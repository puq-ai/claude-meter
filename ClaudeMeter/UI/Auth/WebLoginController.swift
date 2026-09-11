//
//  WebLoginController.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import AppKit
import WebKit

/// How an in-app claude.ai sign-in ended. Always delivered exactly once, including when the
/// user closes the window or the attempt times out, so callers can reliably clear their
/// "signing in…" state.
enum WebLoginOutcome {
    case signedIn(sessionKey: String, organizations: [WebOrganization])
    case cancelled
}

/// Signs the user in to claude.ai in an embedded web view and keeps the resulting session
/// cookie, so the web fallback no longer requires copying a cookie out of browser devtools.
///
/// Two things worth knowing about this approach:
///
/// - It renders claude.ai's real login page inside this app and reads the session cookie the
///   server sets. Nothing is typed into fields this app owns, but it is still a session the
///   app holds on the user's behalf, and it can break without warning if the login flow
///   changes (SSO, an MFA step-up, or bot detection on a non-browser client).
/// - The cookie jar is non-persistent and torn down as soon as the key is captured, so no
///   logged-in browser session lingers inside the app.
@MainActor
final class WebLoginController: NSObject {
    static let shared = WebLoginController()

    /// Long enough to get through SSO and a second factor without leaving a window open forever.
    private static let timeout: TimeInterval = 10 * 60

    private var window: NSWindow?
    private var webView: WKWebView?
    private var dataStore: WKWebsiteDataStore?
    private var statusLabel: NSTextField?
    private var completion: ((WebLoginOutcome) -> Void)?
    private var timeoutTask: Task<Void, Never>?
    private var validationTask: Task<Void, Never>?

    /// Candidates already checked, so a cookie set before sign-in completes isn't re-validated
    /// on every change notification.
    private var rejectedKeys: Set<String> = []
    private var hasDelivered = false

    private let apiService: APIServiceProtocol

    init(apiService: APIServiceProtocol = APIService()) {
        self.apiService = apiService
        super.init()
    }

    // MARK: - Presentation

    func present(completion: @escaping (WebLoginOutcome) -> Void) {
        if window != nil {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        self.completion = completion
        self.hasDelivered = false
        self.rejectedKeys = []

        let store = WKWebsiteDataStore.nonPersistent()
        self.dataStore = store

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        // Identity providers hand off through a popup; without this the call is a no-op.
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        // A browser User-Agent: the CLI's is exactly what a login page's bot detection rejects.
        webView.customUserAgent = Constants.API.webLoginUserAgent
        webView.navigationDelegate = self
        webView.uiDelegate = self
        self.webView = webView

        let status = NSTextField(labelWithString: "")
        status.font = .preferredFont(forTextStyle: .caption1)
        status.textColor = .systemOrange
        status.lineBreakMode = .byWordWrapping
        status.maximumNumberOfLines = 3
        status.isHidden = true
        self.statusLabel = status

        let stack = NSStackView(views: [webView, status])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 12, right: 12)
        stack.setHuggingPriority(.defaultLow, for: .vertical)
        status.setContentHuggingPriority(.defaultHigh, for: .vertical)

        store.httpCookieStore.add(self)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign in to claude.ai"
        window.contentView = stack
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if let url = URL(string: Constants.API.webLoginURL) {
            webView.load(URLRequest(url: url))
        }

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.finish(.cancelled)
        }
    }

    func cancel() {
        finish(.cancelled)
    }

    /// Delivers the outcome exactly once and tears the window down. Every exit path goes
    /// through here: leaving a caller's "signing in…" state stuck on is worse than any of the
    /// failures it reports.
    private func finish(_ outcome: WebLoginOutcome) {
        guard !hasDelivered else { return }
        hasDelivered = true

        let completion = self.completion
        teardown()
        completion?(outcome)
    }

    private func teardown() {
        timeoutTask?.cancel()
        timeoutTask = nil
        validationTask?.cancel()
        validationTask = nil

        dataStore?.httpCookieStore.remove(self)
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView = nil
        // Dropping the non-persistent store discards the browser session with it.
        dataStore = nil
        statusLabel = nil

        window?.delegate = nil
        window?.close()
        window = nil
        completion = nil
    }

    private func showStatus(_ message: String) {
        statusLabel?.stringValue = message
        statusLabel?.isHidden = false
    }

    // MARK: - Cookie capture

    private func captureSessionKeyIfReady() {
        guard !hasDelivered, validationTask == nil, let store = dataStore?.httpCookieStore else { return }

        store.getAllCookies { [weak self] cookies in
            guard let self else { return }
            let candidate = cookies.first {
                $0.name == Constants.API.sessionCookieName && $0.domain.contains("claude.ai")
            }?.value

            guard let candidate, !candidate.isEmpty, !self.rejectedKeys.contains(candidate) else { return }
            self.validate(candidate)
        }
    }

    /// claude.ai can hand out a `sessionKey` before sign-in actually completes, so a cookie on
    /// its own is not proof of anything. Ask the organizations endpoint: it both proves the
    /// session works and yields the organization id the usage endpoint needs.
    ///
    /// The inner guard matters: `getAllCookies` is async, so two rapid change notifications can
    /// both reach this method before either sets `validationTask`.
    private func validate(_ sessionKey: String) {
        guard validationTask == nil else { return }

        validationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.validationTask = nil }

            do {
                let organizations = try await self.apiService.fetchOrganizations(sessionKey: sessionKey)
                guard !Task.isCancelled, !self.hasDelivered else { return }

                guard !organizations.isEmpty else {
                    // A working session that reports no organizations is not something waiting
                    // longer will fix.
                    self.rejectedKeys.insert(sessionKey)
                    self.showStatus("Signed in, but this account has no organizations ClaudeMeter can read usage for.")
                    return
                }

                self.finish(.signedIn(sessionKey: sessionKey, organizations: organizations))
            } catch APIError.unauthorized {
                // Expected until sign-in completes: the cookie exists but isn't authenticated
                // yet. Stay quiet and wait for the next one.
                self.rejectedKeys.insert(sessionKey)
            } catch {
                // Anything else means the endpoint isn't answering the way we expect, and
                // retrying won't help. Say so rather than leaving the window spinning until
                // the timeout.
                self.rejectedKeys.insert(sessionKey)
                self.showStatus("Couldn't confirm the session: \(error.localizedDescription). You can close this and enter the organization ID manually under Settings › Advanced.")
                print("WebLoginController: organization lookup failed - \(error)")
            }
        }
    }
}

// MARK: - WKHTTPCookieStoreObserver

extension WebLoginController: WKHTTPCookieStoreObserver {
    nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor [weak self] in
            self?.captureSessionKeyIfReady()
        }
    }
}

// MARK: - WKUIDelegate

extension WebLoginController: WKUIDelegate {
    /// "Continue with Google" and friends open their flow in a new window (`target="_blank"`
    /// or `window.open`). WKWebView discards those unless this is implemented, so the button
    /// silently did nothing. Load the request in the existing view instead.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame?.isMainFrame != true,
           let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}

// MARK: - WKNavigationDelegate

extension WebLoginController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        checkForBlockedProvider(webView.url)
        captureSessionKeyIfReady()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // Ignore the cancellations WebKit reports for ordinary redirects.
        let nsError = error as NSError
        guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) else { return }
        showStatus("Couldn't load the page: \(error.localizedDescription)")
    }

    /// Some identity providers refuse to run their sign-in flow inside an embedded view at
    /// all. That is their policy and nothing here can change it, so say so plainly rather
    /// than leaving the user on a dead page.
    private func checkForBlockedProvider(_ url: URL?) {
        guard let value = url?.absoluteString.lowercased(),
              value.contains("disallowed_useragent") || value.contains("browser_not_secure") else { return }
        showStatus("This sign-in provider blocks embedded browsers. Use email sign-in here, or connect the Claude Code CLI instead.")
    }
}

// MARK: - NSWindowDelegate

extension WebLoginController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Closed without signing in; leave stored credentials untouched but still report back.
        finish(.cancelled)
    }
}

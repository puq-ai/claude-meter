//
//  WebLoginController.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import AppKit
import WebKit

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
    private var completion: ((String, [WebOrganization]) -> Void)?
    private var timeoutTask: Task<Void, Never>?
    private var validationTask: Task<Void, Never>?

    /// Candidates already checked, so a cookie that is set before sign-in completes isn't
    /// re-validated on every change notification.
    private var rejectedKeys: Set<String> = []
    private var isFinishing = false

    private let apiService: APIServiceProtocol

    init(apiService: APIServiceProtocol = APIService()) {
        self.apiService = apiService
        super.init()
    }

    // MARK: - Presentation

    func present(completion: @escaping (String, [WebOrganization]) -> Void) {
        if window != nil {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        self.completion = completion
        self.isFinishing = false
        self.rejectedKeys = []

        let store = WKWebsiteDataStore.nonPersistent()
        self.dataStore = store

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 680), configuration: configuration)
        // A browser User-Agent: the CLI's is exactly what a login page's bot detection rejects.
        webView.customUserAgent = Constants.API.webLoginUserAgent
        webView.navigationDelegate = self
        self.webView = webView

        store.httpCookieStore.add(self)

        let window = NSWindow(
            contentRect: webView.frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign in to claude.ai"
        window.contentView = webView
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
            self?.dismiss()
        }
    }

    func dismiss() {
        timeoutTask?.cancel()
        timeoutTask = nil
        validationTask?.cancel()
        validationTask = nil

        dataStore?.httpCookieStore.remove(self)
        webView?.navigationDelegate = nil
        webView = nil
        // Dropping the non-persistent store discards the browser session with it.
        dataStore = nil

        window?.delegate = nil
        window?.close()
        window = nil
        completion = nil
    }

    // MARK: - Cookie capture

    private func captureSessionKeyIfReady() {
        guard !isFinishing, validationTask == nil, let store = dataStore?.httpCookieStore else { return }

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
    private func validate(_ sessionKey: String) {
        guard validationTask == nil else { return }

        validationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.validationTask = nil }

            do {
                let organizations = try await self.apiService.fetchOrganizations(sessionKey: sessionKey)
                guard !organizations.isEmpty else {
                    self.rejectedKeys.insert(sessionKey)
                    return
                }
                guard !Task.isCancelled, !self.isFinishing else { return }

                self.isFinishing = true
                let completion = self.completion
                self.dismiss()
                completion?(sessionKey, organizations)
            } catch {
                // Not signed in yet (or the session isn't usable). Wait for the next cookie.
                self.rejectedKeys.insert(sessionKey)
                print("WebLoginController: session key not usable yet - \(error)")
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

// MARK: - WKNavigationDelegate

extension WebLoginController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        captureSessionKeyIfReady()
    }
}

// MARK: - NSWindowDelegate

extension WebLoginController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // The user closed the window without signing in; leave state untouched.
        guard !isFinishing else { return }
        dismiss()
    }
}

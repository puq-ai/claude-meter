//
//  UsageManager.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation
import Combine

/// Where the currently displayed usage data came from.
enum DataSource: String, Equatable {
    case primary
    case webFallback
    case cache
}

/// Whether the app can authenticate at all, and how.
///
/// Previously this was only ever implied by a generic error string, which meant a user who
/// had never logged in saw "No Usage Data - click refresh" and a menu bar reading 0%.
enum AuthState: Equatable {
    /// No fetch has completed yet.
    case unknown
    /// Claude Code CLI credentials are usable.
    case cliAuthenticated
    /// CLI credentials are unusable but the claude.ai session is carrying us.
    case webOnly
    /// Nothing to authenticate with. This is the state that should offer a way in.
    case needsLogin
    /// Credentials exist but were rejected.
    case failed(AppError)

    var needsAttention: Bool {
        switch self {
        case .needsLogin, .failed: return true
        case .unknown, .cliAuthenticated, .webOnly: return false
        }
    }
}

@MainActor
class UsageManager: ObservableObject {
    @Published var usageData: UsageData?
    @Published var isLoading: Bool = false
    @Published var error: Error?

    /// The error the primary (OAuth) API returned on the most recent fetch, even when a
    /// fallback went on to succeed. Polling backoff keys off this rather than `error`,
    /// which a successful fallback clears.
    @Published private(set) var lastPrimaryError: AppError?

    /// Which source served `usageData`.
    @Published private(set) var dataSource: DataSource?

    /// Whether the app can authenticate, and how. Drives the connect screen and the menu bar.
    @Published private(set) var authState: AuthState = .unknown

    private let apiService: APIServiceProtocol
    private let keychainService: KeychainServiceProtocol
    private let cacheManager: CacheManagerProtocol

    /// The CLI's credentials as last read, and when. Re-read once stale, once locally
    /// expired, and whenever the server rejects them.
    private var cachedCredentials: (credentials: ClaudeCredentials, readAt: Date)?

    /// Why the claude.ai fallback failed on the most recent fetch; nil if it was not tried
    /// or succeeded. Distinguishes an expired web session from "never signed in".
    private(set) var lastFallbackError: AppError?

    /// While set, the primary API is known to be rate limited and is skipped in favour of
    /// the fallback, so a rate-limited request isn't spent on every tick.
    private var primaryUnhealthyUntil: Date?

    /// Web API credentials for fallback (set by AppState from settings)
    var webSessionKey: String = ""
    var webOrganizationId: String = ""

    /// Called when the web API returns a refreshed session key
    var onSessionKeyRefreshed: ((String) -> Void)?

    init(
        apiService: APIServiceProtocol = APIService(),
        keychainService: KeychainServiceProtocol = KeychainService(),
        cacheManager: CacheManagerProtocol = CacheManager.shared
    ) {
        self.apiService = apiService
        self.keychainService = keychainService
        self.cacheManager = cacheManager

        // Load cached data on init
        loadCachedData()
    }

    // MARK: - Data Invalidation

    /// Invalidate stale data so UI shows loading state instead of outdated values
    func invalidateStaleData() {
        usageData = nil
        error = nil
        dataSource = nil
        authState = .unknown
        isLoading = true
        print("UsageManager: Stale data invalidated, UI will show loading state")
    }

    /// End the loading placeholder `invalidateStaleData` put up when no fetch replaced it
    /// (every wake attempt was gated), showing the cache as a failed fetch would.
    func endStaleDataPlaceholder() {
        guard usageData == nil else { return }
        isLoading = false
        loadCachedData()
    }

    // MARK: - Fetch Usage

    /// Callers serialize fetches (AppState's fetch guard); this is not reentrant.
    /// - Parameter reloadCredentials: Read the Keychain even if a recent read is cached. For
    ///   explicit refreshes, which may follow `claude auth login` with another account.
    func fetchUsage(reloadCredentials: Bool = false) async {
        isLoading = true
        lastPrimaryError = nil
        lastFallbackError = nil
        defer { isLoading = false }
        // `error` is left in place until this fetch resolves: clearing it up front flipped the
        // footer to "Updated ..." for the whole retry sequence of a fetch that then failed.

        // The primary is rate limited and we have a working alternative: go straight to it
        // instead of spending a request just to be told 429 again.
        if shouldSkipPrimary {
            if let fallbackData = await tryWebAPIFallback() {
                applySuccess(fallbackData, source: .webFallback)
                authState = resolveAuthState(servedByFallback: true)
                return
            }
            // The fallback is the only source inside this window and it just failed.
            // Reopen the primary now rather than leaving the user with nothing until the
            // window elapses.
            primaryUnhealthyUntil = nil
            print("UsageManager: Fallback failed inside primary cooldown, reopening primary")
        }

        var servedByFallback = false
        var localTokenLooksExpired = false
        do {
            let credentials = try await loadCredentials(reload: reloadCredentials)

            // Recorded for error messaging only. There is deliberately no local expiry gate
            // here: the server is the authority on token validity, and a server 401 reaches
            // the fallback path while a client-side clock check would short-circuit it.
            localTokenLooksExpired = !credentials.isValid

            let data: UsageData
            do {
                data = try await apiService.fetchUsageWithRetry(token: credentials.accessToken)
            } catch APIError.unauthorized where !reloadCredentials {
                // The CLI may have rotated the token since it was cached: retry once with a
                // fresh read, and only if it actually changed. A fetch that already read the
                // Keychain has nothing newer to find.
                let fresh = try await loadCredentials(reload: true)
                guard fresh.accessToken != credentials.accessToken else { throw APIError.unauthorized }
                localTokenLooksExpired = !fresh.isValid
                data = try await apiService.fetchUsageWithRetry(token: fresh.accessToken)
            }

            primaryUnhealthyUntil = nil
            applySuccess(data, source: .primary)
        } catch {
            servedByFallback = await handleFetchFailure(error, localTokenLooksExpired: localTokenLooksExpired)
        }

        authState = resolveAuthState(servedByFallback: servedByFallback)
    }

    private func loadCredentials(reload: Bool) async throws -> ClaudeCredentials {
        if !reload, let cached = cachedCredentials, cached.credentials.isValid,
           Date().timeIntervalSince(cached.readAt) < Constants.Credentials.cacheLifetime {
            return cached.credentials
        }
        cachedCredentials = nil
        guard let credentials = try await keychainService.getCredentials() else {
            throw AppError.noCredentials
        }
        cachedCredentials = (credentials, Date())
        return credentials
    }

    /// Derive the auth state from what the primary reported and what served THIS fetch.
    /// `dataSource` is no basis: it keeps naming the last source that succeeded.
    private func resolveAuthState(servedByFallback: Bool) -> AuthState {
        // Either the primary succeeded, or it failed for a reason unrelated to credentials
        // (rate limit, server error) - the credentials themselves are fine. This also covers
        // the skipped-primary path, where `lastPrimaryError` is nil: the window only ever arms
        // on a 429, which says nothing about whether the credentials are good.
        guard let problem = lastPrimaryError, Self.isCredentialProblem(problem) else {
            return .cliAuthenticated
        }

        if servedByFallback { return .webOnly }
        if let fallbackError = lastFallbackError {
            // The claude.ai session was carrying this user and has lapsed: that is what to
            // fix. Any other fallback failure (offline, 5xx) says nothing against the session.
            return fallbackError == .webSessionExpired ? .failed(.webSessionExpired) : .webOnly
        }
        if problem == .noCredentials { return .needsLogin }
        return .failed(problem)
    }

    private static func isCredentialProblem(_ error: AppError) -> Bool {
        switch error {
        case .noCredentials, .invalidCredentials, .credentialsExpired,
             .keychainItemNotFound, .keychainReadFailed:
            return true
        default:
            return false
        }
    }

    // MARK: - Failure Handling

    /// - Returns: Whether the web fallback served data in the primary's place.
    private func handleFetchFailure(_ rawError: Error, localTokenLooksExpired: Bool) async -> Bool {
        let appError = Self.normalize(rawError, localTokenLooksExpired: localTokenLooksExpired)
        lastPrimaryError = appError

        if let fallbackData = await tryWebAPIFallback() {
            // Only park the primary once we know a working alternative exists.
            if case .rateLimited(let retryAfter) = appError {
                primaryUnhealthyUntil = Date().addingTimeInterval(
                    Constants.RateLimit.cooldown(retryAfter: retryAfter)
                )
            }
            applySuccess(fallbackData, source: .webFallback)
            print("UsageManager: Web API fallback succeeded after \(appError)")
            return true
        }

        // A web-only user has no CLI credentials by design; "log in to Claude Code" would
        // send them to the wrong fix. Report what actually stopped the fallback instead.
        if Self.isCredentialProblem(appError), let fallbackError = lastFallbackError {
            self.error = fallbackError
        } else {
            self.error = appError
        }
        print("UsageManager: Fetch failed - \(appError)")

        // Fall back to cache so the popover keeps showing the last known numbers.
        loadCachedData()
        return false
    }

    /// Collapse the three error domains into one `AppError`.
    private static func normalize(_ rawError: Error, localTokenLooksExpired: Bool) -> AppError {
        switch rawError {
        case let apiError as APIError:
            // A 401 on a token our own clock already considers stale is an expiry, not a
            // malformed credential. The distinction matters: the recovery differs.
            if case .unauthorized = apiError, localTokenLooksExpired {
                return .credentialsExpired
            }
            return AppError.from(apiError)
        case let keychainError as KeychainError:
            return AppError.from(keychainError)
        case let appError as AppError:
            return appError
        case is URLError, is CancellationError:
            return AppError.from(transportError: rawError)
        default:
            return .unknown(rawError.localizedDescription)
        }
    }

    private func applySuccess(_ data: UsageData, source: DataSource) {
        // Source first: `usageData` subscribers read it to tell fresh data from cache.
        self.dataSource = source
        self.usageData = data
        self.error = nil
        cacheManager.cacheUsageData(data)
    }

    // MARK: - Web API Fallback

    var isWebFallbackConfigured: Bool {
        !webSessionKey.isEmpty && !webOrganizationId.isEmpty
    }

    private var shouldSkipPrimary: Bool {
        guard isWebFallbackConfigured, let until = primaryUnhealthyUntil else { return false }
        return Date() < until
    }

    private func tryWebAPIFallback() async -> UsageData? {
        // Once per fetch: after a failure inside the primary's cooldown, the primary is
        // reopened, and if it fails too the same fallback request would just fail again.
        guard isWebFallbackConfigured, lastFallbackError == nil else { return nil }
        do {
            let (data, refreshedKey) = try await apiService.fetchUsageFromWeb(
                sessionKey: webSessionKey,
                organizationId: webOrganizationId
            )
            if let refreshedKey = refreshedKey {
                self.webSessionKey = refreshedKey
                onSessionKeyRefreshed?(refreshedKey)
            }
            return data
        } catch {
            if case APIError.unauthorized? = error as? APIError {
                lastFallbackError = .webSessionExpired
            } else {
                lastFallbackError = Self.normalize(error, localTokenLooksExpired: false)
            }
            print("UsageManager: Web API fallback failed - \(error)")
            return nil
        }
    }

    // MARK: - Cache

    private func loadCachedData() {
        // Only use cache if we don't have fresher data
        guard usageData == nil else { return }
        if let cached = cacheManager.getCachedUsageData(maxAge: nil) {
            dataSource = .cache
            usageData = cached
        }
    }

    // MARK: - Credentials Check

    func hasCredentials() async -> Bool {
        await keychainService.hasCredentials()
    }
}

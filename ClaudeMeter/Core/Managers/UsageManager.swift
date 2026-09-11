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

    private let apiService: APIServiceProtocol
    private let keychainService: KeychainServiceProtocol
    private let cacheManager: CacheManagerProtocol
    private var isFetching: Bool = false

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
        isLoading = true
        print("UsageManager: Stale data invalidated, UI will show loading state")
    }

    // MARK: - Fetch Usage

    func fetchUsage() async {
        guard !isFetching else {
            print("UsageManager: Fetch already in progress, skipping")
            return
        }
        isFetching = true
        defer { isFetching = false }

        isLoading = true
        error = nil
        lastPrimaryError = nil
        defer { isLoading = false }

        // The primary is rate limited and we have a working alternative: go straight to it
        // instead of spending a request just to be told 429 again.
        if shouldSkipPrimary {
            if let fallbackData = await tryWebAPIFallback() {
                applySuccess(fallbackData, source: .webFallback)
                return
            }
            // The fallback is the only source inside this window and it just failed.
            // Reopen the primary now rather than leaving the user with nothing until the
            // window elapses.
            primaryUnhealthyUntil = nil
            print("UsageManager: Fallback failed inside primary cooldown, reopening primary")
        }

        var localTokenLooksExpired = false
        do {
            guard let credentials = try keychainService.getCredentials() else {
                throw AppError.noCredentials
            }

            // Recorded for error messaging only. There is deliberately no local expiry gate
            // here: the server is the authority on token validity, and a server 401 reaches
            // the fallback path while a client-side clock check would short-circuit it.
            localTokenLooksExpired = !credentials.isValid

            let data = try await apiService.fetchUsageWithRetry(token: credentials.accessToken)

            primaryUnhealthyUntil = nil
            applySuccess(data, source: .primary)
        } catch {
            await handleFetchFailure(error, localTokenLooksExpired: localTokenLooksExpired)
        }
    }

    // MARK: - Failure Handling

    private func handleFetchFailure(_ rawError: Error, localTokenLooksExpired: Bool) async {
        let appError = Self.normalize(rawError, localTokenLooksExpired: localTokenLooksExpired)
        lastPrimaryError = appError

        if let fallbackData = await tryWebAPIFallback() {
            // Only park the primary once we know a working alternative exists.
            if case .rateLimited(let retryAfter) = appError {
                let cooldown = min(
                    retryAfter ?? Constants.RateLimit.defaultCooldownDuration,
                    Constants.RateLimit.maxCooldownDuration
                )
                primaryUnhealthyUntil = Date().addingTimeInterval(cooldown)
            }
            applySuccess(fallbackData, source: .webFallback)
            print("UsageManager: Web API fallback succeeded after \(appError)")
            return
        }

        self.error = appError
        print("UsageManager: Fetch failed - \(appError)")

        // Fall back to cache so the popover keeps showing the last known numbers.
        loadCachedData()
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
        default:
            return .unknown(rawError.localizedDescription)
        }
    }

    private func applySuccess(_ data: UsageData, source: DataSource) {
        self.usageData = data
        self.error = nil
        self.dataSource = source
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
        guard isWebFallbackConfigured else { return nil }
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
            print("UsageManager: Web API fallback failed - \(error)")
            return nil
        }
    }

    // MARK: - Cache

    private func loadCachedData() {
        // Only use cache if we don't have fresher data
        guard usageData == nil else { return }
        if let cached = cacheManager.getCachedUsageData(maxAge: nil) {
            usageData = cached
            dataSource = .cache
        }
    }

    /// Force refresh, ignoring cache
    func forceRefresh() async {
        cacheManager.clearCache()
        await fetchUsage()
    }

    // MARK: - Credentials Check

    var hasCredentials: Bool {
        return keychainService.hasCredentials()
    }

    func validateCredentials() async -> Bool {
        guard let credentials = try? keychainService.getCredentials() else {
            return false
        }
        return await apiService.validateToken(credentials.accessToken)
    }
}

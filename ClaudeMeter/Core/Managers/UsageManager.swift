//
//  UsageManager.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation
import Combine

@MainActor
class UsageManager: ObservableObject {
    @Published var usageData: UsageData?
    @Published var isLoading: Bool = false
    @Published var error: Error?

    private let apiService: APIServiceProtocol
    private let keychainService: KeychainServiceProtocol
    private let cacheManager: CacheManagerProtocol
    private var isFetching: Bool = false

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

        do {
            // 1. Get Token
            guard let credentials = try keychainService.getCredentials() else {
                throw AppError.noCredentials
            }

            // Check if credentials are valid
            guard credentials.isValid else {
                throw AppError.credentialsExpired
            }

            // 2. Fetch Data with retry
            let data = try await apiService.fetchUsageWithRetry(token: credentials.accessToken)

            // 3. Update State
            self.usageData = data
            self.error = nil

            // 4. Cache the data
            cacheManager.cacheUsageData(data)

        } catch let error as APIError {
            self.error = AppError.from(error)
            print("UsageManager: API error - \(error)")

            // Try to use cached data on error
            loadCachedData()

        } catch let error as KeychainError {
            self.error = AppError.from(error)
            print("UsageManager: Keychain error - \(error)")

        } catch let error as AppError {
            self.error = error
            print("UsageManager: App error - \(error)")

            // Try to use cached data on error
            if error.shouldRetry {
                loadCachedData()
            }

        } catch {
            self.error = AppError.unknown(error.localizedDescription)
            print("UsageManager: Unknown error - \(error)")
        }

        isLoading = false
    }

    // MARK: - Cache

    private func loadCachedData() {
        if let cached = cacheManager.getCachedUsageData(maxAge: nil) {
            // Only use cache if we don't have fresh data
            if usageData == nil {
                usageData = cached
            }
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

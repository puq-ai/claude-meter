//
//  DependencyContainer.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation

/// Centralized dependency container for service instantiation and injection
final class DependencyContainer {
    static let shared = DependencyContainer()

    // MARK: - Lazy Service Instances

    private lazy var _apiService: APIServiceProtocol = APIService()
    private lazy var _keychainService: KeychainServiceProtocol = KeychainService()
    private lazy var _cacheManager: CacheManagerProtocol = CacheManager.shared
    private lazy var _notificationService: NotificationServiceProtocol = NotificationService.shared

    // MARK: - Public Accessors

    var apiService: APIServiceProtocol {
        #if DEBUG
        return testAPIService ?? _apiService
        #else
        return _apiService
        #endif
    }

    var keychainService: KeychainServiceProtocol {
        #if DEBUG
        return testKeychainService ?? _keychainService
        #else
        return _keychainService
        #endif
    }

    var cacheManager: CacheManagerProtocol {
        #if DEBUG
        return testCacheManager ?? _cacheManager
        #else
        return _cacheManager
        #endif
    }

    var notificationService: NotificationServiceProtocol {
        #if DEBUG
        return testNotificationService ?? _notificationService
        #else
        return _notificationService
        #endif
    }

    // MARK: - Test Injection Support

    #if DEBUG
    var testAPIService: APIServiceProtocol?
    var testKeychainService: KeychainServiceProtocol?
    var testCacheManager: CacheManagerProtocol?
    var testNotificationService: NotificationServiceProtocol?

    /// Reset all test overrides
    func resetTestOverrides() {
        testAPIService = nil
        testKeychainService = nil
        testCacheManager = nil
        testNotificationService = nil
    }
    #endif

    // MARK: - Factory Methods

    /// Create a UsageManager with the container's services
    @MainActor
    func makeUsageManager() -> UsageManager {
        return UsageManager(
            apiService: apiService,
            keychainService: keychainService,
            cacheManager: cacheManager
        )
    }

    // MARK: - Private Init

    private init() {}
}

//
//  MockCacheManager.swift
//  ClaudeMeterTests
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation
@testable import ClaudeMeter

/// Mock cache manager for testing
class MockCacheManager: CacheManagerProtocol {
    // MARK: - Storage
    private var cachedData: UsageData?
    private var cacheTimestamp: Date?

    // MARK: - Call Tracking
    var cacheUsageDataCallCount = 0
    var getCachedUsageDataCallCount = 0

    // MARK: - CacheManagerProtocol

    func cacheUsageData(_ data: UsageData) {
        cacheUsageDataCallCount += 1
        cachedData = data
        cacheTimestamp = Date()
    }

    func getCachedUsageData(maxAge: TimeInterval?) -> UsageData? {
        getCachedUsageDataCallCount += 1

        guard let data = cachedData, let timestamp = cacheTimestamp else {
            return nil
        }

        if let maxAge = maxAge {
            if Date().timeIntervalSince(timestamp) > maxAge {
                return nil
            }
        }

        return data
    }

    // MARK: - Test Helpers

    func setCachedData(_ data: UsageData, timestamp: Date = Date()) {
        cachedData = data
        cacheTimestamp = timestamp
    }

    // MARK: - Reset

    func reset() {
        cachedData = nil
        cacheTimestamp = nil
        cacheUsageDataCallCount = 0
        getCachedUsageDataCallCount = 0
    }
}

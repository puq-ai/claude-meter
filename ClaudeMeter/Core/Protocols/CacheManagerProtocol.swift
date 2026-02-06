//
//  CacheManagerProtocol.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation

/// Protocol defining the cache manager interface for data persistence
protocol CacheManagerProtocol {
    /// Cache usage data to disk
    /// - Parameter data: UsageData to cache
    func cacheUsageData(_ data: UsageData)

    /// Retrieve cached usage data
    /// - Parameter maxAge: Maximum age of cache in seconds (optional)
    /// - Returns: Cached UsageData if available and not expired
    func getCachedUsageData(maxAge: TimeInterval?) -> UsageData?

    /// Clear all cached data
    func clearCache()

    /// Check if cache exists and is valid
    var hasCachedData: Bool { get }

    /// Get the age of the cached data
    var cacheAge: TimeInterval? { get }
}

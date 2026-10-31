//
//  CacheManager.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation

/// Manages offline caching of usage data
class CacheManager: CacheManagerProtocol {
    static let shared = CacheManager()

    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let usageDataFile = Constants.Cache.usageDataFilename
    private let maxCacheAge: TimeInterval = Constants.Cache.maxAge

    // Cache version for migration support
    static let cacheVersion = Constants.Cache.version

    private init() {
        // Get cache directory with safe fallback
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        cacheDirectory = caches.appendingPathComponent(Constants.Cache.directoryName, isDirectory: true)

        // Create cache directory if needed
        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        } catch {
            print("CacheManager: Failed to create cache directory - \(error)")
        }
    }

    // MARK: - Usage Data Cache

    /// Cache usage data to disk
    /// - Parameter data: UsageData to cache
    func cacheUsageData(_ data: UsageData) {
        let cacheEntry = CacheEntry(data: data, timestamp: Date(), version: Self.cacheVersion)

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let jsonData = try encoder.encode(cacheEntry)

            let fileURL = cacheDirectory.appendingPathComponent(usageDataFile)
            // Atomic: a crash mid-write must not leave a truncated file that fails to decode.
            try jsonData.write(to: fileURL, options: .atomic)
        } catch {
            print("CacheManager: Failed to cache usage data - \(error)")
        }
    }

    /// Retrieve cached usage data
    /// - Parameter maxAge: Maximum age of cache in seconds (default: 24 hours)
    /// - Returns: Cached UsageData if available and not expired
    func getCachedUsageData(maxAge: TimeInterval? = nil) -> UsageData? {
        let fileURL = cacheDirectory.appendingPathComponent(usageDataFile)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let cacheEntry = try decoder.decode(CacheEntry<UsageData>.self, from: data)

            // Check if cache is still valid
            let effectiveMaxAge = maxAge ?? maxCacheAge
            if Date().timeIntervalSince(cacheEntry.timestamp) < effectiveMaxAge {
                return cacheEntry.data
            } else {
                // Cache expired, delete it
                try? fileManager.removeItem(at: fileURL)
                return nil
            }
        } catch {
            print("CacheManager: Failed to read cached usage data - \(error)")
            return nil
        }
    }
}

// MARK: - Cache Entry

private struct CacheEntry<T: Codable>: Codable {
    let data: T
    let timestamp: Date
    let version: Int

    init(data: T, timestamp: Date, version: Int = CacheManager.cacheVersion) {
        self.data = data
        self.timestamp = timestamp
        self.version = version
    }
}

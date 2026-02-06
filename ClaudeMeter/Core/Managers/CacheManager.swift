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
            try jsonData.write(to: fileURL)
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

    /// Check if cache exists and is valid
    var hasCachedData: Bool {
        return getCachedUsageData() != nil
    }

    /// Get the age of the cached data (uses embedded timestamp, not file date)
    var cacheAge: TimeInterval? {
        let fileURL = cacheDirectory.appendingPathComponent(usageDataFile)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let cacheEntry = try decoder.decode(CacheEntry<UsageData>.self, from: data)
            return Date().timeIntervalSince(cacheEntry.timestamp)
        } catch {
            return nil
        }
    }

    // MARK: - Cache Management

    /// Clear all cached data
    func clearCache() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// Get total cache size in bytes
    var cacheSize: Int64 {
        guard let enumerator = fileManager.enumerator(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else {
            return 0
        }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                  let fileSize = resourceValues.fileSize else {
                continue
            }
            totalSize += Int64(fileSize)
        }
        return totalSize
    }

    /// Format cache size for display
    var formattedCacheSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: cacheSize)
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

// MARK: - Cache Key Protocol

protocol CacheKey: RawRepresentable where RawValue == String {}

//
//  MockAPIService.swift
//  ClaudeMeterTests
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation
@testable import ClaudeMeter

/// Mock API service for testing
class MockAPIService: APIServiceProtocol {
    // MARK: - Call Tracking
    var fetchUsageCallCount = 0
    var fetchUsageWithRetryCallCount = 0
    var validateTokenCallCount = 0
    var lastToken: String?

    // MARK: - Stubbed Responses
    var stubbedUsageData: UsageData?
    var stubbedError: Error?
    var stubbedTokenValid = true

    // MARK: - APIServiceProtocol

    func fetchUsage(token: String) async throws -> UsageData {
        fetchUsageCallCount += 1
        lastToken = token

        if let error = stubbedError {
            throw error
        }

        guard let data = stubbedUsageData else {
            throw APIError.noData
        }

        return data
    }

    func fetchUsageWithRetry(token: String) async throws -> UsageData {
        fetchUsageWithRetryCallCount += 1
        lastToken = token

        if let error = stubbedError {
            throw error
        }

        guard let data = stubbedUsageData else {
            throw APIError.noData
        }

        return data
    }

    func validateToken(_ token: String) async -> Bool {
        validateTokenCallCount += 1
        lastToken = token
        return stubbedTokenValid
    }

    // MARK: - Reset

    func reset() {
        fetchUsageCallCount = 0
        fetchUsageWithRetryCallCount = 0
        validateTokenCallCount = 0
        lastToken = nil
        stubbedUsageData = nil
        stubbedError = nil
        stubbedTokenValid = true
    }
}

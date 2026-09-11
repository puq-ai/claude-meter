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

    // MARK: - Web Fallback (kept separate from the primary stubs so a test can make the
    // primary fail while the fallback succeeds - the whole point of the fallback)
    var fetchUsageFromWebCallCount = 0
    var lastWebSessionKey: String?
    var lastWebOrganizationId: String?
    var stubbedWebUsageData: UsageData?
    var stubbedWebError: Error?
    var stubbedRefreshedSessionKey: String?
    var fetchOrganizationsCallCount = 0
    var stubbedOrganizations: [WebOrganization] = []
    var stubbedOrganizationsError: Error?

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

    func fetchUsageFromWeb(sessionKey: String, organizationId: String) async throws -> (UsageData, String?) {
        fetchUsageFromWebCallCount += 1
        lastWebSessionKey = sessionKey
        lastWebOrganizationId = organizationId

        if let error = stubbedWebError {
            throw error
        }

        guard let data = stubbedWebUsageData else {
            throw APIError.noData
        }

        return (data, stubbedRefreshedSessionKey)
    }

    func fetchOrganizations(sessionKey: String, cookies: [HTTPCookie]) async throws -> [WebOrganization] {
        fetchOrganizationsCallCount += 1
        lastWebSessionKey = sessionKey
        if let error = stubbedOrganizationsError {
            throw error
        }
        return stubbedOrganizations
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
        fetchUsageFromWebCallCount = 0
        lastWebSessionKey = nil
        lastWebOrganizationId = nil
        stubbedWebUsageData = nil
        stubbedWebError = nil
        stubbedRefreshedSessionKey = nil
        fetchOrganizationsCallCount = 0
        stubbedOrganizations = []
        stubbedOrganizationsError = nil
    }
}

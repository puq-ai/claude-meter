//
//  APIServiceProtocol.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation

/// Protocol defining the API service interface for fetching usage data
protocol APIServiceProtocol {
    /// Fetch usage data without retry
    /// - Parameter token: The authentication token
    /// - Returns: UsageData from the API
    func fetchUsage(token: String) async throws -> UsageData

    /// Fetch usage data with automatic retry and exponential backoff
    /// - Parameter token: The authentication token
    /// - Returns: UsageData from the API
    func fetchUsageWithRetry(token: String) async throws -> UsageData

    /// Validate if a token is valid
    /// - Parameter token: The authentication token to validate
    /// - Returns: True if the token is valid
    func validateToken(_ token: String) async -> Bool

    /// Fetch usage data from the web API (claude.ai) as a fallback
    /// Returns a tuple of (UsageData, refreshedSessionKey?)
    func fetchUsageFromWeb(sessionKey: String, organizationId: String) async throws -> (UsageData, String?)

    /// List the organizations the claude.ai session can see, so the organization id can be
    /// resolved automatically instead of being copied out of a browser URL by hand.
    /// - Parameter cookies: every cookie the browser session holds. claude.ai sits behind a
    ///   bot-management layer that sets its own cookies; sending only `sessionKey` gets the
    ///   request rejected even when the session itself is valid.
    func fetchOrganizations(sessionKey: String, cookies: [HTTPCookie]) async throws -> [WebOrganization]
}

extension APIServiceProtocol {
    func fetchOrganizations(sessionKey: String) async throws -> [WebOrganization] {
        try await fetchOrganizations(sessionKey: sessionKey, cookies: [])
    }
}

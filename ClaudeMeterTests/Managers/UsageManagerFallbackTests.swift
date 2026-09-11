//
//  UsageManagerFallbackTests.swift
//  ClaudeMeterTests
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import XCTest
@testable import ClaudeMeter

/// Coverage for the claude.ai web fallback: when it is reached, when the primary is
/// skipped in its favour, and how the two recover from each other's failures.
@MainActor
final class UsageManagerFallbackTests: XCTestCase {
    var sut: UsageManager!
    var mockAPIService: MockAPIService!
    var mockKeychainService: MockKeychainService!
    var mockCacheManager: MockCacheManager!

    /// Distinct utilizations so an assertion can tell which source served the data.
    private let primaryUsage = 11.0
    private let fallbackUsage = 77.0

    override func setUp() {
        super.setUp()
        mockAPIService = MockAPIService()
        mockKeychainService = MockKeychainService()
        mockCacheManager = MockCacheManager()
        sut = UsageManager(
            apiService: mockAPIService,
            keychainService: mockKeychainService,
            cacheManager: mockCacheManager
        )
    }

    override func tearDown() {
        sut = nil
        mockAPIService = nil
        mockKeychainService = nil
        mockCacheManager = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func configureFallback() {
        sut.webSessionKey = "session-key-abc"
        sut.webOrganizationId = "org-uuid-123"
        mockAPIService.stubbedWebUsageData = TestData.makeUsageData(fiveHourUsage: fallbackUsage)
    }

    private func configurePrimary() {
        mockKeychainService.stubbedCredentials = TestData.makeCredentials()
        mockAPIService.stubbedUsageData = TestData.makeUsageData(fiveHourUsage: primaryUsage)
    }

    private var servedUsage: Double? {
        sut.usageData?.fiveHour?.utilization
    }

    /// Drive the manager into the state where the primary is parked: primary 429s and the
    /// fallback covers for it.
    private func armPrimaryCooldown(retryAfter: TimeInterval? = 120) async {
        configureFallback()
        mockKeychainService.stubbedCredentials = TestData.makeCredentials()
        mockAPIService.stubbedError = APIError.rateLimited(retryAfter: retryAfter)
        await sut.fetchUsage()
        XCTAssertEqual(servedUsage, fallbackUsage, "precondition: fallback should have served")
    }

    // MARK: - Reachability

    func testFallback_IsReachedWhenNoCredentialsExist() async {
        configureFallback()
        mockKeychainService.stubbedCredentials = nil

        await sut.fetchUsage()

        XCTAssertEqual(mockAPIService.fetchUsageFromWebCallCount, 1,
                       "no credentials is exactly the case the fallback exists for")
        XCTAssertEqual(servedUsage, fallbackUsage)
        XCTAssertNil(sut.error)
        XCTAssertEqual(sut.lastPrimaryError, .noCredentials)
        XCTAssertEqual(sut.dataSource, .webFallback)
    }

    func testFallback_IsNotAttemptedWhenUnconfigured() async {
        mockKeychainService.stubbedCredentials = nil

        await sut.fetchUsage()

        XCTAssertEqual(mockAPIService.fetchUsageFromWebCallCount, 0)
        XCTAssertEqual(sut.error as? AppError, .noCredentials)
    }

    func testFallback_PassesConfiguredCredentials() async {
        configureFallback()
        mockKeychainService.stubbedCredentials = nil

        await sut.fetchUsage()

        XCTAssertEqual(mockAPIService.lastWebSessionKey, "session-key-abc")
        XCTAssertEqual(mockAPIService.lastWebOrganizationId, "org-uuid-123")
    }

    func testRefreshedSessionKey_IsStoredAndReported() async {
        configureFallback()
        mockKeychainService.stubbedCredentials = nil
        mockAPIService.stubbedRefreshedSessionKey = "rotated-key-xyz"

        var reported: String?
        sut.onSessionKeyRefreshed = { reported = $0 }

        await sut.fetchUsage()

        XCTAssertEqual(reported, "rotated-key-xyz")
        XCTAssertEqual(sut.webSessionKey, "rotated-key-xyz")
    }

    // MARK: - No local expiry gate

    func testLocallyExpiredToken_StillAttemptsPrimary() async {
        configurePrimary()
        mockKeychainService.stubbedCredentials = TestData.makeExpiredCredentials()

        await sut.fetchUsage()

        XCTAssertEqual(mockAPIService.fetchUsageWithRetryCallCount, 1,
                       "the server is the authority on token validity, not the local clock")
        XCTAssertEqual(servedUsage, primaryUsage)
        XCTAssertNil(sut.error)
    }

    func testLocallyExpiredToken_ServerRejection_ReportsExpiryNotInvalidCredentials() async {
        mockKeychainService.stubbedCredentials = TestData.makeExpiredCredentials()
        mockAPIService.stubbedError = APIError.unauthorized

        await sut.fetchUsage()

        XCTAssertEqual(sut.error as? AppError, .credentialsExpired,
                       "a 401 on an already-stale token is an expiry; the recovery differs")
    }

    func testValidToken_ServerRejection_ReportsInvalidCredentials() async {
        mockKeychainService.stubbedCredentials = TestData.makeCredentials()
        mockAPIService.stubbedError = APIError.unauthorized

        await sut.fetchUsage()

        XCTAssertEqual(sut.error as? AppError, .invalidCredentials)
    }

    // MARK: - Primary error survives a successful fallback

    func testRateLimitedPrimary_IsReportedEvenWhenFallbackSucceeds() async {
        await armPrimaryCooldown(retryAfter: 90)

        XCTAssertNil(sut.error, "the user got data, so no error should surface")
        XCTAssertEqual(sut.lastPrimaryError, .rateLimited(retryAfter: 90),
                       "polling backoff needs the primary's 429 even though the user saw data")
        XCTAssertEqual(sut.dataSource, .webFallback)
    }

    // MARK: - Primary cooldown window

    func testPrimaryIsSkippedWhileRateLimited() async {
        await armPrimaryCooldown()
        let callsAfterArming = mockAPIService.fetchUsageWithRetryCallCount

        await sut.fetchUsage()

        XCTAssertEqual(mockAPIService.fetchUsageWithRetryCallCount, callsAfterArming,
                       "no point spending a request just to be told 429 again")
        XCTAssertEqual(mockAPIService.fetchUsageFromWebCallCount, 2)
        XCTAssertEqual(servedUsage, fallbackUsage)
    }

    func testMissingRetryAfter_StillArmsTheWindow() async {
        await armPrimaryCooldown(retryAfter: nil)
        let callsAfterArming = mockAPIService.fetchUsageWithRetryCallCount

        await sut.fetchUsage()

        XCTAssertEqual(mockAPIService.fetchUsageWithRetryCallCount, callsAfterArming,
                       "a missing Retry-After must fall back to the shared default, not to zero")
    }

    /// The regression that turns the optimization into an outage: inside the cooldown the
    /// primary is skipped, so if the fallback also fails the user has nothing at all.
    func testFallbackFailingInsideCooldown_ReopensPrimaryImmediately() async {
        await armPrimaryCooldown()
        let callsAfterArming = mockAPIService.fetchUsageWithRetryCallCount

        // The cookie expires while the primary is parked, and the primary has recovered.
        mockAPIService.stubbedWebError = APIError.unauthorized
        mockAPIService.stubbedError = nil
        mockAPIService.stubbedUsageData = TestData.makeUsageData(fiveHourUsage: primaryUsage)

        await sut.fetchUsage()

        XCTAssertEqual(mockAPIService.fetchUsageWithRetryCallCount, callsAfterArming + 1,
                       "the primary must be retried in the same call, not after the window elapses")
        XCTAssertEqual(servedUsage, primaryUsage)
        XCTAssertNil(sut.error)
        XCTAssertEqual(sut.dataSource, .primary)
    }

    func testSuccessfulPrimary_ClearsTheCooldown() async {
        await armPrimaryCooldown()

        mockAPIService.stubbedError = nil
        mockAPIService.stubbedUsageData = TestData.makeUsageData(fiveHourUsage: primaryUsage)
        mockAPIService.stubbedWebError = APIError.unauthorized

        await sut.fetchUsage()   // reopens the primary, which succeeds
        let callsAfterRecovery = mockAPIService.fetchUsageWithRetryCallCount

        await sut.fetchUsage()

        XCTAssertEqual(mockAPIService.fetchUsageWithRetryCallCount, callsAfterRecovery + 1,
                       "once the primary works again it must stay the preferred source")
        XCTAssertEqual(sut.dataSource, .primary)
    }

    // MARK: - Provenance

    func testDataSource_ReportsCacheWhenEverythingFails() async {
        mockCacheManager.setCachedData(TestData.makeUsageData(fiveHourUsage: 42.0))
        mockKeychainService.stubbedCredentials = nil

        await sut.fetchUsage()

        XCTAssertEqual(sut.dataSource, .cache)
        XCTAssertEqual(servedUsage, 42.0)
        XCTAssertEqual(sut.error as? AppError, .noCredentials,
                       "cached numbers are shown, but the auth failure must still surface")
    }
}

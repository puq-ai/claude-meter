//
//  UsageManagerTests.swift
//  ClaudeMeterTests
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import XCTest
@testable import ClaudeMeter

@MainActor
final class UsageManagerTests: XCTestCase {
    var sut: UsageManager!
    var mockAPIService: MockAPIService!
    var mockKeychainService: MockKeychainService!
    var mockCacheManager: MockCacheManager!

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

    // MARK: - Initial State Tests

    func testInitialState_UsageDataIsNil() {
        // With empty mock cache, usageData should be nil
        XCTAssertNil(sut.usageData)
    }

    func testInitialState_IsLoadingIsFalse() {
        XCTAssertFalse(sut.isLoading)
    }

    func testInitialState_ErrorIsNil() {
        XCTAssertNil(sut.error)
    }

    // MARK: - Fetch Tests

    func testFetchUsage_WithNoCredentials_SetsError() async {
        // Given: No credentials
        mockKeychainService.stubbedCredentials = nil

        // When
        await sut.fetchUsage()

        // Then
        XCTAssertFalse(sut.isLoading)
        XCTAssertNotNil(sut.error)
    }

    func testFetchUsage_WithValidCredentials_UpdatesUsageData() async {
        // Given: Valid credentials and successful API response
        let expectedData = TestData.makeUsageData()
        mockKeychainService.stubbedCredentials = TestData.makeCredentials()
        mockAPIService.stubbedUsageData = expectedData

        // When
        await sut.fetchUsage()

        // Then
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.error)
        XCTAssertNotNil(sut.usageData)
    }

    func testFetchUsage_CachesDataOnSuccess() async {
        // Given
        let expectedData = TestData.makeUsageData()
        mockKeychainService.stubbedCredentials = TestData.makeCredentials()
        mockAPIService.stubbedUsageData = expectedData

        // When
        await sut.fetchUsage()

        // Then
        XCTAssertEqual(mockCacheManager.cacheUsageDataCallCount, 1)
    }

    func testInitialState_LoadsCachedData() {
        // Given: Cache has data
        let cachedData = TestData.makeUsageData()
        mockCacheManager.setCachedData(cachedData)

        // When: Create new manager with pre-populated cache
        let newSut = UsageManager(
            apiService: mockAPIService,
            keychainService: mockKeychainService,
            cacheManager: mockCacheManager
        )

        // Then: Should load cached data
        XCTAssertNotNil(newSut.usageData)
    }
}

// MARK: - UsageData Tests

final class UsageDataTests: XCTestCase {

    func testUsageData_Decoding() throws {
        // Given - JSON with snake_case keys as expected from API
        let json = """
        {
            "five_hour": {
                "utilization": 45.5,
                "resets_at": "2025-01-01T12:00:00Z"
            },
            "seven_day": {
                "utilization": 23.0,
                "resets_at": "2025-01-07T00:00:00Z"
            },
            "seven_day_opus": null
        }
        """.data(using: .utf8)!

        // When - Using default decoder (model has explicit CodingKeys)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let usageData = try decoder.decode(UsageData.self, from: json)

        // Then
        XCTAssertNotNil(usageData.fiveHour)
        XCTAssertEqual(usageData.fiveHour?.utilization, 45.5)
        XCTAssertNotNil(usageData.sevenDay)
        XCTAssertEqual(usageData.sevenDay?.utilization, 23.0)
        XCTAssertNil(usageData.sevenDayOpus)
    }

    func testUsageWindow_Decoding() throws {
        // Given - JSON with snake_case keys
        let json = """
        {
            "utilization": 75.0,
            "resets_at": "2025-01-01T12:00:00Z"
        }
        """.data(using: .utf8)!

        // When
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let window = try decoder.decode(UsageWindow.self, from: json)

        // Then
        XCTAssertEqual(window.utilization, 75.0)
        XCTAssertNotNil(window.resetsAt)
    }

    func testUsageData_Equatable() {
        // Given
        let window1 = UsageWindow(utilization: 50.0, resetsAt: nil)
        let window2 = UsageWindow(utilization: 50.0, resetsAt: nil)
        let date = Date()

        let data1 = UsageData(fiveHour: window1, sevenDay: nil, sevenDayOpus: nil, fetchedAt: date)
        let data2 = UsageData(fiveHour: window2, sevenDay: nil, sevenDayOpus: nil, fetchedAt: date)

        // Then
        XCTAssertEqual(data1, data2)
    }
}

// MARK: - AppSettings Tests

final class AppSettingsTests: XCTestCase {

    func testDefaultSettings() {
        let settings = AppSettings()

        XCTAssertEqual(settings.displayMode, .compact)
        XCTAssertEqual(settings.refreshInterval, 60)
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertTrue(settings.notificationsEnabled)
        XCTAssertEqual(settings.notifyAt, [75, 90, 95])
    }

    func testShouldNotify_EnabledThreshold() {
        var settings = AppSettings()
        settings.notificationsEnabled = true
        settings.notifyAt = [75, 90]

        XCTAssertTrue(settings.shouldNotify(at: 75))
        XCTAssertTrue(settings.shouldNotify(at: 90))
        XCTAssertFalse(settings.shouldNotify(at: 95))
    }

    func testShouldNotify_DisabledNotifications() {
        var settings = AppSettings()
        settings.notificationsEnabled = false
        settings.notifyAt = [75, 90, 95]

        XCTAssertFalse(settings.shouldNotify(at: 75))
        XCTAssertFalse(settings.shouldNotify(at: 90))
        XCTAssertFalse(settings.shouldNotify(at: 95))
    }

    func testSortedThresholds() {
        var settings = AppSettings()
        settings.notifyAt = [95, 75, 90]

        XCTAssertEqual(settings.sortedThresholds, [75, 90, 95])
    }

    func testNotifyAt90_BackwardsCompatibility() {
        var settings = AppSettings()
        settings.notifyAt = [75, 95]

        XCTAssertFalse(settings.notifyAt90)

        settings.notifyAt90 = true
        XCTAssertTrue(settings.notifyAt.contains(90))
        XCTAssertTrue(settings.notifyAt90)

        settings.notifyAt90 = false
        XCTAssertFalse(settings.notifyAt.contains(90))
    }

    func testSettings_Encoding_Decoding() throws {
        // Given
        var settings = AppSettings()
        settings.displayMode = .detailed
        settings.refreshInterval = 120
        settings.launchAtLogin = true
        settings.notifyAt = [80, 90]

        // When
        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)

        // Then
        XCTAssertEqual(decoded.displayMode, .detailed)
        XCTAssertEqual(decoded.refreshInterval, 120)
        XCTAssertTrue(decoded.launchAtLogin)
        XCTAssertEqual(decoded.notifyAt, [80, 90])
    }
}

// MARK: - PollingManager Tests

final class PollingManagerTests: XCTestCase {
    var sut: PollingManager!

    override func setUp() {
        super.setUp()
        sut = PollingManager()
    }

    override func tearDown() {
        sut.stop()
        sut = nil
        super.tearDown()
    }

    func testCalculateInterval_LowUsage() {
        // Given usage < 50%
        let interval = sut.calculateInterval(for: 30)

        // Then interval should be longer than default
        XCTAssertGreaterThan(interval, 60)
    }

    func testCalculateInterval_MediumUsage() {
        // Given usage 50-75%
        let interval = sut.calculateInterval(for: 60)

        // Then interval should be default
        XCTAssertEqual(interval, 60)
    }

    func testCalculateInterval_HighUsage() {
        // Given usage 75-90%
        let interval = sut.calculateInterval(for: 80)

        // Then interval should be less than default
        XCTAssertLessThan(interval, 60)
    }

    func testCalculateInterval_CriticalUsage() {
        // Given usage >= 90%
        let interval = sut.calculateInterval(for: 95)

        // Then interval should be minimum
        XCTAssertEqual(interval, 30)
    }

    func testStart_SetsStateToRunning() {
        // When
        sut.start { }

        // Then
        XCTAssertTrue(sut.isRunning)
    }

    func testStop_SetsStateToIdle() {
        // Given
        sut.start { }

        // When
        sut.stop()

        // Then
        XCTAssertFalse(sut.isRunning)
    }

    func testPause_SetsStateToPaused() {
        // Given
        sut.start { }

        // When
        sut.pause()

        // Then
        XCTAssertTrue(sut.isPaused)
    }
}

// MARK: - RetryConfiguration Tests

final class RetryConfigurationTests: XCTestCase {

    func testDelay_ExponentialBackoff() {
        let config = RetryConfiguration()

        XCTAssertEqual(config.delay(for: 0), 2.0)   // 2 * 2^0 = 2
        XCTAssertEqual(config.delay(for: 1), 4.0)   // 2 * 2^1 = 4
        XCTAssertEqual(config.delay(for: 2), 8.0)   // 2 * 2^2 = 8
        XCTAssertEqual(config.delay(for: 3), 16.0)  // 2 * 2^3 = 16
    }

    func testDelay_CappedAtMaxDelay() {
        let config = RetryConfiguration(maxDelay: 10.0)

        XCTAssertEqual(config.delay(for: 5), 10.0)  // Would be 64, capped at 10
    }
}

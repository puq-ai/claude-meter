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
            "seven_day_sonnet": null
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

    func testUsageData_DecodingDesignWindowPresent() throws {
        // Given
        let json = """
        {
            "seven_day_omelette": {
                "utilization": 61.0,
                "resets_at": "2025-01-07T00:00:00Z"
            }
        }
        """.data(using: .utf8)!

        // When
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let usageData = try decoder.decode(UsageData.self, from: json)

        // Then
        XCTAssertEqual(usageData.sevenDayDesign?.utilization, 61.0)
        XCTAssertNotNil(usageData.sevenDayDesign?.resetsAt)
    }

    func testUsageData_DecodingDesignWindowMissingDefaultsToNil() throws {
        // Given
        let json = """
        {
            "five_hour": {
                "utilization": 45.0,
                "resets_at": "2025-01-01T12:00:00Z"
            }
        }
        """.data(using: .utf8)!

        // When
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let usageData = try decoder.decode(UsageData.self, from: json)

        // Then
        XCTAssertNil(usageData.sevenDayDesign)
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
        XCTAssertEqual(settings.refreshInterval, 30)
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

    func testSettings_DecodingLegacyToggleKeys_IgnoresThemAndUsesDefaults() throws {
        // Given - payload saved before the `limits` migration: it still carries the old
        // per-model toggles, which no longer exist on AppSettings.
        let json = """
        {
            "displayMode": "Detailed",
            "colorScheme": "Dark",
            "showInDock": true,
            "showSonnetLimit": true,
            "showDesignLimit": false,
            "showExtraUsage": true,
            "refreshInterval": 45,
            "launchAtLogin": true,
            "notifyAt": [80, 90],
            "notificationsEnabled": false,
            "webSessionKey": "session",
            "webOrganizationId": "org"
        }
        """.data(using: .utf8)!

        // When
        let decoded = try JSONDecoder().decode(AppSettings.self, from: json)

        // Then
        XCTAssertEqual(decoded.displayMode, .detailed)
        XCTAssertEqual(decoded.colorScheme, .dark)
        XCTAssertTrue(decoded.showInDock)
        XCTAssertTrue(decoded.showExtraUsage)
        XCTAssertEqual(decoded.refreshInterval, 45)
        XCTAssertTrue(decoded.launchAtLogin)
        XCTAssertEqual(decoded.notifyAt, [80, 90])
        XCTAssertFalse(decoded.notificationsEnabled)
        XCTAssertEqual(decoded.webOrganizationId, "org")
        // The session key is a secret and no longer lives in UserDefaults. A legacy value is
        // still decoded so it can be migrated into the Keychain, then dropped on the next save.
        XCTAssertEqual(decoded.legacyWebSessionKey, "session")
        // Unknown legacy keys are ignored and the replacements take their defaults,
        // so upgrading never throws and never silently hides the new limits.
        XCTAssertTrue(decoded.showScopedLimits)
        XCTAssertTrue(decoded.showBreakdown)
    }

    func testEncoding_NeverWritesTheSessionKeyBack() throws {
        // Given a settings value carrying a legacy plaintext key
        var settings = AppSettings()
        settings.legacyWebSessionKey = "super-secret-cookie"
        settings.webOrganizationId = "org-123"

        // When it is persisted
        let encoded = try JSONEncoder().encode(settings)
        let raw = String(data: encoded, encoding: .utf8) ?? ""

        // Then the secret is gone and the non-secret id remains
        XCTAssertFalse(raw.contains("super-secret-cookie"),
                       "the session key belongs in the Keychain, never in UserDefaults")
        XCTAssertFalse(raw.contains("webSessionKey"))
        XCTAssertTrue(raw.contains("org-123"))
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
        XCTAssertGreaterThan(interval, Constants.Polling.defaultInterval)
    }

    func testCalculateInterval_MediumUsage() {
        // Given usage 50-75%
        let interval = sut.calculateInterval(for: 60)

        // Then interval should be default
        XCTAssertEqual(interval, Constants.Polling.defaultInterval)
    }

    func testCalculateInterval_HighUsage() {
        // Given usage 75-90%
        let interval = sut.calculateInterval(for: 80)

        // Then interval should be <= default (high usage polls at or below default)
        XCTAssertLessThanOrEqual(interval, Constants.Polling.defaultInterval)
    }

    func testCalculateInterval_CriticalUsage() {
        // Given usage >= 90%
        let interval = sut.calculateInterval(for: 95)

        // Then interval should be minimum
        XCTAssertEqual(interval, Constants.Polling.minInterval)
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

// MARK: - Limits Schema Tests

/// Covers the API's `limits` array, which replaced the fixed `seven_day_<model>` keys.
final class LimitsSchemaTests: XCTestCase {

    private func decode(_ json: Data) throws -> UsageData {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(UsageData.self, from: json)
    }

    private func decode(_ json: String) throws -> UsageData {
        try decode(json.data(using: .utf8)!)
    }

    // MARK: Core behaviour

    func testLimits_ScopedModelLimitIsNamedByServer() throws {
        let usageData = try decode(TestData.makeLimitsUsageDataJSON())

        let windows = usageData.displayWindows
        XCTAssertEqual(windows.count, 3)

        let fable = try XCTUnwrap(windows.first { $0.title == "Fable Weekly" })
        XCTAssertEqual(fable.usage, 19)
        XCTAssertTrue(fable.isScoped)
        XCTAssertNotNil(fable.resetsAt)
        XCTAssertEqual(fable.severity, .normal)
    }

    func testLimits_OverallWindowsKeepLegacyIdentifiers() throws {
        // The notification state persisted in UserDefaults is keyed by these ids.
        // Changing them would re-fire every previously notified threshold on upgrade.
        let windows = try decode(TestData.makeLimitsUsageDataJSON()).displayWindows

        let session = try XCTUnwrap(windows.first { $0.title == "5-Hour Limit" })
        XCTAssertEqual(session.id, "5h")
        XCTAssertFalse(session.isScoped)

        let weekly = try XCTUnwrap(windows.first { $0.title == "7-Day Limit" })
        XCTAssertEqual(weekly.id, "7d")
        XCTAssertFalse(weekly.isScoped)
        XCTAssertTrue(weekly.isActive)
    }

    func testLimits_PercentIsNotFractionNormalized() throws {
        // UsageWindow rescales values in (0, 1) as fractions. `limits[].percent` is already
        // a percentage, so 0.5 must stay 0.5% and not become 50%.
        let usageData = try decode("""
        {
            "limits": [
                { "group": "weekly", "kind": "weekly_scoped", "percent": 0.5,
                  "scope": { "model": { "display_name": "Fable", "id": null } } }
            ]
        }
        """)

        XCTAssertEqual(usageData.displayWindows.first?.usage, 0.5)
    }

    // MARK: Tolerance to server changes

    func testLimits_UnknownKindAndSeverityStillRender() throws {
        let usageData = try decode("""
        {
            "limits": [
                { "group": "weekly", "kind": "weekly_experimental", "percent": 12,
                  "severity": "apocalyptic", "scope": null }
            ]
        }
        """)

        let window = try XCTUnwrap(usageData.displayWindows.first)
        XCTAssertEqual(window.usage, 12)
        XCTAssertEqual(window.title, "Weekly Experimental")
        XCTAssertEqual(window.severity, .unknown)
        // No scope means it is not hideable — an unrecognised limit is never hidden.
        XCTAssertFalse(window.isScoped)
    }

    func testLimits_UnexpectedSurfaceShapeDoesNotDropTheModelLimit() throws {
        // `scope.surface` has only ever been observed as null, so its shape is a guess.
        // A wrong guess must cost the surface label, never the model limit itself.
        let usageData = try decode("""
        {
            "five_hour": { "utilization": 4.0, "resets_at": "2026-09-11T10:00:00Z" },
            "limits": [
                { "group": "weekly", "kind": "weekly_scoped", "percent": 19,
                  "scope": { "model": { "display_name": "Fable", "id": null },
                             "surface": "cowork" } }
            ]
        }
        """)

        let fable = try XCTUnwrap(usageData.displayWindows.first { $0.isScoped })
        XCTAssertEqual(fable.title, "Fable Weekly")
        XCTAssertEqual(fable.usage, 19)
    }

    func testLimits_MalformedLimitsDoesNotBlankTheResponse() throws {
        let usageData = try decode("""
        {
            "five_hour": { "utilization": 4.0, "resets_at": "2026-09-11T10:00:00Z" },
            "seven_day": { "utilization": 24.0, "resets_at": "2026-09-16T11:00:00Z" },
            "limits": "not-an-array"
        }
        """)

        XCTAssertNil(usageData.limits)
        XCTAssertEqual(usageData.fiveHour?.utilization, 4.0)
        // Falls back to the legacy windows rather than showing nothing.
        XCTAssertEqual(usageData.displayWindows.map(\.id), ["5h", "7d"])
    }

    func testLimits_UnnamedScopedEntriesGetDistinctIdentifiers() throws {
        let usageData = try decode("""
        {
            "limits": [
                { "group": "weekly", "kind": "weekly_scoped", "percent": 10, "scope": null },
                { "group": "weekly", "kind": "weekly_scoped", "percent": 20, "scope": null }
            ]
        }
        """)

        let ids = usageData.displayWindows.map(\.id)
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(Set(ids).count, 2, "Colliding ids would break ForEach and notification state")
    }

    func testLimits_EntryWithoutPercentIsSkipped() throws {
        let usageData = try decode("""
        {
            "limits": [
                { "group": "weekly", "kind": "weekly_all", "percent": 24 },
                { "group": "weekly", "kind": "weekly_scoped", "scope": { "model": { "display_name": "Fable" } } }
            ]
        }
        """)

        XCTAssertEqual(usageData.displayWindows.map(\.id), ["7d"])
    }

    // MARK: Legacy fallback

    func testLegacyResponseStillProducesWindows() throws {
        // The claude.ai web fallback may still return the pre-`limits` shape.
        let usageData = try decode("""
        {
            "five_hour": { "utilization": 45.0, "resets_at": "2026-09-11T10:00:00Z" },
            "seven_day": { "utilization": 30.0, "resets_at": "2026-09-16T11:00:00Z" },
            "seven_day_sonnet": { "utilization": 12.0, "resets_at": "2026-09-16T11:00:00Z" }
        }
        """)

        let windows = usageData.displayWindows
        XCTAssertEqual(windows.map(\.id), ["5h", "7d", "sonnet"])
        XCTAssertEqual(windows.last?.usage, 12.0)
        XCTAssertTrue(try XCTUnwrap(windows.last).isScoped)
    }

    // MARK: Breakdown, spend, extra usage

    func testBreakdown_DecodesAndFiltersEmptyRows() throws {
        let breakdown = try XCTUnwrap(try decode(TestData.makeLimitsUsageDataJSON()).sevenDayBreakdown)

        XCTAssertEqual(breakdown.rows?.count, 2)
        // "Chats" is at 0% and is not worth a row.
        XCTAssertEqual(breakdown.significantRows.map(\.displayName), ["Claude Code"])
        XCTAssertNotNil(breakdown.windowStartedAt)
    }

    func testMoneyAmount_HonoursExponent() throws {
        let spend = try XCTUnwrap(try decode(TestData.makeLimitsUsageDataJSON()).spend)

        XCTAssertEqual(spend.used?.amount, 12.34)
        XCTAssertEqual(spend.used?.currency, "USD")
        XCTAssertEqual(spend.enabled, false)
        XCTAssertEqual(spend.severity, .normal)
    }

    func testMoneyAmount_NonCentExponent() throws {
        let json = """
        { "spend": { "used": { "amount_minor": 1234, "currency": "JPY", "exponent": 0 } } }
        """
        let spend = try XCTUnwrap(try decode(json).spend)

        XCTAssertEqual(spend.used?.amount, 1234)
    }

    func testExtraUsage_DecodesNewFieldsAndNullCredits() throws {
        let extra = try XCTUnwrap(try decode(TestData.makeLimitsUsageDataJSON()).extraUsage)

        XCTAssertFalse(extra.isEnabled)
        XCTAssertEqual(extra.creditsEverEnabled, true)
        XCTAssertEqual(extra.userDisabled, true)
        XCTAssertEqual(extra.spendLimitReached, false)
        XCTAssertNil(extra.usedCredits)
    }

    // MARK: Cache round-trip

    func testLimits_SurviveEncodeDecodeRoundTrip() throws {
        // The offline cache re-encodes UsageData; the Fable card must come back.
        let original = try decode(TestData.makeLimitsUsageDataJSON())

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(UsageData.self, from: encoded)

        XCTAssertEqual(restored.displayWindows.map(\.title), original.displayWindows.map(\.title))
        XCTAssertEqual(restored.displayWindows.first { $0.isScoped }?.title, "Fable Weekly")
    }

    // MARK: Identifier stability

    func testLimits_ScopeIdSurvivesADisplayNameChange() throws {
        // Notification state is persisted against the id. If a rename changed it, every
        // threshold the user already saw would fire again on the next poll.
        func scopedId(displayName: String) throws -> String {
            let usageData = try decode("""
            {
                "limits": [
                    { "group": "weekly", "kind": "weekly_scoped", "percent": 80,
                      "scope": { "model": { "display_name": "\(displayName)", "id": "model_fable" } } }
                ]
            }
            """)
            return try XCTUnwrap(usageData.displayWindows.first).id
        }

        XCTAssertEqual(try scopedId(displayName: "Fable"), try scopedId(displayName: "Fable 5.1"))
    }

    func testLimits_ScopeIdIsPreferredOverThePositionalFallback() throws {
        let usageData = try decode("""
        {
            "limits": [
                { "group": "weekly", "kind": "weekly_scoped", "percent": 10,
                  "scope": { "model": { "display_name": null, "id": "model_a" } } },
                { "group": "weekly", "kind": "weekly_scoped", "percent": 20,
                  "scope": { "model": { "display_name": null, "id": "model_b" } } }
            ]
        }
        """)

        // Ids come from the server, so a reorder can no longer swap two limits' state.
        XCTAssertEqual(usageData.displayWindows.map(\.id),
                       ["weekly_scoped:model_a", "weekly_scoped:model_b"])
    }

    // MARK: Notification naming

    func testNotificationName_DropsTheLimitSuffix() throws {
        // Bodies read "Your <name> usage has been reset", so the card's "5-Hour Limit"
        // would produce "Your 5-Hour Limit usage...". Keep the pre-`limits` wording.
        let windows = try decode(TestData.makeLimitsUsageDataJSON()).displayWindows

        XCTAssertEqual(windows.first { $0.id == "5h" }?.notificationName, "5-Hour")
        XCTAssertEqual(windows.first { $0.id == "7d" }?.notificationName, "7-Day")
        // Titles that do not end in "Limit" are already correct and stay untouched.
        XCTAssertEqual(windows.first { $0.isScoped }?.notificationName, "Fable Weekly")
    }

    // MARK: Single-window lookup (menu bar)

    func testUsageForLimitId_ReadsThroughTheLimitsArray() throws {
        let usageData = try decode(TestData.makeLimitsUsageDataJSON())

        XCTAssertEqual(usageData.usage(forLimitId: "5h"), 4)
        XCTAssertEqual(usageData.usage(forLimitId: "7d"), 24)
        XCTAssertNil(usageData.usage(forLimitId: "opus"))
    }

    func testUsageForLimitId_SurvivesTheTopLevelWindowsGoingAway() throws {
        // The server already dropped the per-model keys this way; the menu bar must keep
        // reading 5h/7d off `limits` if `five_hour` / `seven_day` follow.
        let usageData = try decode("""
        {
            "five_hour": null,
            "seven_day": null,
            "limits": [
                { "group": "session", "kind": "session", "percent": 4 },
                { "group": "weekly", "kind": "weekly_all", "percent": 24 }
            ]
        }
        """)

        XCTAssertNil(usageData.fiveHour)
        XCTAssertEqual(usageData.usage(forLimitId: "5h"), 4)
        XCTAssertEqual(usageData.usage(forLimitId: "7d"), 24)
    }

    func testUsageForLimitId_FallsBackToLegacyWindows() throws {
        let usageData = try decode("""
        {
            "five_hour": { "utilization": 45.0, "resets_at": "2026-09-11T10:00:00Z" },
            "seven_day": { "utilization": 30.0, "resets_at": "2026-09-16T11:00:00Z" }
        }
        """)

        XCTAssertEqual(usageData.usage(forLimitId: "5h"), 45.0)
        XCTAssertEqual(usageData.usage(forLimitId: "7d"), 30.0)
    }
}

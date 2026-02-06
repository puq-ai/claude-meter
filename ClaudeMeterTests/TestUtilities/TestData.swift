//
//  TestData.swift
//  ClaudeMeterTests
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation
@testable import ClaudeMeter

/// Factory methods for creating test data
enum TestData {

    // MARK: - Usage Data

    static func makeUsageData(
        fiveHourUsage: Double = 50.0,
        sevenDayUsage: Double = 30.0,
        opusUsage: Double? = 25.0
    ) -> UsageData {
        return UsageData(
            fiveHour: makeUsageWindow(utilization: fiveHourUsage),
            sevenDay: makeUsageWindow(utilization: sevenDayUsage),
            sevenDayOpus: opusUsage.map { makeUsageWindow(utilization: $0) }
        )
    }

    static func makeUsageWindow(
        utilization: Double = 50.0,
        resetsAt: Date? = Date().addingTimeInterval(3600)
    ) -> UsageWindow {
        return UsageWindow(
            utilization: utilization,
            resetsAt: resetsAt
        )
    }

    static func makeHighUsageData() -> UsageData {
        return makeUsageData(
            fiveHourUsage: 85.0,
            sevenDayUsage: 75.0,
            opusUsage: 90.0
        )
    }

    static func makeCriticalUsageData() -> UsageData {
        return makeUsageData(
            fiveHourUsage: 95.0,
            sevenDayUsage: 92.0,
            opusUsage: 98.0
        )
    }

    static func makeLowUsageData() -> UsageData {
        return makeUsageData(
            fiveHourUsage: 10.0,
            sevenDayUsage: 5.0,
            opusUsage: 2.0
        )
    }

    // MARK: - Credentials

    static func makeCredentials(
        accessToken: String = "test_access_token_12345",
        refreshToken: String = "test_refresh_token_67890",
        expiresAt: Date = Date().addingTimeInterval(3600),
        subscriptionType: String = "pro"
    ) -> ClaudeCredentials {
        return ClaudeCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            subscriptionType: subscriptionType
        )
    }

    static func makeExpiredCredentials() -> ClaudeCredentials {
        return makeCredentials(
            expiresAt: Date().addingTimeInterval(-3600)
        )
    }

    static func makeExpiringSoonCredentials() -> ClaudeCredentials {
        return makeCredentials(
            expiresAt: Date().addingTimeInterval(120) // 2 minutes
        )
    }

    // MARK: - App Settings

    static func makeAppSettings(
        displayMode: DisplayMode = .compact,
        colorScheme: AppColorScheme = .auto,
        refreshInterval: Int = 60,
        notificationsEnabled: Bool = true,
        notifyAt: [Int] = [75, 90, 95]
    ) -> AppSettings {
        var settings = AppSettings()
        settings.displayMode = displayMode
        settings.colorScheme = colorScheme
        settings.refreshInterval = refreshInterval
        settings.notificationsEnabled = notificationsEnabled
        settings.notifyAt = notifyAt
        return settings
    }

    // MARK: - JSON Data

    static func makeUsageDataJSON() -> Data {
        let resetDate = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600))
        let json = """
        {
            "five_hour": {
                "utilization": 50.0,
                "resets_at": "\(resetDate)"
            },
            "seven_day": {
                "utilization": 30.0,
                "resets_at": "\(resetDate)"
            },
            "seven_day_opus": {
                "utilization": 25.0,
                "resets_at": "\(resetDate)"
            }
        }
        """
        return json.data(using: .utf8)!
    }

    static func makeErrorJSON(message: String = "Test error") -> Data {
        let json = """
        {
            "error": {
                "message": "\(message)"
            }
        }
        """
        return json.data(using: .utf8)!
    }
}

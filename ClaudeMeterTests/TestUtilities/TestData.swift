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

    /// JSON with 0-1 scale utilization values (API format change)
    static func makeUsageDataJSON_FractionalScale() -> Data {
        let resetDate = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600))
        let json = """
        {
            "five_hour": {
                "utilization": 0.50,
                "resets_at": "\(resetDate)"
            },
            "seven_day": {
                "utilization": 0.30,
                "resets_at": "\(resetDate)"
            },
            "seven_day_opus": {
                "utilization": 0.25,
                "resets_at": "\(resetDate)"
            }
        }
        """
        return json.data(using: .utf8)!
    }

    /// Trimmed copy of a real `/api/oauth/usage` response captured 2026-09-11, after the
    /// API moved every limit into the `limits` array. Note that all legacy per-model keys
    /// come back null and the scoped limit is named by the server, not by a fixed key.
    static func makeLimitsUsageDataJSON() -> Data {
        let json = """
        {
            "five_hour": { "utilization": 4.0, "resets_at": "2026-09-11T10:00:00Z" },
            "seven_day": { "utilization": 24.0, "resets_at": "2026-09-16T11:00:00Z" },
            "seven_day_opus": null,
            "seven_day_sonnet": null,
            "seven_day_omelette": null,
            "limits": [
                {
                    "group": "session",
                    "kind": "session",
                    "percent": 4,
                    "resets_at": "2026-09-11T10:00:00Z",
                    "is_active": false,
                    "scope": null,
                    "severity": "normal"
                },
                {
                    "group": "weekly",
                    "kind": "weekly_all",
                    "percent": 24,
                    "resets_at": "2026-09-16T11:00:00Z",
                    "is_active": true,
                    "scope": null,
                    "severity": "normal"
                },
                {
                    "group": "weekly",
                    "kind": "weekly_scoped",
                    "percent": 19,
                    "resets_at": "2026-09-16T10:59:59Z",
                    "is_active": false,
                    "scope": { "model": { "display_name": "Fable", "id": null }, "surface": null },
                    "severity": "normal"
                }
            ],
            "seven_day_breakdown": {
                "as_of": "2026-09-11T06:34:38Z",
                "window_started_at": "2026-09-09T11:00:00Z",
                "rows": [
                    { "display_name": "Claude Code", "key": "claude_code", "percent": 100 },
                    { "display_name": "Chats", "key": "chat", "percent": 0 }
                ]
            },
            "spend": {
                "enabled": false,
                "percent": 0,
                "severity": "normal",
                "can_purchase_credits": false,
                "can_toggle": false,
                "used": { "amount_minor": 1234, "currency": "USD", "exponent": 2 }
            },
            "extra_usage": {
                "is_enabled": false,
                "credits_ever_enabled": true,
                "user_disabled": true,
                "spend_limit_reached": false,
                "monthly_limit": null,
                "used_credits": null,
                "utilization": null
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

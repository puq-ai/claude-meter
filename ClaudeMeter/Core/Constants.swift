//
//  Constants.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation

/// Centralized constants for the ClaudeMeter application
enum Constants {

    // MARK: - API Configuration
    enum API {
        static let baseURL = "https://api.anthropic.com"
        static let usageEndpoint = "/api/oauth/usage"

        // Timeouts
        static let requestTimeout: TimeInterval = 30
        static let resourceTimeout: TimeInterval = 60

        // Headers
        static let userAgent = "ClaudeMeter/1.0"
        static let anthropicBeta = "oauth-2025-04-20"
        static let contentType = "application/json"
        static let acceptType = "application/json"
    }

    // MARK: - Retry Configuration
    enum Retry {
        static let maxRetries = 3
        static let initialDelay: TimeInterval = 2.0
        static let maxDelay: TimeInterval = 30.0
        static let multiplier: Double = 2.0
        static let serverErrorMinDelay: TimeInterval = 30.0
    }

    // MARK: - Polling Configuration
    enum Polling {
        static let defaultInterval: TimeInterval = 60
        static let minInterval: TimeInterval = 30
        static let maxInterval: TimeInterval = 300
        static let backgroundInterval: TimeInterval = 900  // 15 minutes

        // Adaptive polling thresholds
        static let highUsageThreshold: Double = 75
        static let criticalUsageThreshold: Double = 90

        // Circuit breaker
        static let maxConsecutiveFailures = 5
        static let failureBackoffInterval: TimeInterval = 600  // 10 minutes

        // Hysteresis for interval changes
        static let intervalChangeThreshold: TimeInterval = 10
    }

    // MARK: - Cache Configuration
    enum Cache {
        static let directoryName = "ClaudeMeter"
        static let usageDataFilename = "usage_data.json"
        static let maxAge: TimeInterval = 3600 * 24  // 24 hours
        static let version = 1
    }

    // MARK: - Notification Configuration
    enum Notification {
        static let throttleInterval: TimeInterval = 3600  // 1 hour
        static let hysteresisBuffer: Double = 5.0

        // Default thresholds
        static let defaultThresholds: [Int] = [75, 90, 95]

        // UserDefaults keys
        static let throttleTimesKey = "com.claudemeter.throttleTimes"
        static let notificationStateKey = "com.claudemeter.notificationState"

        // Reset detection
        static let resetDropThreshold: Double = 40.0
        static let resetLowThreshold: Double = 20.0
    }

    // MARK: - Keychain Configuration
    enum Keychain {
        static let serviceName = "Claude Code-credentials"
    }

    // MARK: - FileWatcher Configuration
    enum FileWatcher {
        static let debounceInterval: TimeInterval = 1.0
        static let fsEventsLatency: CFTimeInterval = 0.5

        static let configPaths: [String] = [
            "~/.config/claude/",
            "~/.claude/"
        ]

        static let relevantExtensions = ["json", ""]
        static let relevantFiles = ["credentials", "settings", "config"]
    }

    // MARK: - App Settings
    enum Settings {
        static let userDefaultsKey = "com.claudemeter.settings"

        // Validation bounds
        static let minRefreshInterval = 30
        static let maxRefreshInterval = 600

        // Defaults
        static let defaultRefreshInterval = 60
        static let defaultNotifyThresholds: [Int] = [75, 90, 95]
    }

    // MARK: - Credentials
    enum Credentials {
        static let expirationWarningThreshold: TimeInterval = 5 * 60  // 5 minutes
        static let defaultSubscriptionType = "pro"
    }

    // MARK: - UI Dimensions
    enum UI {
        static let menuBarIconSize: CGFloat = 18
        static let menuBarIconLineWidth: CGFloat = 2.5
        static let settingsMaxWidth: CGFloat = 400
        static let aboutLogoSize: CGFloat = 64
    }

    // MARK: - Wake Recovery Configuration
    enum WakeRecovery {
        static let initialDelay: TimeInterval = 2.0
        static let retryDelays: [TimeInterval] = [2, 4, 8]
        static let significantSleepDuration: TimeInterval = 300  // 5 minutes
        static let maxRetries = 3
    }

    // MARK: - Statistics Configuration
    enum Statistics {
        static let storageFileName = "usage_statistics.json"
        static let maxHistoryDays = 365
        static let refreshInterval: TimeInterval = 300  // 5 minutes
        static let claudeProjectsPath = "~/.claude/projects"
    }
}

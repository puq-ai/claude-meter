//
//  AppSettings.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation
import SwiftUI

// MARK: - Display Mode
enum DisplayMode: String, Codable, CaseIterable {
    case iconOnly = "Icon Only"
    case compact = "Compact"
    case detailed = "Detailed"
}

// MARK: - Color Scheme
enum AppColorScheme: String, Codable, CaseIterable {
    case auto = "Auto"
    case light = "Light"
    case dark = "Dark"

    var colorScheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - App Settings
struct AppSettings: Codable, Equatable {
    // Display
    var displayMode: DisplayMode = .compact
    var colorScheme: AppColorScheme = .auto
    var showInDock: Bool = false
    /// Show per-model / per-surface weekly limits reported in the API's `limits` array.
    /// Replaces the old showSonnetLimit + showDesignLimit pair: the server no longer sends
    /// those windows, and it now names each scoped limit itself, so one switch covers all.
    var showScopedLimits: Bool = true
    var showBreakdown: Bool = true
    var showExtraUsage: Bool = false

    // Polling
    var refreshInterval: Int = Constants.Settings.defaultRefreshInterval

    // Startup
    var launchAtLogin: Bool = false

    // Notifications
    var notifyAt: [Int] = Constants.Settings.defaultNotifyThresholds
    var notificationsEnabled: Bool = true

    // Web API Fallback (claude.ai). The session key is a secret and lives in the Keychain,
    // not here - only the non-secret organization id is persisted in UserDefaults.
    var webOrganizationId: String = ""
    /// Display name for the connected organization. Non-secret, purely for the settings UI.
    var webOrganizationName: String = ""

    /// Session key left behind by versions that stored it in UserDefaults as plaintext.
    /// Decoded so it can be migrated into the Keychain, and deliberately never re-encoded:
    /// saving these settings drops it.
    var legacyWebSessionKey: String?

    private enum CodingKeys: String, CodingKey {
        case displayMode
        case colorScheme
        case showInDock
        case showScopedLimits
        case showBreakdown
        case showExtraUsage
        case refreshInterval
        case launchAtLogin
        case notifyAt
        case notificationsEnabled
        case webSessionKey
        case webOrganizationId
        case webOrganizationName
    }

    /// Everything that is actually persisted. `webSessionKey` is intentionally absent.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(displayMode, forKey: .displayMode)
        try container.encode(colorScheme, forKey: .colorScheme)
        try container.encode(showInDock, forKey: .showInDock)
        try container.encode(showScopedLimits, forKey: .showScopedLimits)
        try container.encode(showBreakdown, forKey: .showBreakdown)
        try container.encode(showExtraUsage, forKey: .showExtraUsage)
        try container.encode(refreshInterval, forKey: .refreshInterval)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(notifyAt, forKey: .notifyAt)
        try container.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try container.encode(webOrganizationId, forKey: .webOrganizationId)
        try container.encode(webOrganizationName, forKey: .webOrganizationName)
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()

        displayMode = try container.decodeIfPresent(DisplayMode.self, forKey: .displayMode) ?? defaults.displayMode
        colorScheme = try container.decodeIfPresent(AppColorScheme.self, forKey: .colorScheme) ?? defaults.colorScheme
        showInDock = try container.decodeIfPresent(Bool.self, forKey: .showInDock) ?? defaults.showInDock
        // Settings saved before the `limits` migration carry showSonnetLimit / showDesignLimit.
        // Codable ignores unknown keys, so those simply fall through to the defaults here.
        showScopedLimits = try container.decodeIfPresent(Bool.self, forKey: .showScopedLimits) ?? defaults.showScopedLimits
        showBreakdown = try container.decodeIfPresent(Bool.self, forKey: .showBreakdown) ?? defaults.showBreakdown
        showExtraUsage = try container.decodeIfPresent(Bool.self, forKey: .showExtraUsage) ?? defaults.showExtraUsage
        refreshInterval = try container.decodeIfPresent(Int.self, forKey: .refreshInterval) ?? defaults.refreshInterval
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        notifyAt = try container.decodeIfPresent([Int].self, forKey: .notifyAt) ?? defaults.notifyAt
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? defaults.notificationsEnabled
        webOrganizationId = try container.decodeIfPresent(String.self, forKey: .webOrganizationId) ?? defaults.webOrganizationId
        webOrganizationName = try container.decodeIfPresent(String.self, forKey: .webOrganizationName) ?? defaults.webOrganizationName
        legacyWebSessionKey = try container.decodeIfPresent(String.self, forKey: .webSessionKey)
    }

    // Computed property for backward compatibility
    var notifyAt90: Bool {
        get { notifyAt.contains(90) }
        set {
            if newValue && !notifyAt.contains(90) {
                notifyAt.append(90)
                notifyAt.sort()
            } else if !newValue {
                notifyAt.removeAll { $0 == 90 }
            }
        }
    }

    // Check if notification should be sent for a threshold
    func shouldNotify(at threshold: Int) -> Bool {
        return notificationsEnabled && notifyAt.contains(threshold)
    }

    // Get all enabled thresholds sorted
    var sortedThresholds: [Int] {
        return notifyAt.sorted()
    }
}

// MARK: - Settings Keys
extension AppSettings {
    static let userDefaultsKey = Constants.Settings.userDefaultsKey

    // Validation bounds
    private static let minRefreshInterval = Constants.Settings.minRefreshInterval
    private static let maxRefreshInterval = Constants.Settings.maxRefreshInterval

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              var settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        // Validate loaded settings
        settings.validate()
        return settings
    }

    func save() {
        var validatedSettings = self
        validatedSettings.validate()
        if let data = try? JSONEncoder().encode(validatedSettings) {
            UserDefaults.standard.set(data, forKey: AppSettings.userDefaultsKey)
        }
    }

    /// Validate and fix any out-of-bounds values
    mutating func validate() {
        // Validate refresh interval bounds
        refreshInterval = max(Self.minRefreshInterval, min(refreshInterval, Self.maxRefreshInterval))

        // Validate notification thresholds (must be between 0 and 100)
        notifyAt = notifyAt.filter { $0 > 0 && $0 <= 100 }.sorted()

        // Ensure at least default thresholds if empty
        if notifyAt.isEmpty {
            notifyAt = Constants.Settings.defaultNotifyThresholds
        }
    }
}

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
    var showSonnetLimit: Bool = false
    var showDesignLimit: Bool = true
    var showExtraUsage: Bool = false

    // Polling
    var refreshInterval: Int = Constants.Settings.defaultRefreshInterval

    // Startup
    var launchAtLogin: Bool = false

    // Notifications
    var notifyAt: [Int] = Constants.Settings.defaultNotifyThresholds
    var notificationsEnabled: Bool = true

    // Web API Fallback (claude.ai session credentials)
    var webSessionKey: String = ""
    var webOrganizationId: String = ""

    private enum CodingKeys: String, CodingKey {
        case displayMode
        case colorScheme
        case showInDock
        case showSonnetLimit
        case showDesignLimit
        case showExtraUsage
        case refreshInterval
        case launchAtLogin
        case notifyAt
        case notificationsEnabled
        case webSessionKey
        case webOrganizationId
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()

        displayMode = try container.decodeIfPresent(DisplayMode.self, forKey: .displayMode) ?? defaults.displayMode
        colorScheme = try container.decodeIfPresent(AppColorScheme.self, forKey: .colorScheme) ?? defaults.colorScheme
        showInDock = try container.decodeIfPresent(Bool.self, forKey: .showInDock) ?? defaults.showInDock
        showSonnetLimit = try container.decodeIfPresent(Bool.self, forKey: .showSonnetLimit) ?? defaults.showSonnetLimit
        showDesignLimit = try container.decodeIfPresent(Bool.self, forKey: .showDesignLimit) ?? defaults.showDesignLimit
        showExtraUsage = try container.decodeIfPresent(Bool.self, forKey: .showExtraUsage) ?? defaults.showExtraUsage
        refreshInterval = try container.decodeIfPresent(Int.self, forKey: .refreshInterval) ?? defaults.refreshInterval
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        notifyAt = try container.decodeIfPresent([Int].self, forKey: .notifyAt) ?? defaults.notifyAt
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? defaults.notificationsEnabled
        webSessionKey = try container.decodeIfPresent(String.self, forKey: .webSessionKey) ?? defaults.webSessionKey
        webOrganizationId = try container.decodeIfPresent(String.self, forKey: .webOrganizationId) ?? defaults.webOrganizationId
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

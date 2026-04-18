//
//  UsageData.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation

struct UsageData: Codable, Equatable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let sevenDayOpus: UsageWindow?
    let sevenDaySonnet: UsageWindow?
    let sevenDayOauthApps: UsageWindow?
    let sevenDayCowork: UsageWindow?
    let sevenDayDesign: UsageWindow?
    let extraUsage: ExtraUsage?
    let fetchedAt: Date

    // CodingKeys for snake_case API response mapping
    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOauthApps = "seven_day_oauth_apps"
        case sevenDayCowork = "seven_day_cowork"
        // Claude Design — server returns the internal codename for now
        case sevenDayDesign = "seven_day_omelette"
        case extraUsage = "extra_usage"
        case fetchedAt = "fetched_at"
    }

    // Custom initializer for creating instances programmatically
    init(fiveHour: UsageWindow?, sevenDay: UsageWindow?, sevenDayOpus: UsageWindow?, sevenDaySonnet: UsageWindow? = nil, sevenDayOauthApps: UsageWindow? = nil, sevenDayCowork: UsageWindow? = nil, sevenDayDesign: UsageWindow? = nil, extraUsage: ExtraUsage? = nil, fetchedAt: Date = Date()) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDayOpus = sevenDayOpus
        self.sevenDaySonnet = sevenDaySonnet
        self.sevenDayOauthApps = sevenDayOauthApps
        self.sevenDayCowork = sevenDayCowork
        self.sevenDayDesign = sevenDayDesign
        self.extraUsage = extraUsage
        self.fetchedAt = fetchedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fiveHour = try container.decodeIfPresent(UsageWindow.self, forKey: .fiveHour)
        sevenDay = try container.decodeIfPresent(UsageWindow.self, forKey: .sevenDay)
        sevenDayOpus = try container.decodeIfPresent(UsageWindow.self, forKey: .sevenDayOpus)
        sevenDaySonnet = try container.decodeIfPresent(UsageWindow.self, forKey: .sevenDaySonnet)
        sevenDayOauthApps = try container.decodeIfPresent(UsageWindow.self, forKey: .sevenDayOauthApps)
        sevenDayCowork = try container.decodeIfPresent(UsageWindow.self, forKey: .sevenDayCowork)
        sevenDayDesign = try container.decodeIfPresent(UsageWindow.self, forKey: .sevenDayDesign)
        extraUsage = try container.decodeIfPresent(ExtraUsage.self, forKey: .extraUsage)
        // fetchedAt may not come from API, default to now
        fetchedAt = try container.decodeIfPresent(Date.self, forKey: .fetchedAt) ?? Date()
    }
}

struct UsageWindow: Codable, Equatable {
    let utilization: Double      // Always 0-100 percentage
    let resetsAt: Date?          // ISO 8601

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    init(utilization: Double, resetsAt: Date? = nil) {
        // Normalize: if value is in 0-1 range (exclusive of 0), treat as fraction
        self.utilization = utilization > 0 && utilization < 1.0 ? utilization * 100.0 : utilization
        self.resetsAt = resetsAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawUtilization = try container.decode(Double.self, forKey: .utilization)
        resetsAt = try container.decodeIfPresent(Date.self, forKey: .resetsAt)
        // Normalize: if value is in 0-1 range (exclusive of 0), treat as fraction
        utilization = rawUtilization > 0 && rawUtilization < 1.0 ? rawUtilization * 100.0 : rawUtilization
    }
}

struct ExtraUsage: Codable, Equatable {
    let isEnabled: Bool
    let monthlyLimit: Double?
    let usedCredits: Double?
    let utilization: Double?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case utilization
    }
}

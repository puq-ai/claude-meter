//
//  SubscriptionType.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import SwiftUI

/// Claude subscription plan types
enum SubscriptionType: String, Codable, CaseIterable, Identifiable {
    case free = "free"
    case pro = "pro"
    case max = "max"
    case max5 = "max5"
    case team = "team"
    case enterprise = "enterprise"

    var id: String { rawValue }

    /// Human-readable display name
    var displayName: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro"
        case .max: return "Max"
        case .max5: return "Max (5x)"
        case .team: return "Team"
        case .enterprise: return "Enterprise"
        }
    }

    /// SF Symbol icon name
    var icon: String {
        switch self {
        case .free: return "person.fill"
        case .pro: return "star.fill"
        case .max: return "bolt.fill"
        case .max5: return "bolt.horizontal.fill"
        case .team: return "person.3.fill"
        case .enterprise: return "building.2.fill"
        }
    }

    /// Theme color for the subscription badge
    var color: Color {
        switch self {
        case .free: return .gray
        case .pro: return ColorTheme.accent
        case .max: return .orange
        case .max5: return Color(red: 1.0, green: 0.6, blue: 0.0) // Bright orange
        case .team: return .blue
        case .enterprise: return .indigo
        }
    }

    /// Secondary color for gradients
    var secondaryColor: Color {
        switch self {
        case .free: return .gray.opacity(0.7)
        case .pro: return ColorTheme.accent.opacity(0.7)
        case .max: return .yellow
        case .max5: return .orange
        case .team: return .cyan
        case .enterprise: return .purple
        }
    }

    /// Initialize from string with fallback
    init(from string: String) {
        switch string.lowercased() {
        case "free": self = .free
        case "pro": self = .pro
        case "max": self = .max
        case "max5", "max_5x": self = .max5
        case "team": self = .team
        case "enterprise": self = .enterprise
        default: self = .pro // Default to pro
        }
    }
}

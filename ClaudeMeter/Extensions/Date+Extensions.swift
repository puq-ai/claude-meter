//
//  Date+Extensions.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation

extension Date {
    /// Format time remaining until this date
    /// - Parameter style: Formatting style
    /// - Returns: Formatted string like "2h 30m" or "3d 5h"
    func timeRemainingFormatted(style: TimeRemainingStyle = .short) -> String {
        let diff = self.timeIntervalSinceNow

        guard diff > 0 else {
            return style == .short ? "Reset" : "Time's up"
        }

        let seconds = Int(diff)
        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24

        switch style {
        case .short:
            if days > 0 {
                let remainingHours = hours % 24
                return "\(days)d \(remainingHours)h"
            } else if hours > 0 {
                let remainingMinutes = minutes % 60
                return "\(hours)h \(remainingMinutes)m"
            } else {
                return "\(minutes)m"
            }

        case .medium:
            if days > 0 {
                let remainingHours = hours % 24
                return "\(days) days, \(remainingHours) hours"
            } else if hours > 0 {
                let remainingMinutes = minutes % 60
                return "\(hours) hours, \(remainingMinutes) minutes"
            } else {
                return "\(minutes) minutes"
            }

        case .long:
            if days > 0 {
                return "\(days) day\(days > 1 ? "s" : "") remaining"
            } else if hours > 0 {
                return "\(hours) hour\(hours > 1 ? "s" : "") remaining"
            } else {
                return "\(minutes) minute\(minutes > 1 ? "s" : "") remaining"
            }

        case .accessibilityFriendly:
            if days > 0 {
                let remainingHours = hours % 24
                return "\(days) days and \(remainingHours) hours until reset"
            } else if hours > 0 {
                let remainingMinutes = minutes % 60
                return "\(hours) hours and \(remainingMinutes) minutes until reset"
            } else {
                return "\(minutes) minutes until reset"
            }
        }
    }

    enum TimeRemainingStyle {
        case short               // "2h 30m"
        case medium              // "2 hours, 30 minutes"
        case long                // "2 hours remaining"
        case accessibilityFriendly  // "2 hours and 30 minutes until reset"
    }

    /// Check if date is within given time interval from now
    func isWithin(_ interval: TimeInterval) -> Bool {
        return abs(self.timeIntervalSinceNow) < interval
    }

    /// Relative time description (e.g., "2 minutes ago", "in 5 hours")
    var relativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    /// Start of the current day
    var startOfDay: Date {
        return Calendar.current.startOfDay(for: self)
    }

    /// End of the current day
    var endOfDay: Date {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        return Calendar.current.date(byAdding: components, to: startOfDay) ?? startOfDay
    }

    /// Check if date is today
    var isToday: Bool {
        return Calendar.current.isDateInToday(self)
    }

    /// Add time interval and return new date
    func adding(_ interval: TimeInterval) -> Date {
        return self.addingTimeInterval(interval)
    }
}

// MARK: - TimeInterval Extensions

extension TimeInterval {
    /// Format as duration string
    var formattedDuration: String {
        let hours = Int(self) / 3600
        let minutes = (Int(self) % 3600) / 60
        let seconds = Int(self) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    /// Time interval constants
    static let minute: TimeInterval = 60
    static let hour: TimeInterval = 3600
    static let day: TimeInterval = 86400
    static let week: TimeInterval = 604800
}

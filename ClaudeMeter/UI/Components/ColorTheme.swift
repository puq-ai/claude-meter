//
//  ColorTheme.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import SwiftUI

/// Color theme for ClaudeMeter
/// Based on Apple Human Interface Guidelines color palette
enum ColorTheme {
    // MARK: - Usage Colors

    /// Green - Low usage (0-50%)
    static let green = Color(red: 52/255, green: 199/255, blue: 89/255)  // #34C759

    /// Yellow - Medium usage (50-75%)
    static let yellow = Color(red: 255/255, green: 204/255, blue: 0/255)  // #FFCC00

    /// Orange - High usage (75-90%)
    static let orange = Color(red: 230/255, green: 126/255, blue: 0/255)  // #E67E00

    /// Red - Critical usage (90-100%)
    static let red = Color(red: 255/255, green: 59/255, blue: 48/255)  // #FF3B30

    // MARK: - UI Colors

    /// Primary accent color
    static let accent = Color(red: 175/255, green: 82/255, blue: 222/255)  // #AF52DE - Purple (Claude brand)

    /// Background color for cards (deprecated - use .regularMaterial instead)
    @available(*, deprecated, message: "Use .regularMaterial for glass effect")
    static let cardBackground = Color(nsColor: .controlBackgroundColor)

    /// Secondary text color
    static let secondaryText = Color(nsColor: .secondaryLabelColor)

    // MARK: - Glass Effect Colors

    /// Subtle overlay for glass effect
    static let glassOverlay = Color.white.opacity(0.05)

    /// Border color for glass cards
    static let glassBorder = Color.white.opacity(0.1)

    // MARK: - Methods

    /// Returns the appropriate color based on usage percentage
    /// - Parameter usage: Usage percentage (0-100)
    /// - Returns: Color corresponding to the usage level
    static func colorForUsage(_ usage: Double) -> Color {
        switch usage {
        case 0..<50:
            return green
        case 50..<75:
            return yellow
        case 75..<90:
            return orange
        default:
            return red
        }
    }

    /// Returns gradient colors for usage visualization
    /// - Parameter usage: Usage percentage (0-100)
    /// - Returns: Array of colors for gradient
    static func gradientForUsage(_ usage: Double) -> [Color] {
        let primaryColor = colorForUsage(usage)
        return [primaryColor.opacity(0.8), primaryColor]
    }

    /// Returns NSColor for AppKit compatibility
    static func nsColorForUsage(_ usage: Double) -> NSColor {
        return NSColor(colorForUsage(usage))
    }
}

// MARK: - Color Extensions for Theme

extension Color {
    static let usageGreen = ColorTheme.green
    static let usageYellow = ColorTheme.yellow
    static let usageOrange = ColorTheme.orange
    static let usageRed = ColorTheme.red
    static let claudeAccent = ColorTheme.accent
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 10) {
            Circle().fill(ColorTheme.green).frame(width: 40, height: 40)
            Text("Green (0-50%)")
        }
        HStack(spacing: 10) {
            Circle().fill(ColorTheme.yellow).frame(width: 40, height: 40)
            Text("Yellow (50-75%)")
        }
        HStack(spacing: 10) {
            Circle().fill(ColorTheme.orange).frame(width: 40, height: 40)
            Text("Orange (75-90%)")
        }
        HStack(spacing: 10) {
            Circle().fill(ColorTheme.red).frame(width: 40, height: 40)
            Text("Red (90-100%)")
        }
    }
    .padding()
}

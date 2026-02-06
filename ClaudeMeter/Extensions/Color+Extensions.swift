//
//  Color+Extensions.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import SwiftUI
import AppKit

extension Color {
    /// Initialize Color from hex string
    /// - Parameter hex: Hex color string (e.g., "#FF5733" or "FF5733")
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// Convert to hex string
    var hexString: String {
        guard let components = NSColor(self).cgColor.components else {
            return "#000000"
        }

        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)

        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// Lighten the color by a percentage
    func lighter(by percentage: CGFloat = 0.2) -> Color {
        return self.adjust(by: abs(percentage))
    }

    /// Darken the color by a percentage
    func darker(by percentage: CGFloat = 0.2) -> Color {
        return self.adjust(by: -abs(percentage))
    }

    private func adjust(by percentage: CGFloat) -> Color {
        let nsColor = NSColor(self)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        nsColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        let newBrightness = max(min(brightness + percentage, 1.0), 0.0)

        return Color(NSColor(
            hue: hue,
            saturation: saturation,
            brightness: newBrightness,
            alpha: alpha
        ))
    }

    /// Interpolate between two colors
    static func interpolate(from: Color, to: Color, progress: CGFloat) -> Color {
        let fromNS = NSColor(from)
        let toNS = NSColor(to)

        var fromR: CGFloat = 0, fromG: CGFloat = 0, fromB: CGFloat = 0, fromA: CGFloat = 0
        var toR: CGFloat = 0, toG: CGFloat = 0, toB: CGFloat = 0, toA: CGFloat = 0

        fromNS.getRed(&fromR, green: &fromG, blue: &fromB, alpha: &fromA)
        toNS.getRed(&toR, green: &toG, blue: &toB, alpha: &toA)

        let clampedProgress = max(0, min(1, progress))

        return Color(
            red: Double(fromR + (toR - fromR) * clampedProgress),
            green: Double(fromG + (toG - fromG) * clampedProgress),
            blue: Double(fromB + (toB - fromB) * clampedProgress),
            opacity: Double(fromA + (toA - fromA) * clampedProgress)
        )
    }
}

// Note: NSColor(Color) is available natively on macOS 11+

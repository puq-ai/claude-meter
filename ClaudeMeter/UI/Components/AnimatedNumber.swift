//
//  AnimatedNumber.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import SwiftUI

/// Animated number display with smooth transitions
struct AnimatedNumber: View {
    let value: Double
    let format: String
    let color: Color
    var accessibilityLabelText: String?

    @State private var displayedValue: Double = 0
    @State private var isAnimating: Bool = false

    init(value: Double, format: String = "%.0f", color: Color = .primary, accessibilityLabel: String? = nil) {
        self.value = value
        self.format = format
        self.color = color
        self.accessibilityLabelText = accessibilityLabel
    }

    var body: some View {
        Text(String(format: format, displayedValue))
            .monospacedDigit()
            .foregroundColor(color)
            .contentTransition(.numericText(value: displayedValue))
            .task(id: value) {
                if displayedValue == 0 {
                    // Initial load without animation
                    displayedValue = value
                } else {
                    // Subsequent updates with animation
                    withAnimation(.easeInOut(duration: 0.5)) {
                        displayedValue = value
                    }
                }
            }
            .accessibilityLabel(accessibilityLabelText ?? String(format: format, value))
    }
}

/// Animated percentage display
struct AnimatedPercentage: View {
    let value: Double

    var body: some View {
        HStack(spacing: 0) {
            AnimatedNumber(
                value: value,
                format: "%.0f",
                color: ColorTheme.colorForUsage(value)
            )
            Text("%")
                .foregroundColor(ColorTheme.colorForUsage(value))
        }
        .font(.system(.title2, design: .rounded).bold())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int(value)) percent")
        .accessibilityValue("\(Int(value))")
    }
}

/// Countdown timer with animated transitions
struct AnimatedCountdown: View {
    let targetDate: Date

    @State private var hours: Int = 0
    @State private var minutes: Int = 0

    var body: some View {
        HStack(spacing: 2) {
            Text("\(hours)")
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("h")
            Text("\(String(format: "%02d", minutes))")
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("m")
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .onAppear {
            updateTime()
        }
    }

    private func updateTime() {
        let diff = targetDate.timeIntervalSinceNow
        guard diff > 0 else {
            hours = 0
            minutes = 0
            return
        }

        hours = Int(diff) / 3600
        minutes = (Int(diff) % 3600) / 60
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 30) {
        AnimatedNumber(value: 75, format: "%.1f%%", color: .orange)
            .font(.title)

        AnimatedPercentage(value: 45)

        AnimatedPercentage(value: 85)

        AnimatedCountdown(targetDate: Date().addingTimeInterval(3700))
    }
    .padding()
}

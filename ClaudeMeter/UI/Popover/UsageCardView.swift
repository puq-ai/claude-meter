//
//  UsageCardView.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import SwiftUI

struct UsageCardView: View {
    let title: String
    let usage: Double // Percentage 0-100
    let resetsAt: Date?

    private var progressColor: Color {
        ColorTheme.colorForUsage(usage)
    }

    private var isCritical: Bool {
        usage >= 90
    }

    private var usageLevel: String {
        switch usage {
        case 0..<50: return "low"
        case 50..<75: return "moderate"
        case 75..<90: return "high"
        default: return "critical"
        }
    }

    private var accessibilityDescription: String {
        var description = "\(title): \(Int(usage)) percent, \(usageLevel) usage"
        if let date = resetsAt {
            description += ". Resets in \(date.timeRemainingFormatted(style: .accessibilityFriendly))"
        }
        return description
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                AnimatedPercentage(value: usage)
            }

            // Progress Ring and Details
            HStack(spacing: 16) {
                // Progress Ring with pulse effect for critical usage
                ProgressRingView(
                    progress: usage / 100.0,
                    color: progressColor,
                    lineWidth: 6,
                    size: 50
                )
                .glowEffect(isActive: isCritical, color: progressColor)

                // Details
                VStack(alignment: .leading, spacing: 4) {
                    // Linear progress bar
                    ProgressBarView(
                        progress: usage / 100.0,
                        showPercentage: false,
                        height: 6
                    )
                    .frame(maxWidth: .infinity)

                    // Reset countdown
                    if let date = resetsAt {
                        HStack(spacing: 4) {
                            Image(systemName: "timer")
                                .font(.caption2)
                            Text("Resets: \(date.timeRemainingFormatted())")
                                .font(.caption2)
                        }
                        .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
        )
        .shadow(color: isCritical ? progressColor.opacity(0.3) : .clear, radius: isCritical ? 8 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityValue("\(Int(usage)) percent")
    }
}

// MARK: - Compact Card Variant

struct CompactUsageCardView: View {
    let title: String
    let usage: Double
    let resetsAt: Date?

    private var progressColor: Color {
        ColorTheme.colorForUsage(usage)
    }

    var body: some View {
        HStack {
            // Progress circle
            CircularProgressBar(
                progress: usage / 100.0,
                lineWidth: 4,
                size: 36,
                showLabel: false
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(Int(usage))%")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(progressColor)
                }

                if let date = resetsAt {
                    Text(date.timeRemainingFormatted())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        UsageCardView(
            title: "5-Hour Limit",
            usage: 45,
            resetsAt: Date().addingTimeInterval(3600)
        )

        UsageCardView(
            title: "7-Day Limit",
            usage: 78,
            resetsAt: Date().addingTimeInterval(86400 * 3)
        )

        UsageCardView(
            title: "Opus Limit",
            usage: 95,
            resetsAt: Date().addingTimeInterval(86400 * 5)
        )

        Divider()

        CompactUsageCardView(
            title: "5-Hour",
            usage: 45,
            resetsAt: Date().addingTimeInterval(3600)
        )
    }
    .padding()
    .frame(width: 320)
}

//
//  TokenUsageCardView.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import SwiftUI

/// Card displaying token usage statistics
struct TokenUsageCardView: View {
    let title: String
    let inputTokens: Int
    let outputTokens: Int
    let icon: String

    private var totalTokens: Int {
        inputTokens + outputTokens
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ColorTheme.accent)

                Text(title)
                    .font(.headline)

                Spacer()
            }

            // Token breakdown
            VStack(spacing: 8) {
                StatRowView(
                    label: "Input",
                    value: formatTokens(inputTokens),
                    color: .blue
                )

                StatRowView(
                    label: "Output",
                    value: formatTokens(outputTokens),
                    color: .green
                )

                Divider()
                    .padding(.vertical, 2)

                StatRowView(
                    label: "Total",
                    value: formatTokens(totalTokens),
                    color: ColorTheme.accent,
                    isBold: true
                )
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
        )
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        } else {
            return "\(count)"
        }
    }
}

/// Row showing a statistic label and value
struct StatRowView: View {
    let label: String
    let value: String
    var color: Color = .primary
    var isBold: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(isBold ? .headline : .subheadline)
                .fontWeight(isBold ? .bold : .medium)
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        TokenUsageCardView(
            title: "Token Usage (Today)",
            inputTokens: 45230,
            outputTokens: 12450,
            icon: "chart.bar.fill"
        )

        TokenUsageCardView(
            title: "Token Usage (7 Days)",
            inputTokens: 1_234_567,
            outputTokens: 345_678,
            icon: "calendar"
        )
    }
    .padding()
    .frame(width: 320)
}

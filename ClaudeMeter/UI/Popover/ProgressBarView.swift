//
//  ProgressBarView.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import SwiftUI

/// Linear progress bar with color coding
struct ProgressBarView: View {
    let progress: Double  // 0.0 to 1.0
    let showPercentage: Bool
    let height: CGFloat
    let cornerRadius: CGFloat
    let animated: Bool
    var accessibilityLabelText: String?

    @State private var displayedProgress: Double = 0

    init(
        progress: Double,
        showPercentage: Bool = true,
        height: CGFloat = 8,
        cornerRadius: CGFloat = 4,
        animated: Bool = true,
        accessibilityLabel: String? = nil
    ) {
        self.progress = progress
        self.showPercentage = showPercentage
        self.height = height
        self.cornerRadius = cornerRadius
        self.animated = animated
        self.accessibilityLabelText = accessibilityLabel
    }

    private var color: Color {
        ColorTheme.colorForUsage(progress * 100)
    }

    private var usageLevel: String {
        let percentage = progress * 100
        switch percentage {
        case 0..<50: return "low"
        case 50..<75: return "moderate"
        case 75..<90: return "high"
        default: return "critical"
        }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.primary.opacity(0.08))

                    // Progress
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(min(max(displayedProgress, 0), 1)))
                }
            }
            .frame(height: height)

            if showPercentage {
                Text("\(Int(displayedProgress * 100))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
        .onAppear {
            if animated {
                withAnimation(.easeInOut(duration: 0.5)) {
                    displayedProgress = progress
                }
            } else {
                displayedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            if animated {
                withAnimation(.easeInOut(duration: 0.3)) {
                    displayedProgress = newValue
                }
            } else {
                displayedProgress = newValue
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText ?? "Progress bar")
        .accessibilityValue("\(Int(displayedProgress * 100)) percent, \(usageLevel) usage")
    }
}

/// Segmented progress bar showing multiple values
struct SegmentedProgressBar: View {
    let segments: [(label: String, value: Double)]
    let height: CGFloat

    init(segments: [(String, Double)], height: CGFloat = 6) {
        self.segments = segments.map { (label: $0.0, value: $0.1) }
        self.height = height
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                HStack {
                    Text(segment.label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .leading)

                    ProgressBarView(
                        progress: segment.value / 100,
                        showPercentage: false,
                        height: height
                    )

                    Text("\(Int(segment.value))%")
                        .font(.caption)
                        .foregroundColor(ColorTheme.colorForUsage(segment.value))
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
    }
}

/// Circular progress indicator
struct CircularProgressBar: View {
    let progress: Double
    let lineWidth: CGFloat
    let size: CGFloat
    let showLabel: Bool

    init(progress: Double, lineWidth: CGFloat = 8, size: CGFloat = 60, showLabel: Bool = true) {
        self.progress = progress
        self.lineWidth = lineWidth
        self.size = size
        self.showLabel = showLabel
    }

    private var color: Color {
        ColorTheme.colorForUsage(progress * 100)
    }

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)

            // Progress arc
            Circle()
                .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: progress)

            if showLabel {
                Text("\(Int(progress * 100))%")
                    .font(.system(.caption, design: .rounded).bold())
                    .foregroundColor(color)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 30) {
        VStack(alignment: .leading, spacing: 8) {
            Text("Linear Progress").font(.headline)
            ProgressBarView(progress: 0.45)
            ProgressBarView(progress: 0.75)
            ProgressBarView(progress: 0.95)
        }

        Divider()

        VStack(alignment: .leading, spacing: 8) {
            Text("Segmented Progress").font(.headline)
            SegmentedProgressBar(segments: [
                ("5-Hour", 45),
                ("7-Day", 23),
                ("Opus", 78)
            ])
        }

        Divider()

        HStack(spacing: 20) {
            CircularProgressBar(progress: 0.25)
            CircularProgressBar(progress: 0.65)
            CircularProgressBar(progress: 0.90)
        }
    }
    .padding()
    .frame(width: 300)
}

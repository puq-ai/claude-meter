//
//  PopoverView.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import SwiftUI

struct PopoverView: View {
    @ObservedObject var appState: AppState
    @State private var showingSettings = false
    @State private var isRefreshDisabled = false

    // Size constants
    private let popoverWidth: CGFloat = 380
    private let popoverHeight: CGFloat = 420
    private let contentPadding: CGFloat = 16

    var body: some View {
        ZStack {
            // Main content - No frame, adapts to parent size
            VStack(spacing: 0) {
                headerView
                    .padding(.horizontal, contentPadding)
                    .padding(.top, contentPadding)

                Divider()
                    .opacity(0.3)
                    .padding(.vertical, 8)

                // Content
                contentView

                Divider()
                    .opacity(0.3)

                footerView
                    .padding(.horizontal, contentPadding)
                    .padding(.vertical, 10)
            }
            .opacity(showingSettings ? 0 : 1)

            // Settings - full page (not overlay)
            if showingSettings {
                SettingsView(appState: appState, onDismiss: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showingSettings = false
                    }
                })
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(width: popoverWidth, height: popoverHeight)
        .background(.ultraThinMaterial)
        .preferredColorScheme(appState.settings.colorScheme.colorScheme)
        .animation(.easeInOut(duration: 0.25), value: showingSettings)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        // Checked before the data/error ladder: with nothing to authenticate with, neither
        // "No Usage Data - click refresh" nor a raw error is an answer the user can act on.
        if appState.authState == .needsLogin, appState.usageData == nil {
            ConnectView(appState: appState)
        } else if let data = appState.usageData {
            usageContentView(data: data)
        } else if let error = appState.error {
            errorView(error: error)
        } else {
            emptyStateView
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("Claude Code Usage")
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            ProgressView()
                .controlSize(.small)
                .opacity(appState.isLoading ? 1 : 0)
                .accessibilityLabel("Loading usage data")

            Button(action: {
                guard !isRefreshDisabled else { return }
                isRefreshDisabled = true
                Task {
                    await appState.refresh(reason: "manual_refresh")
                    try? await Task.sleep(nanoseconds: UInt64(Constants.RateLimit.manualRefreshDebounce * 1_000_000_000))
                    isRefreshDisabled = false
                }
            }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .opacity(isRefreshDisabled ? 0.5 : 1.0)
            .help("Refresh usage data")
            .accessibilityLabel("Refresh")
            .accessibilityHint("Double tap to refresh usage data")

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingSettings = true
                }
            }) {
                Image(systemName: "gear")
            }
            .buttonStyle(.plain)
            .help("Open settings")
            .accessibilityLabel("Settings")
            .accessibilityHint("Double tap to open settings")

            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.plain)
            .help("Quit ClaudeMeter")
            .accessibilityLabel("Quit")
            .accessibilityHint("Double tap to quit ClaudeMeter")
        }
        .frame(height: 22)
    }

    // MARK: - Usage Content

    private func usageContentView(data: UsageData) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                let windows = data.displayWindows
                // Scoped limits (per model or surface) are hideable; the overall windows
                // always show.
                let visibleWindows = windows.filter {
                    !$0.isScoped || appState.settings.showScopedLimits
                }

                if windows.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                        Text("Usage data structure not recognized")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }

                // Every limit the server reports, named by the server.
                ForEach(visibleWindows) { window in
                    UsageCardView(
                        title: window.title,
                        usage: window.usage,
                        resetsAt: window.resetsAt,
                        severity: window.severity,
                        isActive: window.isActive
                    )
                }

                // The server always sends the overall windows today, so this only shows if
                // it ever reports scoped limits alone — without it the popover would look
                // empty with no explanation.
                if !windows.isEmpty && visibleWindows.isEmpty {
                    Text("Model limits are hidden. Enable them in Settings.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }

                if appState.settings.showBreakdown,
                   let breakdown = data.sevenDayBreakdown,
                   !breakdown.significantRows.isEmpty {
                    breakdownCardView(breakdown: breakdown)
                }

                // `extra_usage.is_enabled` describes the credits feature; `spend.enabled`
                // describes the spend the card actually renders. Either one being on is
                // reason enough to show it.
                if appState.settings.showExtraUsage,
                   let extra = data.extraUsage,
                   extra.isEnabled || data.spend?.enabled == true {
                    extraUsageCardView(extra: extra, spend: data.spend)
                }
            }
            .padding(.horizontal, contentPadding)
            .padding(.vertical, 8)
            .background(ScrollBarHider())
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Error View

    private func errorView(error: Error) -> some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundColor(ColorTheme.orange)

            Text("Error loading data")
                .font(.headline)

            Text(error.localizedDescription)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Recovery suggestion if available
            if let appError = error as? AppError,
               let suggestion = appError.recoverySuggestion {
                Text(suggestion)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button("Retry") {
                guard !isRefreshDisabled else { return }
                isRefreshDisabled = true
                Task {
                    await appState.refresh(reason: "retry_button")
                    try? await Task.sleep(nanoseconds: UInt64(Constants.RateLimit.manualRefreshDebounce * 1_000_000_000))
                    isRefreshDisabled = false
                }
            }
            .buttonStyle(.bordered)
            .disabled(isRefreshDisabled)

            Spacer()
        }
        .padding()
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 36))
                .foregroundColor(.secondary)

            Text("No Usage Data")
                .font(.headline)

            Text("Click refresh to load your Claude Code usage.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Refresh") {
                guard !isRefreshDisabled else { return }
                isRefreshDisabled = true
                Task {
                    await appState.refresh(reason: "empty_state_refresh")
                    try? await Task.sleep(nanoseconds: UInt64(Constants.RateLimit.manualRefreshDebounce * 1_000_000_000))
                    isRefreshDisabled = false
                }
            }
            .buttonStyle(.bordered)
            .disabled(isRefreshDisabled)

            Spacer()
        }
        .padding()
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            if let error = appState.error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundColor(ColorTheme.orange)
                Text(error.localizedDescription)
                    .font(.caption2)
                    .foregroundColor(ColorTheme.orange)
                    // Auth errors are the longest and the most important to read in full.
                    // Cached data keeps them off the main view, so this is all the user sees.
                    .lineLimit(appState.authState.needsAttention ? 3 : 1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)

                if appState.authState.needsAttention {
                    Button("Reconnect") {
                        WebLoginController.shared.present { outcome in
                            guard case .signedIn(let sessionKey, let organizations) = outcome,
                                  let organization = organizations.preferredForUsage else { return }
                            appState.applyWebSession(sessionKey: sessionKey, organization: organization)
                        }
                    }
                    .buttonStyle(.link)
                    .font(.caption2)
                }
            } else if let lastUpdate = appState.lastUpdateTime {
                Text("Updated \(lastUpdate.relativeDescription)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Powered by puq.ai (sağ tarafa taşındı)
            poweredByView
        }
    }

    // MARK: - Breakdown Card

    /// Shows what is consuming the 7-day window (Claude Code / Chats / Cowork / Other).
    ///
    /// These are SHARES of consumption, not utilization. A 100% share is normal and must
    /// never be painted with the usage thresholds, hence the neutral accent tint.
    private func breakdownCardView(breakdown: SevenDayBreakdown) -> some View {
        let rows = breakdown.significantRows

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("7-Day Breakdown")
                    .font(.headline)
                Spacer()
            }

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                let percent = row.percent ?? 0
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(row.displayName ?? "Other")
                            .font(.caption)
                        Spacer()
                        Text("\(Int(percent))%")
                            .font(.caption)
                            .fontWeight(.medium)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }

                    ProgressBarView(
                        progress: percent / 100.0,
                        showPercentage: false,
                        height: 4,
                        tint: ColorTheme.accent
                    )
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.displayName ?? "Other"): \(Int(percent)) percent of 7-day usage")
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: - Extra Usage Card

    private func extraUsageCardView(extra: ExtraUsage, spend: SpendInfo?) -> some View {
        // `extra_usage` now reports null credit figures; `spend` carries the real numbers.
        let utilization = extra.utilization ?? spend?.percent ?? 0
        let progressColor = ColorTheme.colorForSeverity(spend?.severity, fallbackUsage: utilization)
        let isCritical = spend?.severity == .critical || utilization >= 90

        let spentAmount = extra.usedCredits.map { $0 / 100.0 } ?? spend?.used?.amount
        let limitAmount = extra.monthlyLimit.map { $0 / 100.0 }
        let currencyCode = spend?.used?.currency ?? extra.currency

        return VStack(spacing: 12) {
            // Header
            HStack {
                Text("Extra Usage")
                    .font(.headline)
                Spacer()
                AnimatedPercentage(value: utilization)
            }

            // Progress Ring and Details
            HStack(spacing: 16) {
                ProgressRingView(
                    progress: utilization / 100.0,
                    color: progressColor,
                    lineWidth: 6,
                    size: 50
                )
                .glowEffect(isActive: isCritical, color: progressColor)

                VStack(alignment: .leading, spacing: 4) {
                    ProgressBarView(
                        progress: utilization / 100.0,
                        showPercentage: false,
                        height: 6,
                        tint: progressColor
                    )
                    .frame(maxWidth: .infinity)

                    // Spending info
                    if let spent = spentAmount {
                        HStack(spacing: 4) {
                            Image(systemName: "dollarsign.circle")
                                .font(.caption2)
                            Text(Self.spendDescription(spent: spent, limit: limitAmount, currencyCode: currencyCode))
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
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: isCritical ? progressColor.opacity(0.3) : .clear, radius: isCritical ? 8 : 0)
    }

    /// Formats spend, honouring the server's currency instead of assuming dollars.
    private static func spendDescription(spent: Double, limit: Double?, currencyCode: String?) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode ?? "USD"

        func format(_ value: Double, fractionDigits: Int) -> String {
            formatter.minimumFractionDigits = fractionDigits
            formatter.maximumFractionDigits = fractionDigits
            return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(fractionDigits)f", value)
        }

        let spentText = format(spent, fractionDigits: 2)
        guard let limit = limit else {
            return "\(spentText) spent"
        }
        return "\(spentText) spent of \(format(limit, fractionDigits: 0)) limit"
    }

    // MARK: - Powered By View

    private var poweredByView: some View {
        Button(action: {
            if let url = URL(string: "https://puq.ai") {
                NSWorkspace.shared.open(url)
            }
        }) {
            HStack(spacing: 4) {
                Text("powered by")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.7))

                HStack(spacing: 2) {
                    Text("puq")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(ColorTheme.accent)
                    Text(".ai")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .help("Visit puq.ai")
    }
}

// MARK: - ScrollBar Hider

struct ScrollBarHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            Self.hideScrollBars(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Self.hideScrollBars(for: nsView)
    }

    private static func hideScrollBars(for view: NSView) {
        guard let scrollView = view.enclosingScrollView else { return }
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
    }
}

// MARK: - Preview

#Preview {
    PopoverView(appState: AppState())
}

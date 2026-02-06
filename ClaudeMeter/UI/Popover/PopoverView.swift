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
        if let data = appState.usageData {
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
                Task { await appState.refresh() }
            }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
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
                if let fiveHour = data.fiveHour {
                    UsageCardView(
                        title: "5-Hour Limit",
                        usage: fiveHour.utilization,
                        resetsAt: fiveHour.resetsAt
                    )
                }

                if let sevenDay = data.sevenDay {
                    UsageCardView(
                        title: "7-Day Limit",
                        usage: sevenDay.utilization,
                        resetsAt: sevenDay.resetsAt
                    )
                }

                if appState.settings.showOpusLimit, let opus = data.sevenDayOpus {
                    UsageCardView(
                        title: "Opus Limit",
                        usage: opus.utilization,
                        resetsAt: opus.resetsAt
                    )
                }
            }
            .padding(.horizontal, contentPadding)
            .padding(.vertical, 8)
        }
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
                Task { await appState.refresh() }
            }
            .buttonStyle(.bordered)

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
                Task { await appState.refresh() }
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding()
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            if let lastUpdate = appState.lastUpdateTime {
                Text("Updated \(lastUpdate.relativeDescription)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Powered by puq.ai (sağ tarafa taşındı)
            poweredByView
        }
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

// MARK: - Preview

#Preview {
    PopoverView(appState: AppState())
}

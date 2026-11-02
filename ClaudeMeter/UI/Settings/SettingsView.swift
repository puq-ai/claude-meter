//
//  SettingsView.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    var onDismiss: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Fixed Header
            headerView

            // Fixed Tab Picker
            tabPickerView

            // Scrollable Content - fills remaining space
            contentView
                .padding(.top, 5)
                .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Header View
    private var headerView: some View {
        HStack {
            Button(action: {
                if let onDismiss = onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Go back")

            Spacer()

            Text("Settings")
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()

            // Balance placeholder (invisible)
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text("Back")
            }
            .opacity(0)
        }
        .padding(.horizontal)
        .padding(.top, 20)
        .padding(.bottom, 20)
    }

    // MARK: - Tab Picker View
    private var tabPickerView: some View {
        // Text-only, small, content-sized segments: on current macOS the regular-size
        // segmented control with Labels outgrows the 380pt popover and is clipped at both edges.
        Picker("", selection: $selectedTab) {
            Text("General").tag(0)
            Text("Appearance").tag(1)
            Text("Notifications").tag(2)
            Text("About").tag(3)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Content View
    private var contentView: some View {
        Group {
            switch selectedTab {
            case 0: GeneralSettingsView(appState: appState)
            case 1: AppearanceSettingsView(appState: appState)
            case 2: NotificationSettingsView(appState: appState)
            case 3: AboutView()
            default: EmptyView()
            }
        }
    }
}

// MARK: - Settings Tab Container
struct SettingsTabContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: Constants.UI.settingsMaxWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 6)
    }
}

// MARK: - Preview
#Preview {
    SettingsView(appState: AppState())
}

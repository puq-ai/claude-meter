//
//  GeneralSettingsView.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import SwiftUI
import ServiceManagement

// MARK: - General Settings
struct GeneralSettingsView: View {
    @ObservedObject var appState: AppState
    @State private var launchAtLoginError: String?

    var body: some View {
        SettingsTabContainer {
            Form {
                Section {
                    Toggle("Launch at Login", isOn: Binding(
                        get: { appState.settings.launchAtLogin },
                        set: { newValue in
                            appState.settings.launchAtLogin = newValue
                            toggleLaunchAtLogin(newValue)
                        }
                    ))
                    .help("Automatically start ClaudeMeter when you log in.")
                    .accessibilityLabel("Launch at Login")
                    .accessibilityHint("When enabled, ClaudeMeter will start automatically when you log in")

                    if let error = launchAtLoginError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(ColorTheme.red)
                            .accessibilityLabel("Error: \(error)")
                    }

                    Toggle("Show Model Limits", isOn: $appState.settings.showScopedLimits)
                        .help("Display per-model weekly limits reported by the API (e.g. Fable).")
                    Toggle("Show Usage Breakdown", isOn: $appState.settings.showBreakdown)
                        .help("Display what is consuming your 7-day limit (Claude Code, Chats, Cowork).")
                    Toggle("Show Extra Usage", isOn: $appState.settings.showExtraUsage)
                        .help("Display extra usage spending information.")

                    Toggle("Show in Dock", isOn: Binding(
                        get: { appState.settings.showInDock },
                        set: { newValue in
                            appState.settings.showInDock = newValue
                            updateDockVisibility(newValue)
                        }
                    ))
                    .help("Show ClaudeMeter icon in the Dock.")
                    .accessibilityLabel("Show in Dock")
                    .accessibilityHint("When enabled, ClaudeMeter will appear in the Dock")

                    Picker("Refresh Interval", selection: $appState.settings.refreshInterval) {
                        Text("30 Seconds").tag(30)
                        Text("1 Minute").tag(60)
                        Text("2 Minutes").tag(120)
                        Text("5 Minutes").tag(300)
                    }
                    .accessibilityLabel("Refresh Interval")
                    .accessibilityHint("Choose how often to update usage data")
                }
                .background(ScrollBarHider())

                Section(header: Text("claude.ai Fallback")) {
                    HStack {
                        Image(systemName: isWebSessionConnected ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundColor(isWebSessionConnected ? ColorTheme.green : .secondary)
                        Text(connectionSummary)
                            .font(.caption)
                        Spacer()
                        if isWebSessionConnected {
                            Button("Sign Out") { appState.signOutOfWebSession() }
                                .controlSize(.small)
                        } else {
                            Button("Sign In…") { startWebLogin() }
                                .controlSize(.small)
                                .disabled(isSigningIn)
                        }
                    }

                    if discoveredOrganizations.count > 1 {
                        Picker("Organization", selection: organizationSelection) {
                            ForEach(discoveredOrganizations) { organization in
                                Text(organization.name).tag(organization.id)
                            }
                        }
                        .font(.caption)
                    }

                    // The fallback runs on ANY primary API failure, not just rate limiting -
                    // the old copy here said otherwise and was simply wrong.
                    Text("Used whenever the Claude Code API can't be reached. Signing in stores a claude.ai session in your Keychain.")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    DisclosureGroup("Advanced") {
                        TextField("Organization ID", text: $appState.settings.webOrganizationId)
                            .font(.caption)
                            .help("Organization UUID from the claude.ai URL. Filled in automatically after signing in.")
                    }
                    .font(.caption)
                }
            }
            .formStyle(.grouped)
            .scrollIndicators(.hidden)

        }
    }

    // MARK: - claude.ai session

    @State private var isSigningIn = false
    @State private var discoveredOrganizations: [WebOrganization] = []

    private var isWebSessionConnected: Bool {
        appState.isWebSessionConfigured
    }

    private var connectionSummary: String {
        guard isWebSessionConnected else { return "Not connected" }
        let name = appState.settings.webOrganizationName
        return name.isEmpty ? "Connected" : "Connected as \(name)"
    }

    private var organizationSelection: Binding<String> {
        Binding(
            get: { appState.settings.webOrganizationId },
            set: { newId in
                guard let organization = discoveredOrganizations.first(where: { $0.id == newId }) else { return }
                var updated = appState.settings
                updated.webOrganizationId = organization.id
                updated.webOrganizationName = organization.name
                appState.settings = updated
            }
        )
    }

    private func startWebLogin() {
        isSigningIn = true
        WebLoginController.shared.present { outcome in
            isSigningIn = false
            guard case .signedIn(let sessionKey, let organizations) = outcome,
                  let organization = organizations.preferredForUsage else { return }
            discoveredOrganizations = organizations
            appState.applyWebSession(sessionKey: sessionKey, organization: organization)
        }
    }

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginError = "Failed to update: \(error.localizedDescription)"
            // Revert the setting on failure
            appState.settings.launchAtLogin = !enabled
        }
    }

    private func updateDockVisibility(_ showInDock: Bool) {
        if showInDock {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

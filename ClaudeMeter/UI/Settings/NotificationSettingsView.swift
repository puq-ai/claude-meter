//
//  NotificationSettingsView.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import SwiftUI

// MARK: - Notification Settings
struct NotificationSettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        SettingsTabContainer {
            Form {
                Section(header: Text("Notifications")) {
                    Toggle("Enable Notifications", isOn: $appState.settings.notificationsEnabled)
                        .help("Receive alerts when usage approaches limits.")
                }

                Section(header: Text("Alert Thresholds")) {
                    Toggle("75% Usage Warning", isOn: Binding(
                        get: { appState.settings.notifyAt.contains(75) },
                        set: { enabled in
                            updateThreshold(75, enabled: enabled)
                        }
                    ))
                    .disabled(!appState.settings.notificationsEnabled)

                    Toggle("90% Usage Alert", isOn: Binding(
                        get: { appState.settings.notifyAt.contains(90) },
                        set: { enabled in
                            updateThreshold(90, enabled: enabled)
                        }
                    ))
                    .disabled(!appState.settings.notificationsEnabled)

                    Toggle("95% Critical Alert", isOn: Binding(
                        get: { appState.settings.notifyAt.contains(95) },
                        set: { enabled in
                            updateThreshold(95, enabled: enabled)
                        }
                    ))
                    .disabled(!appState.settings.notificationsEnabled)
                }

                Section {
                    HStack {
                        Spacer()
                        Button("Request Notification Permission") {
                            Task {
                                _ = await NotificationService.shared.requestPermission()
                            }
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                    }
                }
            }
            .formStyle(.grouped)
            .scrollIndicators(.hidden)
        }
    }

    private func updateThreshold(_ threshold: Int, enabled: Bool) {
        if enabled {
            if !appState.settings.notifyAt.contains(threshold) {
                appState.settings.notifyAt.append(threshold)
                appState.settings.notifyAt.sort()
            }
        } else {
            appState.settings.notifyAt.removeAll { $0 == threshold }
        }
    }
}

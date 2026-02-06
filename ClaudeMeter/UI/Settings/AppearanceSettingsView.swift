//
//  AppearanceSettingsView.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import SwiftUI

// MARK: - Appearance Settings
struct AppearanceSettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        SettingsTabContainer {
            Form {
                Section(header: Text("Menu Bar Display")) {
                    Picker("Display Mode", selection: $appState.settings.displayMode) {
                        ForEach(DisplayMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }

                Section(header: Text("Color Scheme")) {
                    Picker("Theme", selection: $appState.settings.colorScheme) {
                        ForEach(AppColorScheme.allCases, id: \.self) { scheme in
                            Text(scheme.rawValue).tag(scheme)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .formStyle(.grouped)
            .scrollIndicators(.hidden)
        }
    }
}

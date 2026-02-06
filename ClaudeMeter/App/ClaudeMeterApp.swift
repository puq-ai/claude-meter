//
//  ClaudeMeterApp.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import SwiftUI
import AppKit

@main
struct ClaudeMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            if let appState = appDelegate.appState {
                SettingsView(appState: appState)
            } else {
                VStack {
                    ProgressView()
                    Text("Loading...")
                }
                .frame(width: 480, height: 320)
            }
        }
    }
}

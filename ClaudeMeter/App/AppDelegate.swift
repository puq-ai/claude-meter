//
//  AppDelegate.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Cocoa
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItemController: StatusItemController?
    private(set) var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // AppState applies persisted settings (dock visibility included) as it initializes.
        let state = AppState()
        appState = state

        statusItemController = StatusItemController(appState: state)

        registerForLifecycleNotifications()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState?.pollingManager.stopNetworkMonitor()
        appState?.pollingManager.stop()
    }

    // MARK: - Lifecycle Notifications

    private func registerForLifecycleNotifications() {
        // App became active (foreground)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.appState?.onAppBecameActive()
        }

        // App resigned active (background)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.appState?.onAppResignedActive()
        }

        // System will sleep
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.appState?.onSystemWillSleep()
        }

        // System did wake
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.appState?.onSystemDidWake()
        }
    }

    // MARK: - App Actions

    @objc func showPopover() {
        statusItemController?.showPopover()
    }

    @objc func hidePopover() {
        statusItemController?.hidePopover()
    }
}

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
    private var fileWatcher: FileWatcherService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize AppState
        let state = AppState()
        appState = state

        // Apply initial dock visibility setting
        applyDockVisibility()

        // Setup status item controller
        statusItemController = StatusItemController(appState: state)

        // Setup file watcher for credential changes
        setupFileWatcher()

        // Register for app lifecycle notifications
        registerForLifecycleNotifications()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup
        fileWatcher?.stopWatching()
        appState?.pollingManager.stopNetworkMonitor()
        appState?.pollingManager.stop()
    }

    // MARK: - Dock Visibility

    private func applyDockVisibility() {
        guard let appState = appState else { return }
        if appState.settings.showInDock {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - File Watcher

    private func setupFileWatcher() {
        fileWatcher = FileWatcherService()
        fileWatcher?.startWatching { [weak self] in
            // Credential file changed, refresh data
            Task {
                await self?.appState?.refresh()
            }
        }
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

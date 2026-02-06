//
//  AppState.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation
import Combine
import AppKit

@MainActor
class AppState: ObservableObject {
    // Usage Data
    @Published var usageData: UsageData?
    @Published var isLoading: Bool = false
    @Published var lastUpdateTime: Date?
    @Published var error: Error?


    // Previous usage for notification comparison
    private var previousUsageData: UsageData?

    // Wake recovery
    private var wakeRetryTask: Task<Void, Never>?

    // UI State
    @Published var isPopoverShown: Bool = false

    // Settings - Single source of truth with UserDefaults
    @Published var settings: AppSettings {
        didSet {
            saveSettings()
            applySettings()
        }
    }

    // Managers
    private let usageManager: UsageManager
    let pollingManager: PollingManager

    private var cancellables = Set<AnyCancellable>()

    init() {
        // PHASE 1: Sync, fast initialization
        self.usageManager = UsageManager()
        self.pollingManager = PollingManager()

        // Load settings from UserDefaults
        self.settings = AppSettings.load()

        setupBindings()
        applySettings()

        // Setup network monitor for wake recovery
        pollingManager.startNetworkMonitor { [weak self] in
            Task { @MainActor in
                self?.onNetworkBecameAvailable()
            }
        }

        // PHASE 2: Deferred polling (300ms delay to let UI render first)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            self?.pollingManager.start { [weak self] in
                await self?.refresh()
            }
        }

        // Request notification permission on first launch (deferred)
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            _ = await NotificationService.shared.requestPermission()
        }
    }

    private func setupBindings() {
        usageManager.$usageData
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newData in
                self?.previousUsageData = self?.usageData
                self?.usageData = newData

                // Check notifications
                if let data = newData {
                    self?.checkNotifications(data)
                    self?.updatePollingInterval(data)
                }
            }
            .store(in: &cancellables)

        usageManager.$isLoading
            .receive(on: DispatchQueue.main)
            .assign(to: &$isLoading)

        usageManager.$error
            .receive(on: DispatchQueue.main)
            .assign(to: &$error)
    }

    // MARK: - Settings Management

    private func loadSettings() {
        settings = AppSettings.load()
    }

    private func saveSettings() {
        settings.save()
    }

    private func applySettings() {
        // Apply refresh interval to polling manager
        pollingManager.setDefaultInterval(TimeInterval(settings.refreshInterval))

        // Apply dock visibility
        if settings.showInDock {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Data Refresh

    func refresh() async {
        await usageManager.fetchUsage()
        if usageManager.error == nil {
            lastUpdateTime = Date()
            pollingManager.recordSuccess()
        } else {
            pollingManager.recordFailure()
        }
    }

    // MARK: - Notifications

    private func checkNotifications(_ data: UsageData) {
        guard settings.notificationsEnabled else { return }

        NotificationService.shared.checkAndNotify(
            usage: data,
            previousUsage: previousUsageData,
            thresholds: settings.notifyAt
        )
    }

    // MARK: - Adaptive Polling

    private func updatePollingInterval(_ data: UsageData) {
        // Calculate max usage across all windows
        let maxUsage = [
            data.fiveHour?.utilization ?? 0,
            data.sevenDay?.utilization ?? 0,
            data.sevenDayOpus?.utilization ?? 0
        ].max() ?? 0

        pollingManager.updateForUsage(maxUsage)
    }

    // MARK: - App Lifecycle

    func onAppBecameActive() {
        pollingManager.onAppBecameActive()
    }

    func onAppResignedActive() {
        pollingManager.onAppResignedActive()
    }

    // MARK: - Sleep/Wake Management

    func onSystemWillSleep() {
        // Cancel any in-progress wake retry
        wakeRetryTask?.cancel()
        wakeRetryTask = nil

        pollingManager.onSystemWillSleep()
        print("AppState: System going to sleep")
    }

    func onSystemDidWake() {
        // Cancel any previous wake retry task
        wakeRetryTask?.cancel()

        let sleepDuration = pollingManager.onSystemDidWake()
        let isSignificantSleep = sleepDuration >= Constants.WakeRecovery.significantSleepDuration

        if isSignificantSleep {
            usageManager.invalidateStaleData()
            print("AppState: Significant sleep (\(String(format: "%.0f", sleepDuration))s), invalidated stale data")
        }

        // Start wake recovery with retry logic
        wakeRetryTask = Task { @MainActor [weak self] in
            guard let self = self else { return }

            // Initial delay for network to become available
            let initialNanos = UInt64(Constants.WakeRecovery.initialDelay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: initialNanos)

            let retryDelays = Constants.WakeRecovery.retryDelays
            for (index, delay) in retryDelays.enumerated() {
                guard !Task.isCancelled else { return }

                print("AppState: Wake recovery attempt \(index + 1)/\(retryDelays.count)")
                await self.refresh()

                if self.usageManager.error == nil && self.usageData != nil {
                    print("AppState: Wake recovery succeeded on attempt \(index + 1)")
                    self.pollingManager.schedulePostWakeTimer()
                    return
                }

                // Wait before next retry (except on last attempt)
                if index < retryDelays.count - 1 {
                    let delayNanos = UInt64(delay * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: delayNanos)
                }
            }

            // All retries exhausted - start normal polling anyway, NWPathMonitor will trigger when network returns
            guard !Task.isCancelled else { return }
            print("AppState: Wake recovery exhausted all retries, falling back to normal polling")
            self.pollingManager.schedulePostWakeTimer()
        }
    }

    // MARK: - Network Recovery

    private func onNetworkBecameAvailable() {
        guard pollingManager.isRunning else { return }

        // If we have no data or data might be stale, refresh immediately
        if usageData == nil {
            print("AppState: Network became available with no data, triggering refresh")
            Task {
                await refresh()
            }
        }
    }
}

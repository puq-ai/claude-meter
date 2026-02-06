//
//  PollingManager.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation
import Combine
import Network

class PollingManager {
    // MARK: - Configuration
    struct Config {
        var defaultInterval: TimeInterval = Constants.Polling.defaultInterval
        var minInterval: TimeInterval = Constants.Polling.minInterval
        var maxInterval: TimeInterval = Constants.Polling.maxInterval
        var backgroundInterval: TimeInterval = Constants.Polling.backgroundInterval

        // Adaptive polling thresholds
        var highUsageThreshold: Double = Constants.Polling.highUsageThreshold
        var criticalUsageThreshold: Double = Constants.Polling.criticalUsageThreshold

        // Circuit breaker for consecutive failures
        var maxConsecutiveFailures: Int = Constants.Polling.maxConsecutiveFailures
        var failureBackoffInterval: TimeInterval = Constants.Polling.failureBackoffInterval
    }

    // MARK: - State
    enum State {
        case idle
        case running
        case paused
        case background
    }

    private(set) var config: Config
    private var timer: Timer?
    private var onTick: (() async -> Void)?
    private var currentInterval: TimeInterval
    private(set) var state: State = .idle
    private var lastUsage: Double = 0

    // Circuit breaker state
    private var consecutiveFailures: Int = 0
    private var isInFailureBackoff: Bool = false

    // Sleep tracking
    private var sleepStartTime: Date?
    private(set) var lastSleepDuration: TimeInterval = 0

    // Network monitoring
    private var networkMonitor: NWPathMonitor?
    private var networkMonitorQueue: DispatchQueue?
    private(set) var isNetworkAvailable: Bool = true
    private var networkBecameAvailableCallback: (() -> Void)?

    // Concurrent fetch guard
    private(set) var isFetching: Bool = false

    // MARK: - Initialization
    init(config: Config = Config()) {
        self.config = config
        self.currentInterval = config.defaultInterval
    }

    // MARK: - Public Methods

    func start(onTick: @escaping () async -> Void) {
        self.onTick = onTick
        state = .running
        scheduleTimer(interval: currentInterval)

        // Trigger immediate guarded fetch
        Task {
            guard beginFetch() else { return }
            defer { endFetch() }
            await onTick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        state = .idle
    }

    func pause() {
        timer?.invalidate()
        timer = nil
        state = .paused
    }

    func resume() {
        guard state == .paused || state == .background else { return }
        state = .running
        scheduleTimer(interval: currentInterval)
    }

    /// Called when app becomes active (foreground)
    func onAppBecameActive() {
        guard state == .background else { return }
        state = .running
        // Use calculated interval based on last known usage
        let newInterval = calculateInterval(for: lastUsage)
        scheduleTimer(interval: newInterval)

        // Immediate guarded refresh when coming to foreground
        Task {
            guard beginFetch() else { return }
            defer { endFetch() }
            await onTick?()
        }
    }

    /// Called when app goes to background
    func onAppResignedActive() {
        guard state == .running else { return }
        state = .background
        scheduleTimer(interval: config.backgroundInterval)
    }

    /// Update polling interval based on usage
    /// - Parameter usage: Current usage percentage (0-100)
    func updateForUsage(_ usage: Double) {
        lastUsage = usage
        guard state == .running, !isInFailureBackoff else { return }

        let newInterval = calculateInterval(for: usage)
        // Hysteresis: only change if difference is significant
        if abs(newInterval - currentInterval) > Constants.Polling.intervalChangeThreshold {
            currentInterval = newInterval
            scheduleTimer(interval: newInterval)
        }
    }

    /// Update configuration
    func updateConfig(_ newConfig: Config) {
        self.config = newConfig
        if state == .running {
            let newInterval = calculateInterval(for: lastUsage)
            scheduleTimer(interval: newInterval)
        }
    }

    /// Set default interval from settings
    func setDefaultInterval(_ interval: TimeInterval) {
        config.defaultInterval = max(config.minInterval, min(interval, config.maxInterval))
        if state == .running && lastUsage < config.highUsageThreshold {
            scheduleTimer(interval: config.defaultInterval)
        }
    }

    /// Record a successful fetch - resets circuit breaker
    func recordSuccess() {
        consecutiveFailures = 0
        if isInFailureBackoff {
            isInFailureBackoff = false
            // Return to normal polling interval
            if state == .running {
                let newInterval = calculateInterval(for: lastUsage)
                scheduleTimer(interval: newInterval)
            }
        }
    }

    /// Record a failed fetch - triggers circuit breaker after threshold
    func recordFailure() {
        consecutiveFailures += 1
        if consecutiveFailures >= config.maxConsecutiveFailures && !isInFailureBackoff {
            isInFailureBackoff = true
            // Switch to longer backoff interval
            if state == .running {
                scheduleTimer(interval: config.failureBackoffInterval)
            }
        }
    }

    // MARK: - Sleep/Wake Management

    /// Called when system is about to sleep
    func onSystemWillSleep() {
        sleepStartTime = Date()
        pause()
        print("PollingManager: System going to sleep at \(sleepStartTime!)")
    }

    /// Called when system wakes from sleep. Returns the sleep duration.
    @discardableResult
    func onSystemDidWake() -> TimeInterval {
        if let start = sleepStartTime {
            lastSleepDuration = Date().timeIntervalSince(start)
        } else {
            lastSleepDuration = 0
        }
        sleepStartTime = nil
        state = .running
        // Do NOT schedule timer here - AppState will manage post-wake timing
        print("PollingManager: System woke after \(String(format: "%.0f", lastSleepDuration))s sleep")
        return lastSleepDuration
    }

    /// Schedule normal polling timer after wake recovery completes
    func schedulePostWakeTimer() {
        guard state == .running else { return }
        let interval = calculateInterval(for: lastUsage)
        scheduleTimer(interval: interval)
        print("PollingManager: Post-wake timer scheduled at \(interval)s interval")
    }

    // MARK: - Network Monitoring

    func startNetworkMonitor(onBecameAvailable: @escaping () -> Void) {
        networkBecameAvailableCallback = onBecameAvailable
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "com.claudemeter.networkmonitor")
        networkMonitor = monitor
        networkMonitorQueue = queue

        monitor.pathUpdateHandler = { [weak self] path in
            let wasAvailable = self?.isNetworkAvailable ?? true
            let isNowAvailable = path.status == .satisfied
            self?.isNetworkAvailable = isNowAvailable

            if !wasAvailable && isNowAvailable {
                print("PollingManager: Network became available")
                DispatchQueue.main.async {
                    self?.networkBecameAvailableCallback?()
                }
            }
        }
        monitor.start(queue: queue)
    }

    func stopNetworkMonitor() {
        networkMonitor?.cancel()
        networkMonitor = nil
        networkMonitorQueue = nil
        networkBecameAvailableCallback = nil
    }

    // MARK: - Concurrent Fetch Guard

    /// Mark fetch as started. Returns false if already fetching.
    func beginFetch() -> Bool {
        guard !isFetching else {
            print("PollingManager: Fetch already in progress, skipping")
            return false
        }
        isFetching = true
        return true
    }

    /// Mark fetch as completed
    func endFetch() {
        isFetching = false
    }

    // MARK: - Private Methods

    /// Calculate optimal polling interval based on current usage
    /// Higher usage = more frequent polling to catch limit resets
    func calculateInterval(for usage: Double) -> TimeInterval {
        if usage >= config.criticalUsageThreshold {
            // Critical: poll every 30 seconds
            return config.minInterval
        } else if usage >= config.highUsageThreshold {
            // High: poll every 45 seconds
            return (config.minInterval + config.defaultInterval) / 2
        } else if usage >= 50 {
            // Medium: use default interval
            return config.defaultInterval
        } else {
            // Low usage: can poll less frequently
            return min(config.defaultInterval * 1.5, config.maxInterval)
        }
    }

    private func scheduleTimer(interval: TimeInterval) {
        timer?.invalidate()
        currentInterval = interval

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task {
                guard let self = self else { return }
                guard self.beginFetch() else { return }
                defer { self.endFetch() }
                await self.onTick?()
            }
        }

        // Ensure timer runs on common run loop mode
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
}

// MARK: - Convenience
extension PollingManager {
    var isRunning: Bool {
        return state == .running
    }

    var isPaused: Bool {
        return state == .paused
    }

    var isInBackground: Bool {
        return state == .background
    }

    var currentPollingInterval: TimeInterval {
        return currentInterval
    }
}

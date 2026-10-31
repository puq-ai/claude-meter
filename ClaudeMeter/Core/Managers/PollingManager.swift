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

/// Main-actor isolated: the timer, the fetch guard and the rate-limit gate are all read and
/// written from AppState, and a timer tick or network change must not race those writes.
@MainActor
final class PollingManager {
    // MARK: - Configuration
    struct Config {
        var defaultInterval: TimeInterval = Constants.Polling.defaultInterval
        var minInterval: TimeInterval = Constants.Polling.minInterval
        var maxInterval: TimeInterval = Constants.Polling.maxInterval

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

    // Network monitoring
    private var networkMonitor: NWPathMonitor?
    /// Last path status NWPathMonitor reported. Failures while this is false are expected and
    /// must not trip the circuit breaker: the network coming back triggers its own refresh.
    private(set) var isNetworkAvailable = true
    private var networkBecameAvailableCallback: (() -> Void)?

    // Rate limit gate
    private var lastRequestTime: Date?
    private var rateLimitCooldownUntil: Date?

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

        // Trigger immediate fetch (performRefresh handles its own fetch guard)
        Task {
            guard canMakeRequest(reason: "start") else { return }
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
        guard state == .paused else { return }
        state = .running
        rescheduleForCurrentState()
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

    /// Set default interval from settings. Reschedules only when the value actually changed,
    /// and never while the circuit breaker holds the timer at its backoff interval - an
    /// unrelated settings edit must not cut a failure or rate-limit backoff short.
    func setDefaultInterval(_ interval: TimeInterval) {
        let clamped = max(config.minInterval, min(interval, config.maxInterval))
        guard clamped != config.defaultInterval else { return }
        config.defaultInterval = clamped
        guard !isInFailureBackoff else { return }
        let newInterval = calculateInterval(for: lastUsage)
        if state == .running {
            scheduleTimer(interval: newInterval)
        } else {
            // Not started yet (launch applies settings before polling begins): `start`
            // schedules with `currentInterval`, which would otherwise still be the default.
            currentInterval = newInterval
        }
    }

    /// Record a successful fetch - resets circuit breaker
    func recordSuccess() {
        consecutiveFailures = 0
        if isInFailureBackoff {
            isInFailureBackoff = false
            rescheduleForCurrentState()
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
        let sleepDuration = sleepStartTime.map { Date().timeIntervalSince($0) } ?? 0
        sleepStartTime = nil
        state = .running
        // Do NOT schedule timer here - AppState will manage post-wake timing
        print("PollingManager: System woke after \(String(format: "%.0f", sleepDuration))s sleep")
        return sleepDuration
    }

    /// Schedule polling after wake recovery completes. Honours a failure backoff or a 429
    /// cooldown still in force: wake recovery ending must not reset either.
    func schedulePostWakeTimer() {
        rescheduleForCurrentState()
        print("PollingManager: Post-wake timer scheduled at \(currentInterval)s interval")
    }

    // MARK: - Network Monitoring

    func startNetworkMonitor(onBecameAvailable: @escaping () -> Void) {
        networkBecameAvailableCallback = onBecameAvailable
        let monitor = NWPathMonitor()
        networkMonitor = monitor

        // The handler runs on the monitor's queue; only the Bool crosses over, and all state
        // is touched on the main actor.
        monitor.pathUpdateHandler = { [weak self] path in
            let isNowAvailable = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.networkPathChanged(isAvailable: isNowAvailable)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.claudemeter.networkmonitor"))
    }

    private func networkPathChanged(isAvailable: Bool) {
        let wasAvailable = isNetworkAvailable
        isNetworkAvailable = isAvailable
        guard !wasAvailable && isAvailable else { return }
        print("PollingManager: Network became available")
        networkBecameAvailableCallback?()
    }

    func stopNetworkMonitor() {
        networkMonitor?.cancel()
        networkMonitor = nil
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
        lastRequestTime = Date()
        return true
    }

    /// Mark fetch as completed
    func endFetch() {
        isFetching = false
    }

    // MARK: - Rate Limit Gate

    /// Central gate for all API requests. Returns false if request should be blocked.
    /// - Parameter enforceMinimumInterval: Timer ticks keep the request spacing. Explicit
    ///   refreshes (user action, credential change, recovery) skip it; the 429 cooldown and
    ///   the in-flight check always apply.
    func canMakeRequest(reason: String = "unknown", enforceMinimumInterval: Bool = true) -> Bool {
        // Check 429 cooldown
        if let cooldownUntil = rateLimitCooldownUntil, Date() < cooldownUntil {
            let remaining = cooldownUntil.timeIntervalSince(Date())
            print("PollingManager: Request blocked (\(reason)) - rate limit cooldown, \(String(format: "%.0f", remaining))s remaining")
            return false
        }

        // Check minimum request interval
        if enforceMinimumInterval, let lastRequest = lastRequestTime {
            let elapsed = Date().timeIntervalSince(lastRequest)
            if elapsed < Constants.RateLimit.minimumRequestInterval {
                print("PollingManager: Request blocked (\(reason)) - too soon, \(String(format: "%.0f", Constants.RateLimit.minimumRequestInterval - elapsed))s remaining")
                return false
            }
        }

        // Check concurrent fetch
        if isFetching {
            print("PollingManager: Request blocked (\(reason)) - fetch already in progress")
            return false
        }

        return true
    }

    /// Record a 429 rate limit hit and enter cooldown
    func recordRateLimitHit(retryAfter: TimeInterval?) {
        // Already in backoff means this 429 answered the post-cooldown probe.
        let probeWasRateLimited = isInFailureBackoff
        let cooldown = Constants.RateLimit.cooldown(retryAfter: retryAfter)
        rateLimitCooldownUntil = Date().addingTimeInterval(cooldown)

        // Activate circuit breaker immediately
        consecutiveFailures = config.maxConsecutiveFailures
        isInFailureBackoff = true

        // One probe when the cooldown ends, then the backoff interval until a fetch succeeds.
        // Probing again after every cooldown polled a rate-limited API faster than normal.
        // The backoff interval is at least the longest cooldown, so it never ticks inside one.
        if probeWasRateLimited, state == .running {
            scheduleTimer(interval: config.failureBackoffInterval)
        } else {
            rescheduleForCurrentState()
        }

        print("PollingManager: Rate limited - cooldown for \(String(format: "%.0f", cooldown))s")
    }

    /// Check if data is stale enough to warrant a new request
    func isDataStale(lastUpdateTime: Date?) -> Bool {
        guard let lastUpdate = lastUpdateTime else { return true }
        return Date().timeIntervalSince(lastUpdate) > Constants.RateLimit.stalenessThreshold
    }

    // MARK: - Private Methods

    /// Polling interval for the current usage. The user's setting is the ceiling: adaptive
    /// polling only speeds up as a limit gets close, it never polls slower than chosen.
    func calculateInterval(for usage: Double) -> TimeInterval {
        if usage >= config.criticalUsageThreshold {
            // Critical: poll at the fastest allowed rate
            return config.minInterval
        } else if usage >= config.highUsageThreshold {
            // High: halfway between the fastest rate and the chosen one
            return (config.minInterval + config.defaultInterval) / 2
        } else {
            return config.defaultInterval
        }
    }

    /// Arm the timer for whatever the 429 gate and the circuit breaker currently require.
    private func rescheduleForCurrentState() {
        guard state == .running else { return }
        if let cooldownUntil = rateLimitCooldownUntil, cooldownUntil > Date() {
            scheduleTimer(
                interval: config.failureBackoffInterval,
                firstFireIn: cooldownUntil.timeIntervalSinceNow
            )
        } else if isInFailureBackoff {
            scheduleTimer(interval: config.failureBackoffInterval)
        } else {
            scheduleTimer(interval: calculateInterval(for: lastUsage))
        }
    }

    /// - Parameter firstFireIn: Delay before the first tick; defaults to `interval`.
    private func scheduleTimer(interval: TimeInterval, firstFireIn: TimeInterval? = nil) {
        timer?.invalidate()
        currentInterval = interval

        let timer = Timer(
            fire: Date().addingTimeInterval(firstFireIn ?? interval),
            interval: interval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard self.canMakeRequest(reason: "timer") else { return }
                // performRefresh handles its own beginFetch/endFetch guard
                await self.onTick?()
            }
        }
        // Common modes keep the timer firing while a menu or the popover is tracking.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}

// MARK: - Convenience
extension PollingManager {
    var isRunning: Bool {
        return state == .running
    }
}

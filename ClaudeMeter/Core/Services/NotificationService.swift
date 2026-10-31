//
//  NotificationService.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation
import UserNotifications

// MARK: - Notification Types
enum NotificationType: String, CaseIterable {
    case warning75 = "warning_75"
    case warning90 = "warning_90"
    case critical95 = "critical_95"
    case limitReset = "limit_reset"

    var title: String {
        switch self {
        case .warning75: return "Usage Warning"
        case .warning90: return "High Usage Alert"
        case .critical95: return "Critical Usage"
        case .limitReset: return "Usage Reset"
        }
    }

    var threshold: Int? {
        switch self {
        case .warning75: return 75
        case .warning90: return 90
        case .critical95: return 95
        case .limitReset: return nil
        }
    }

    static func forThreshold(_ threshold: Int) -> NotificationType? {
        switch threshold {
        case 75: return .warning75
        case 90: return .warning90
        case 95: return .critical95
        default: return nil
        }
    }
}

// MARK: - Notification Service
class NotificationService: NotificationServiceProtocol {
    static let shared = NotificationService()

    private var notifiedThresholds: Set<String> = []  // "5h_75", "7d_90", etc.

    // Hysteresis buffer: usage must drop this much below threshold before re-notifying
    private let hysteresisBuffer: Double = Constants.Notification.hysteresisBuffer

    private let defaults: UserDefaults
    private let deliver: (UNNotificationRequest) -> Void

    private convenience init() {
        self.init(defaults: .standard) { request in
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("NotificationService: Failed to schedule notification - \(error)")
                }
            }
        }
    }

    /// Tests supply isolated defaults and capture requests instead of posting them.
    init(defaults: UserDefaults, deliver: @escaping (UNNotificationRequest) -> Void) {
        self.defaults = defaults
        self.deliver = deliver
        loadNotificationState()
    }

    // MARK: - Permission

    func requestPermission() async -> Bool {
        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            print("NotificationService: Permission request failed - \(error)")
            return false
        }
    }

    func checkPermissionStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    // MARK: - Basic Notification

    func scheduleNotification(title: String, body: String, identifier: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let id = identifier ?? UUID().uuidString
        deliver(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // MARK: - Usage-Based Notifications

    /// Check usage and send notifications based on thresholds
    /// Uses aggregated notifications to avoid spam
    /// - Parameters:
    ///   - usage: Current usage data
    ///   - previousUsage: Previous usage data for comparison
    ///   - thresholds: Enabled threshold values (e.g., [75, 90, 95])
    func checkAndNotify(usage: UsageData, previousUsage: UsageData?, thresholds: [Int]) {
        // Collect crossed thresholds for aggregated notification
        var crossedThresholds: [(windowTitle: String, threshold: Int, usage: Double)] = []

        // One loop over displayWindows instead of a block per window: whatever the API
        // adds next (a new scoped model limit, a new surface) is notified automatically.
        let previousWindows = previousUsage?.displayWindows
        for window in usage.displayWindows {
            let previous = previousWindows?.first { $0.id == window.id }?.usage

            // A window that appears out of nowhere BETWEEN two polls is almost always an
            // existing limit under a new id — the server renamed the scope, started sending
            // a scope id, or reordered unnamed entries. Treating its absence as 0% would
            // re-fire every threshold the user has already been told about, so its state is
            // seeded silently instead. A cold start (no previous response at all) still
            // notifies, which is the long-standing behaviour for the 5h/7d windows.
            //
            // The emptiness check matters: a single malformed response yields no windows at
            // all, and treating that as "everything was renamed" would seed — and therefore
            // swallow — the next real threshold crossing.
            let appearedSinceLastPoll = previousWindows?.isEmpty == false && previous == nil

            let crossed = checkThresholdsAggregated(
                currentUsage: window.usage,
                windowName: window.id,
                windowTitle: window.notificationName,
                thresholds: thresholds,
                seedOnly: appearedSinceLastPoll
            )
            crossedThresholds.append(contentsOf: crossed)
        }

        // Send aggregated notification if any thresholds were crossed
        if !crossedThresholds.isEmpty {
            sendAggregatedNotification(crossedThresholds: crossedThresholds)
        }

        // Check for limit resets (usage went from high to low)
        checkForReset(current: usage, previous: previousUsage)
    }

    /// Check thresholds and return crossed ones for aggregation.
    ///
    /// Level-based against the persisted `notifiedThresholds`, not edge-based against the
    /// previous poll: a threshold is due whenever usage is at or above it and it has not been
    /// notified since usage last fell below it. Edge detection lost alerts for good - a
    /// crossing that couldn't be delivered on the poll it happened (the old per-type hourly
    /// throttle, e.g. a scoped limit reaching 75% within an hour of the 5-hour window) was
    /// never "crossed" again, because the next poll's previous value was already above it.
    /// The per-key state plus hysteresis is what keeps this from repeating.
    /// - Parameter seedOnly: Record the thresholds this limit is already above without
    ///   notifying. Used when a limit shows up under an id we have never seen, so the
    ///   user is not told again about a threshold they already crossed.
    private func checkThresholdsAggregated(
        currentUsage: Double,
        windowName: String,
        windowTitle: String,
        thresholds: [Int],
        seedOnly: Bool = false
    ) -> [(windowTitle: String, threshold: Int, usage: Double)] {
        var crossed: [(windowTitle: String, threshold: Int, usage: Double)] = []
        var stateChanged = false
        let sortedThresholds = thresholds.sorted()

        for threshold in sortedThresholds {
            let key = "\(windowName)_\(threshold)"

            if seedOnly {
                // Adopt the current position silently; the next genuine crossing notifies.
                if currentUsage >= Double(threshold) {
                    stateChanged = notifiedThresholds.insert(key).inserted || stateChanged
                }
            } else if currentUsage >= Double(threshold),
                      !notifiedThresholds.contains(key),
                      NotificationType.forThreshold(threshold) != nil {
                crossed.append((windowTitle: windowTitle, threshold: threshold, usage: currentUsage))
                notifiedThresholds.insert(key)
                stateChanged = true
            }

            // Reset notification flag if usage dropped below threshold (with hysteresis)
            if currentUsage < Double(threshold) - hysteresisBuffer {
                stateChanged = notifiedThresholds.remove(key) != nil || stateChanged
            }
        }

        if stateChanged {
            saveNotificationState()
        }

        // A jump past several thresholds in one poll (a cold start at 96%, or a big job)
        // marks them all notified, but reports the window once, at its highest threshold.
        // Returning every crossing printed the same "Current Session: 96%" three times.
        return crossed.max { $0.threshold < $1.threshold }.map { [$0] } ?? []
    }

    /// Send a single aggregated notification for all crossed thresholds
    private func sendAggregatedNotification(crossedThresholds: [(windowTitle: String, threshold: Int, usage: Double)]) {
        // Find the highest threshold crossed to determine notification type
        let maxThreshold = crossedThresholds.map { $0.threshold }.max() ?? 75
        guard let notificationType = NotificationType.forThreshold(maxThreshold) else { return }

        // Build aggregated body
        let usageDescriptions = crossedThresholds.map { "\($0.windowTitle): \(Int($0.usage))%" }
        let body = usageDescriptions.joined(separator: ", ")

        scheduleNotification(
            title: notificationType.title,
            body: body,
            identifier: "aggregated_\(maxThreshold)"
        )
        // No per-type throttle: threshold alerts are deduplicated by the per-window
        // `notifiedThresholds` state, and throttling by type lost them.
    }

    private func checkForReset(current: UsageData, previous: UsageData?) {
        guard let previous = previous else { return }

        var resetWindows: [String] = []
        let now = Date()

        // Driven by displayWindows so every limit — including newly introduced scoped
        // ones — is covered.
        let previousWindows = previous.displayWindows
        for window in current.displayWindows {
            guard let previousWindow = previousWindows.first(where: { $0.id == window.id }),
                  Self.didReset(window, from: previousWindow, now: now) else { continue }
            resetWindows.append(window.notificationName)
            // Clear this window's persisted threshold notifications.
            notifiedThresholds = notifiedThresholds.filter { !$0.hasPrefix("\(window.id)_") }
        }

        // Note: keys for windows the server has stopped sending (sonnet_*, opus_*, design_*)
        // linger in UserDefaults. They are inert — no migration needed.

        // Send aggregated reset notification
        if !resetWindows.isEmpty {
            sendResetNotification(windowTitles: resetWindows)
            saveNotificationState()
        }
    }

    /// Whether `window` is a fresh period of `previous` worth announcing.
    ///
    /// The server's `resets_at` is authoritative: once the time we last saw has passed and the
    /// limit reports a later one (or none, before the next period starts), it rolled over —
    /// however much has been used since. Inferring a reset from a drop to under 20% missed
    /// any reset followed by real work before the next poll. Rollover detection is edge-based
    /// against the previous poll, so it fires once per period without a throttle; the old
    /// hourly per-type throttle swallowed a second limit resetting within the hour.
    private static func didReset(_ window: DisplayLimit, from previous: DisplayLimit, now: Date) -> Bool {
        if let previousReset = previous.resetsAt, previousReset <= now {
            let rolledOver = window.resetsAt.map {
                $0.timeIntervalSince(previousReset) > Constants.Notification.resetRolloverTolerance
            } ?? true
            if rolledOver {
                return previous.usage >= Constants.Notification.resetMinimumPriorUsage
            }
        }
        // Limits without `resets_at`, or reset early by the server: infer from a large drop.
        return previous.usage - window.usage > Constants.Notification.resetDropThreshold
            && window.usage < Constants.Notification.resetLowThreshold
    }

    private func sendResetNotification(windowTitles: [String]) {
        let windowList = windowTitles.joined(separator: ", ")
        let body = windowTitles.count == 1
            ? "Your \(windowList) usage has been reset. You're good to go!"
            : "Your \(windowList) usage limits have been reset. You're good to go!"

        scheduleNotification(
            title: NotificationType.limitReset.title,
            body: body,
            identifier: "reset_aggregated"
        )
    }

    // MARK: - State Persistence

    private let notificationStateKey = Constants.Notification.notificationStateKey

    private func saveNotificationState() {
        let state = Array(notifiedThresholds)
        defaults.set(state, forKey: notificationStateKey)
    }

    private func loadNotificationState() {
        if let state = defaults.array(forKey: notificationStateKey) as? [String] {
            notifiedThresholds = Set(state)
        }
    }
}

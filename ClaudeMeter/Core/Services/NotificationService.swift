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
    case credentialExpiring = "credential_expiring"

    var title: String {
        switch self {
        case .warning75: return "Usage Warning"
        case .warning90: return "High Usage Alert"
        case .critical95: return "Critical Usage"
        case .limitReset: return "Usage Reset"
        case .credentialExpiring: return "Credentials Expiring"
        }
    }

    var threshold: Int? {
        switch self {
        case .warning75: return 75
        case .warning90: return 90
        case .critical95: return 95
        case .limitReset, .credentialExpiring: return nil
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

    // Throttling: track last notification time per type
    private var lastNotificationTimes: [NotificationType: Date] = [:]
    private var notifiedThresholds: Set<String> = []  // "5h_75", "7d_90", etc.

    // Throttle interval: 1 hour between same notification types
    private let throttleInterval: TimeInterval = Constants.Notification.throttleInterval

    // Hysteresis buffer: usage must drop this much below threshold before re-notifying
    private let hysteresisBuffer: Double = Constants.Notification.hysteresisBuffer

    // Keys for persisting throttle times
    private let throttleTimesKey = Constants.Notification.throttleTimesKey

    private init() {
        loadNotificationState()
        loadThrottleTimes()
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
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("NotificationService: Failed to schedule notification - \(error)")
            }
        }
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

        // Check 5-hour usage
        if let fiveHour = usage.fiveHour {
            let crossed = checkThresholdsAggregated(
                currentUsage: fiveHour.utilization,
                previousUsage: previousUsage?.fiveHour?.utilization,
                windowName: "5h",
                windowTitle: "5-Hour",
                thresholds: thresholds
            )
            crossedThresholds.append(contentsOf: crossed)
        }

        // Check 7-day usage
        if let sevenDay = usage.sevenDay {
            let crossed = checkThresholdsAggregated(
                currentUsage: sevenDay.utilization,
                previousUsage: previousUsage?.sevenDay?.utilization,
                windowName: "7d",
                windowTitle: "7-Day",
                thresholds: thresholds
            )
            crossedThresholds.append(contentsOf: crossed)
        }

        // Check Opus usage
        if let opus = usage.sevenDayOpus {
            let crossed = checkThresholdsAggregated(
                currentUsage: opus.utilization,
                previousUsage: previousUsage?.sevenDayOpus?.utilization,
                windowName: "opus",
                windowTitle: "Opus",
                thresholds: thresholds
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

    /// Check thresholds and return crossed ones for aggregation
    private func checkThresholdsAggregated(
        currentUsage: Double,
        previousUsage: Double?,
        windowName: String,
        windowTitle: String,
        thresholds: [Int]
    ) -> [(windowTitle: String, threshold: Int, usage: Double)] {
        var crossed: [(windowTitle: String, threshold: Int, usage: Double)] = []
        let sortedThresholds = thresholds.sorted()

        for threshold in sortedThresholds {
            let key = "\(windowName)_\(threshold)"
            let previousValue = previousUsage ?? 0

            // Check if we just crossed this threshold upward
            if currentUsage >= Double(threshold) && previousValue < Double(threshold) {
                // Only notify if not already notified for this threshold
                if !notifiedThresholds.contains(key) {
                    if let notificationType = NotificationType.forThreshold(threshold),
                       shouldSendNotification(type: notificationType) {
                        crossed.append((windowTitle: windowTitle, threshold: threshold, usage: currentUsage))
                        notifiedThresholds.insert(key)
                    }
                }
            }

            // Reset notification flag if usage dropped below threshold (with hysteresis)
            if currentUsage < Double(threshold) - hysteresisBuffer {
                notifiedThresholds.remove(key)
            }
        }

        if !crossed.isEmpty {
            saveNotificationState()
        }

        return crossed
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
        recordNotification(type: notificationType)
    }

    private func checkForReset(current: UsageData, previous: UsageData?) {
        guard let previous = previous else { return }

        var resetWindows: [String] = []

        // Check 5-hour reset - gradual detection (>40% drop)
        if let currentFiveHour = current.fiveHour,
           let previousFiveHour = previous.fiveHour {
            let drop = previousFiveHour.utilization - currentFiveHour.utilization
            if drop > Constants.Notification.resetDropThreshold && currentFiveHour.utilization < Constants.Notification.resetLowThreshold {
                resetWindows.append("5-Hour")
                // Clear 5h threshold notifications
                notifiedThresholds = notifiedThresholds.filter { !$0.hasPrefix("5h_") }
            }
        }

        // Check 7-day reset (less common) - gradual detection
        if let currentSevenDay = current.sevenDay,
           let previousSevenDay = previous.sevenDay {
            let drop = previousSevenDay.utilization - currentSevenDay.utilization
            if drop > Constants.Notification.resetDropThreshold && currentSevenDay.utilization < Constants.Notification.resetLowThreshold {
                resetWindows.append("7-Day")
                notifiedThresholds = notifiedThresholds.filter { !$0.hasPrefix("7d_") }
            }
        }

        // Check Opus reset
        if let currentOpus = current.sevenDayOpus,
           let previousOpus = previous.sevenDayOpus {
            let drop = previousOpus.utilization - currentOpus.utilization
            if drop > Constants.Notification.resetDropThreshold && currentOpus.utilization < Constants.Notification.resetLowThreshold {
                resetWindows.append("Opus")
                notifiedThresholds = notifiedThresholds.filter { !$0.hasPrefix("opus_") }
            }
        }

        // Send aggregated reset notification
        if !resetWindows.isEmpty {
            sendResetNotification(windowTitles: resetWindows)
            saveNotificationState()
        }
    }

    private func sendUsageNotification(type: NotificationType, windowTitle: String, usage: Double) {
        let body: String
        switch type {
        case .warning75:
            body = "\(windowTitle) usage at \(Int(usage))%. Consider slowing down."
        case .warning90:
            body = "\(windowTitle) usage at \(Int(usage))%. You're almost at the limit."
        case .critical95:
            body = "\(windowTitle) usage at \(Int(usage))%! Limit approaching."
        default:
            body = "\(windowTitle) usage at \(Int(usage))%"
        }

        scheduleNotification(title: type.title, body: body, identifier: type.rawValue)
        recordNotification(type: type)
    }

    private func sendResetNotification(windowTitles: [String]) {
        guard shouldSendNotification(type: .limitReset), !windowTitles.isEmpty else { return }

        let windowList = windowTitles.joined(separator: ", ")
        let body = windowTitles.count == 1
            ? "Your \(windowList) usage has been reset. You're good to go!"
            : "Your \(windowList) usage limits have been reset. You're good to go!"

        scheduleNotification(
            title: NotificationType.limitReset.title,
            body: body,
            identifier: "reset_aggregated"
        )
        recordNotification(type: .limitReset)
    }

    // MARK: - Credential Notifications

    func notifyCredentialExpiring(in timeInterval: TimeInterval) {
        guard shouldSendNotification(type: .credentialExpiring) else { return }

        let minutes = Int(timeInterval / 60)
        let body = "Your Claude credentials will expire in \(minutes) minutes. Please re-authenticate."

        scheduleNotification(
            title: NotificationType.credentialExpiring.title,
            body: body,
            identifier: NotificationType.credentialExpiring.rawValue
        )
        recordNotification(type: .credentialExpiring)
    }

    // MARK: - Throttling

    private func shouldSendNotification(type: NotificationType) -> Bool {
        guard let lastTime = lastNotificationTimes[type] else {
            return true
        }
        return Date().timeIntervalSince(lastTime) >= throttleInterval
    }

    private func recordNotification(type: NotificationType) {
        lastNotificationTimes[type] = Date()
        saveThrottleTimes()
    }

    // MARK: - State Persistence

    private let notificationStateKey = Constants.Notification.notificationStateKey

    private func saveNotificationState() {
        let state = Array(notifiedThresholds)
        UserDefaults.standard.set(state, forKey: notificationStateKey)
    }

    private func loadNotificationState() {
        if let state = UserDefaults.standard.array(forKey: notificationStateKey) as? [String] {
            notifiedThresholds = Set(state)
        }
    }

    private func saveThrottleTimes() {
        // Convert NotificationType -> Date dictionary to String -> TimeInterval for storage
        var dict: [String: TimeInterval] = [:]
        for (type, date) in lastNotificationTimes {
            dict[type.rawValue] = date.timeIntervalSince1970
        }
        UserDefaults.standard.set(dict, forKey: throttleTimesKey)
    }

    private func loadThrottleTimes() {
        guard let dict = UserDefaults.standard.dictionary(forKey: throttleTimesKey) as? [String: TimeInterval] else {
            return
        }
        for (rawValue, timestamp) in dict {
            if let type = NotificationType(rawValue: rawValue) {
                lastNotificationTimes[type] = Date(timeIntervalSince1970: timestamp)
            }
        }
    }

    /// Reset all notification state (e.g., on app restart or user request)
    func resetNotificationState() {
        notifiedThresholds.removeAll()
        lastNotificationTimes.removeAll()
        saveNotificationState()
        saveThrottleTimes()
    }
}

//
//  NotificationServiceProtocol.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation
import UserNotifications

/// Protocol defining the notification service interface
protocol NotificationServiceProtocol {
    /// Request notification permission
    /// - Returns: True if permission was granted
    func requestPermission() async -> Bool

    /// Check current permission status
    /// - Returns: The authorization status
    func checkPermissionStatus() async -> UNAuthorizationStatus

    /// Schedule a notification
    /// - Parameters:
    ///   - title: Notification title
    ///   - body: Notification body
    ///   - identifier: Optional identifier for the notification
    func scheduleNotification(title: String, body: String, identifier: String?)

    /// Check usage and send notifications based on thresholds
    /// - Parameters:
    ///   - usage: Current usage data
    ///   - previousUsage: Previous usage data for comparison
    ///   - thresholds: Enabled threshold values
    func checkAndNotify(usage: UsageData, previousUsage: UsageData?, thresholds: [Int])

    /// Reset all notification state
    func resetNotificationState()
}

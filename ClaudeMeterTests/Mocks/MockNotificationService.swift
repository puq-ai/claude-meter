//
//  MockNotificationService.swift
//  ClaudeMeterTests
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation
import UserNotifications
@testable import ClaudeMeter

/// Mock notification service for testing
class MockNotificationService: NotificationServiceProtocol {
    // MARK: - Call Tracking
    var requestPermissionCallCount = 0
    var checkPermissionStatusCallCount = 0
    var scheduleNotificationCallCount = 0
    var checkAndNotifyCallCount = 0
    var resetNotificationStateCallCount = 0

    // MARK: - Captured Data
    var scheduledNotifications: [(title: String, body: String, identifier: String?)] = []
    var lastUsageData: UsageData?
    var lastPreviousUsageData: UsageData?
    var lastThresholds: [Int]?

    // MARK: - Stubbed Responses
    var stubbedPermissionGranted = true
    var stubbedAuthorizationStatus: UNAuthorizationStatus = .authorized

    // MARK: - NotificationServiceProtocol

    func requestPermission() async -> Bool {
        requestPermissionCallCount += 1
        return stubbedPermissionGranted
    }

    func checkPermissionStatus() async -> UNAuthorizationStatus {
        checkPermissionStatusCallCount += 1
        return stubbedAuthorizationStatus
    }

    func scheduleNotification(title: String, body: String, identifier: String?) {
        scheduleNotificationCallCount += 1
        scheduledNotifications.append((title: title, body: body, identifier: identifier))
    }

    func checkAndNotify(usage: UsageData, previousUsage: UsageData?, thresholds: [Int]) {
        checkAndNotifyCallCount += 1
        lastUsageData = usage
        lastPreviousUsageData = previousUsage
        lastThresholds = thresholds
    }

    func resetNotificationState() {
        resetNotificationStateCallCount += 1
        scheduledNotifications.removeAll()
    }

    // MARK: - Reset

    func reset() {
        requestPermissionCallCount = 0
        checkPermissionStatusCallCount = 0
        scheduleNotificationCallCount = 0
        checkAndNotifyCallCount = 0
        resetNotificationStateCallCount = 0
        scheduledNotifications.removeAll()
        lastUsageData = nil
        lastPreviousUsageData = nil
        lastThresholds = nil
        stubbedPermissionGranted = true
        stubbedAuthorizationStatus = .authorized
    }
}

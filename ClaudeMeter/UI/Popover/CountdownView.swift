//
//  CountdownView.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import SwiftUI
import Combine

struct CountdownView: View {
    let targetDate: Date

    @State private var timeRemaining: String = ""
    @State private var timerSubscription: AnyCancellable?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "timer")
            Text(timeRemaining)
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .onAppear {
            updateTime()
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time until reset")
        .accessibilityValue(accessibilityTimeRemaining)
    }

    private var accessibilityTimeRemaining: String {
        let diff = targetDate.timeIntervalSinceNow
        guard diff > 0 else { return "Reset complete" }

        let hours = Int(diff) / 3600
        let minutes = (Int(diff) % 3600) / 60

        if hours > 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            return "\(days) days and \(remainingHours) hours"
        } else if hours > 0 {
            return "\(hours) hours and \(minutes) minutes"
        } else {
            return "\(minutes) minutes"
        }
    }

    private func startTimer() {
        // Cancel any existing timer first
        stopTimer()

        // Create a new timer that fires every 60 seconds
        timerSubscription = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                updateTime()
            }
    }

    private func stopTimer() {
        timerSubscription?.cancel()
        timerSubscription = nil
    }

    private func updateTime() {
        let diff = targetDate.timeIntervalSinceNow
        if diff <= 0 {
            timeRemaining = "Reset"
            stopTimer() // Stop timer when countdown is complete
            return
        }

        let hours = Int(diff) / 3600
        let minutes = (Int(diff) % 3600) / 60

        if hours > 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            timeRemaining = "\(days)d \(remainingHours)h"
        } else if hours > 0 {
            timeRemaining = String(format: "%dh %02dm", hours, minutes)
        } else {
            timeRemaining = String(format: "%dm", minutes)
        }
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 20) {
        CountdownView(targetDate: Date().addingTimeInterval(3600)) // 1 hour
        CountdownView(targetDate: Date().addingTimeInterval(86400)) // 1 day
        CountdownView(targetDate: Date().addingTimeInterval(259200)) // 3 days
    }
    .padding()
}

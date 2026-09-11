//
//  StatusItemController.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Cocoa
import SwiftUI
import Combine

@MainActor
class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?

    // Progress icon configuration
    private let iconSize: CGFloat = 18

    init(appState: AppState) {
        self.appState = appState
        super.init()
        setupStatusItem()
        setupPopover()
        setupSubscriptions()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            if let image = NSImage(named: "AppLogo") {
                image.size = NSSize(width: 18, height: 18)
                button.image = image
            }
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
    }

    private func setupPopover() {
        let pop = NSPopover()
        pop.contentSize = NSSize(width: 380, height: 420)
        pop.behavior = .transient

        let popoverView = PopoverView(appState: appState)
        pop.contentViewController = NSHostingController(rootView: popoverView)
        popover = pop
    }

    private func setupSubscriptions() {
        // Update menu bar based on usage and display mode
        Publishers.CombineLatest3(appState.$usageData, appState.$settings, appState.$authState)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data, settings, authState in
                self?.updateMenuBarDisplay(with: data, mode: settings.displayMode, authState: authState)
            }
            .store(in: &cancellables)
    }

    // MARK: - Display Mode Rendering

    private func updateMenuBarDisplay(with data: UsageData?, mode: DisplayMode, authState: AuthState) {
        guard let button = statusItem?.button else { return }

        // Without data, an auth failure used to render as a green 0% - a broken app that
        // looks like a healthy one. Say so instead.
        if data == nil, authState.needsAttention {
            updateNeedsAttentionMode(button: button, mode: mode)
            return
        }

        // Use 5-hour usage for menu bar display. Read through displayWindows so the menu
        // bar keeps working off the `limits` array once the server stops sending the
        // top-level `five_hour` key, the way it already did for the per-model windows.
        let fiveHourUsage = data?.usage(forLimitId: "5h") ?? 0

        switch mode {
        case .iconOnly:
            updateIconOnlyMode(button: button, usage: fiveHourUsage)
        case .compact:
            updateCompactMode(button: button, usage: fiveHourUsage)
        case .detailed:
            updateDetailedMode(button: button, data: data)
        }
    }

    // MARK: - Needs Attention (no credentials / rejected credentials)
    private func updateNeedsAttentionMode(button: NSStatusBarButton, mode: DisplayMode) {
        let symbol = NSImage(
            systemSymbolName: "exclamationmark.triangle.fill",
            accessibilityDescription: "ClaudeMeter needs you to sign in"
        )
        symbol?.isTemplate = true

        button.image = symbol
        button.imagePosition = mode == .iconOnly ? .imageOnly : .imageLeading
        button.title = mode == .iconOnly ? "" : " --"
        button.toolTip = "ClaudeMeter can't read your usage - click to connect an account"
    }

    // MARK: - Icon Only Mode
    private func updateIconOnlyMode(button: NSStatusBarButton, usage: Double) {
        button.title = ""
        button.image = createProgressIcon(progress: usage / 100.0, color: colorForUsage(usage))
    }

    // MARK: - Compact Mode (Icon + Percentage)
    private func updateCompactMode(button: NSStatusBarButton, usage: Double) {
        button.image = createProgressIcon(progress: usage / 100.0, color: colorForUsage(usage))
        button.title = String(format: " %.0f%%", usage)
        button.imagePosition = .imageLeading
    }

    // MARK: - Detailed Mode (5h: XX% | 7d: YY%)
    private func updateDetailedMode(button: NSStatusBarButton, data: UsageData?) {
        button.image = nil

        guard let data = data else {
            button.title = "-- | --"
            return
        }

        var parts: [String] = []

        if let fiveHour = data.usage(forLimitId: "5h") {
            parts.append("5h: \(Int(fiveHour))%")
        }

        if let sevenDay = data.usage(forLimitId: "7d") {
            parts.append("7d: \(Int(sevenDay))%")
        }

        let title = parts.isEmpty ? "No data" : parts.joined(separator: " | ")

        // Apply color to the title based on max usage
        let maxUsage = calculateMaxUsage(from: data)
        let color = colorForUsage(maxUsage)

        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor(color),
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        ]

        button.attributedTitle = NSAttributedString(string: title, attributes: attributes)
    }

    // MARK: - Progress Icon Creation

    /// Creates a circular progress icon for the menu bar
    private func createProgressIcon(progress: Double, color: Color) -> NSImage {
        let size = NSSize(width: iconSize, height: iconSize)
        let image = NSImage(size: size, flipped: false) { rect in
            let context = NSGraphicsContext.current?.cgContext
            context?.clear(rect)

            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = min(rect.width, rect.height) / 2 - 2
            let lineWidth: CGFloat = 2.5

            // Background circle (gray)
            let backgroundPath = NSBezierPath()
            backgroundPath.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 0,
                endAngle: 360
            )
            NSColor.systemGray.withAlphaComponent(0.3).setStroke()
            backgroundPath.lineWidth = lineWidth
            backgroundPath.stroke()

            // Progress arc
            let clampedProgress = min(max(progress, 0), 1)
            if clampedProgress > 0 {
                let startAngle: CGFloat = 90  // Start from top
                let endAngle: CGFloat = 90 - (CGFloat(clampedProgress) * 360)

                let progressPath = NSBezierPath()
                progressPath.appendArc(
                    withCenter: center,
                    radius: radius,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    clockwise: true
                )
                NSColor(color).setStroke()
                progressPath.lineWidth = lineWidth
                progressPath.lineCapStyle = .round
                progressPath.stroke()
            }

            return true
        }

        image.isTemplate = false
        return image
    }

    // MARK: - Color Helpers

    /// Returns appropriate color based on usage percentage
    /// Uses ColorTheme for consistent colors across the app
    func colorForUsage(_ usage: Double) -> Color {
        return ColorTheme.colorForUsage(usage)
    }

    /// Calculate max usage from all windows
    private func calculateMaxUsage(from data: UsageData?) -> Double {
        guard let data = data else { return 0 }

        // Every limit counts, scoped ones included. Deliberately NOT filtered by
        // settings.showScopedLimits: hiding a card is a display preference and must not
        // suppress a real limit warning in the menu bar.
        return data.displayWindows.map(\.usage).max() ?? 0
    }

    // MARK: - Popover Toggle

    @objc func togglePopover(_ sender: AnyObject?) {
        guard let statusItem = statusItem,
              let popover = popover,
              let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(sender)
            removeEventMonitor()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            setupEventMonitor()

            // Only refresh if data is stale
            if appState.pollingManager.isDataStale(lastUpdateTime: appState.lastUpdateTime) {
                Task {
                    await appState.refresh(reason: "popover_open")
                }
            }
        }
    }

    // MARK: - Public Methods

    func showPopover() {
        guard let statusItem = statusItem,
              let popover = popover,
              let button = statusItem.button,
              !popover.isShown else { return }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func hidePopover() {
        guard let popover = popover, popover.isShown else { return }
        popover.performClose(nil)
        removeEventMonitor()
    }

    // MARK: - Event Monitor

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self,
                  let popover = self.popover,
                  popover.isShown else { return }

            self.hidePopover()
        }
    }

    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

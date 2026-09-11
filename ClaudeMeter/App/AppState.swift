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
    @Published var authState: AuthState = .unknown
    @Published var dataSource: DataSource?



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
    private let keychainService: KeychainServiceProtocol
    private let apiService: APIServiceProtocol

    private var cancellables = Set<AnyCancellable>()

    init(
        keychainService: KeychainServiceProtocol = KeychainService(),
        apiService: APIServiceProtocol = APIService()
    ) {
        // PHASE 1: Sync, fast initialization
        self.usageManager = UsageManager()
        self.pollingManager = PollingManager()
        self.keychainService = keychainService
        self.apiService = apiService

        // Load settings from UserDefaults
        self.settings = AppSettings.load()

        migrateWebSessionKeyIfNeeded()
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
                await self?.performRefresh()
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

        usageManager.$authState
            .receive(on: DispatchQueue.main)
            .assign(to: &$authState)

        usageManager.$dataSource
            .receive(on: DispatchQueue.main)
            .assign(to: &$dataSource)
    }

    // MARK: - Authentication

    /// Whether Claude Code CLI credentials are present right now. Read live rather than
    /// cached: the CLI writes them to the Keychain, which the file watcher cannot see.
    var hasCLICredentials: Bool {
        usageManager.hasCredentials
    }

    var isWebSessionConfigured: Bool {
        usageManager.isWebFallbackConfigured
    }

    /// Store a claude.ai session key obtained from the in-app login and refresh immediately.
    func applyWebSession(sessionKey: String, organization: WebOrganization) {
        try? keychainService.saveWebSessionKey(sessionKey)
        var updated = settings
        updated.webOrganizationId = organization.id
        updated.webOrganizationName = organization.name
        settings = updated   // one didSet, so applySettings runs once with both values
        Task { await refresh(reason: "web_login") }
    }

    /// Connect using a session key the user supplied themselves, for the cases the embedded
    /// sign-in can't serve - passkeys and some identity providers refuse to run inside an
    /// embedded web view, and that is their policy, not something this app can work around.
    ///
    /// Only the key is asked for: the organization is still resolved automatically, so this
    /// is one value to paste rather than the two the old settings screen demanded.
    func connectWebSession(sessionKey: String) async -> WebSessionConnectionResult {
        let key = Self.normalizeSessionKey(sessionKey)
        guard !key.isEmpty else {
            return .failed("Paste the value of the sessionKey cookie from claude.ai.")
        }

        do {
            let organizations = try await apiService.fetchOrganizations(sessionKey: key)
            guard let organization = organizations.preferredForUsage else {
                return .noOrganizations
            }
            applyWebSession(sessionKey: key, organization: organization)
            return .connected(organization)
        } catch APIError.unauthorized {
            return .failed("That session key was rejected. Copy it again - it may have expired.")
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Accepts either the bare value or a copied `sessionKey=...` pair, since both are easy
    /// things to end up with on the clipboard.
    private static func normalizeSessionKey(_ raw: String) -> String {
        var key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = key.range(of: "\(Constants.API.sessionCookieName)=") {
            key = String(key[range.upperBound...])
        }
        return key.split(separator: ";").first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? key
    }

    /// Forget the claude.ai session.
    func signOutOfWebSession() {
        try? keychainService.deleteWebSessionKey()
        var updated = settings
        updated.webOrganizationId = ""
        updated.webOrganizationName = ""
        settings = updated
    }

    // MARK: - Settings Management

    private func loadSettings() {
        settings = AppSettings.load()
    }

    private func saveSettings() {
        settings.save()
    }

    /// Move a session key left in UserDefaults by an earlier version into the Keychain.
    /// Clearing it here also rewrites the settings blob without it, so the plaintext copy
    /// does not linger on disk.
    private func migrateWebSessionKeyIfNeeded() {
        guard let legacy = settings.legacyWebSessionKey, !legacy.isEmpty else { return }
        do {
            try keychainService.saveWebSessionKey(legacy)
            settings.legacyWebSessionKey = nil
            print("AppState: migrated web session key from UserDefaults into the Keychain")
        } catch {
            print("AppState: web session key migration failed - \(error)")
        }
    }

    private func applySettings() {
        // Apply refresh interval to polling manager
        pollingManager.setDefaultInterval(TimeInterval(settings.refreshInterval))

        // Apply web API fallback credentials. The key comes from the Keychain; only the
        // non-secret organization id lives in settings.
        usageManager.webSessionKey = keychainService.readWebSessionKey() ?? ""
        usageManager.webOrganizationId = settings.webOrganizationId
        usageManager.onSessionKeyRefreshed = { [weak self] newKey in
            try? self?.keychainService.saveWebSessionKey(newKey)
        }

        // Apply dock visibility
        if settings.showInDock {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Data Refresh

    func refresh(reason: String = "unknown") async {
        guard pollingManager.canMakeRequest(reason: reason) else { return }
        await performRefresh()
    }

    /// Internal refresh used by polling timer (timer already checks canMakeRequest)
    private func performRefresh() async {
        guard pollingManager.beginFetch() else { return }
        defer { pollingManager.endFetch() }
        await usageManager.fetchUsage()

        if usageManager.error == nil {
            lastUpdateTime = Date()
        }

        // Back off on what the PRIMARY API reported, not on what the user ended up seeing.
        // A successful fallback clears `error`, so keying off that would let a 429 pass
        // unnoticed and we'd keep spending a rate-limited request on every tick.
        if case .rateLimited(let retryAfter)? = usageManager.lastPrimaryError {
            pollingManager.recordRateLimitHit(retryAfter: retryAfter)
        } else if usageManager.error != nil {
            pollingManager.recordFailure()
        } else {
            // Data is flowing, whether the primary or the fallback served it. A primary
            // failure the fallback covered must not trip the circuit breaker, or a
            // web-only user would be throttled to the 10-minute backoff interval.
            pollingManager.recordSuccess()
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
        // Max across every window the server reports, scoped limits included.
        let maxUsage = data.displayWindows.map(\.usage).max() ?? 0

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
                await self.refresh(reason: "wake_recovery")

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
                await refresh(reason: "network_recovery")
            }
        }
    }
}

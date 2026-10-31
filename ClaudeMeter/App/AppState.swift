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



    // Previous usage for notification comparison. Only ever holds a real response: see
    // `setupBindings` for why a nil in between must not overwrite it.
    private var previousUsageData: UsageData?

    // Wake recovery
    private var wakeRetryTask: Task<Void, Never>?

    // Refresh scheduled for just after the next limit reset
    private var resetRefreshTask: Task<Void, Never>?

    /// An explicit refresh arrived while a fetch was in flight. That fetch may predate what
    /// prompted it (new credentials, a sign-in), so one more runs as soon as it finishes.
    private var refreshQueued = false

    // UI State
    @Published var isPopoverShown: Bool = false

    // Settings - Single source of truth with UserDefaults
    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            saveSettings()
            applySettings(changedFrom: oldValue)
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
        self.usageManager = UsageManager(apiService: apiService, keychainService: keychainService)
        self.pollingManager = PollingManager()
        self.keychainService = keychainService
        self.apiService = apiService

        // Load settings from UserDefaults
        self.settings = AppSettings.load()

        migrateWebSessionKeyIfNeeded()
        setupBindings()
        applySettings(changedFrom: nil)

        // The web session key lives in the Keychain, not in settings: read it once here.
        // Sign-in, sign-out and server-side rotation update it directly from then on.
        usageManager.webSessionKey = keychainService.readWebSessionKey() ?? ""
        usageManager.onSessionKeyRefreshed = { [weak self] newKey in
            try? self?.keychainService.saveWebSessionKey(newKey)
        }

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
                await self?.performRefresh(explicit: false)
            }
        }

        // Request notification permission on first launch (deferred)
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            _ = await NotificationService.shared.requestPermission()
        }
    }

    /// Synchronous on purpose: everything here is main-actor already, and a `receive(on:)`
    /// hop left AppState one step behind UsageManager, so code reading AppState right after
    /// a fetch saw the previous values.
    private func setupBindings() {
        usageManager.$usageData
            .sink { [weak self] newData in
                guard let self = self else { return }
                // Keep the last real response as the comparison baseline across a nil.
                // Stale-data invalidation after sleep publishes nil; letting that become
                // the baseline hid every limit reset that happened while the Mac slept.
                if let current = self.usageData {
                    self.previousUsageData = current
                }
                self.usageData = newData

                guard let data = newData else { return }
                self.scheduleRefreshAfterNextReset(data)

                // Cached numbers can be up to a day old: alerting or retuning the poll rate
                // on them would report a state the user may no longer be in. UsageManager
                // sets `dataSource` before `usageData`, so this read is current.
                guard self.usageManager.dataSource != .cache else { return }
                self.checkNotifications(data)
                self.updatePollingInterval(data)
            }
            .store(in: &cancellables)

        usageManager.$isLoading.assign(to: &$isLoading)
        usageManager.$error.assign(to: &$error)
        usageManager.$authState.assign(to: &$authState)
        usageManager.$dataSource.assign(to: &$dataSource)
    }

    // MARK: - Authentication

    /// Whether Claude Code CLI credentials are present right now. Read live rather than
    /// cached: the CLI writes them to the Keychain, which nothing can observe for changes.
    func hasCLICredentials() async -> Bool {
        await usageManager.hasCredentials()
    }

    var isWebSessionConfigured: Bool {
        usageManager.isWebFallbackConfigured
    }

    /// Store a claude.ai session key obtained from the in-app login and refresh immediately.
    func applyWebSession(sessionKey: String, organization: WebOrganization) {
        try? keychainService.saveWebSessionKey(sessionKey)
        usageManager.webSessionKey = sessionKey
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
        usageManager.webSessionKey = ""
        var updated = settings
        updated.webOrganizationId = ""
        updated.webOrganizationName = ""
        settings = updated
    }

    // MARK: - Settings Management

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
            // Property observers don't run during init, so persist explicitly - otherwise
            // the plaintext copy stays on disk until some unrelated setting changes.
            saveSettings()
            print("AppState: migrated web session key from UserDefaults into the Keychain")
        } catch {
            print("AppState: web session key migration failed - \(error)")
        }
    }

    /// Push settings into the managers, touching only what changed. Settings are edited
    /// field by field (the organization id is a text field), and re-applying everything on
    /// every keystroke reset the polling timer and toggled the activation policy each time.
    /// `previous == nil` applies everything, for launch.
    private func applySettings(changedFrom previous: AppSettings?) {
        if previous?.refreshInterval != settings.refreshInterval {
            pollingManager.setDefaultInterval(TimeInterval(settings.refreshInterval))
        }

        // Only the non-secret organization id lives in settings; the key is in the Keychain.
        if previous?.webOrganizationId != settings.webOrganizationId {
            usageManager.webOrganizationId = settings.webOrganizationId
        }

        if previous?.showInDock != settings.showInDock {
            NSApp.setActivationPolicy(settings.showInDock ? .regular : .accessory)
        }
    }

    // MARK: - Data Refresh

    /// An explicit refresh: a user action, a sign-in, new credentials, a limit reset,
    /// recovery after sleep or offline. Each has its own reason to want data now, so the
    /// request spacing that throttles the timer does not apply; the 429 cooldown does.
    /// Requested during a fetch, it runs once that fetch finishes instead of being dropped.
    func refresh(reason: String = "unknown") async {
        if pollingManager.isFetching {
            print("AppState: Refresh (\(reason)) queued behind the fetch in flight")
            refreshQueued = true
            return
        }
        guard pollingManager.canMakeRequest(reason: reason, enforceMinimumInterval: false) else { return }
        await performRefresh(explicit: true)
    }

    /// Timer ticks come here directly, having passed `canMakeRequest` with request spacing.
    private func performRefresh(explicit: Bool) async {
        guard pollingManager.beginFetch() else { return }
        await usageManager.fetchUsage(reloadCredentials: explicit)
        recordFetchOutcome()
        pollingManager.endFetch()

        if refreshQueued {
            refreshQueued = false
            // Its own task: the caller's task (limit-reset, wake recovery, ConnectView's
            // watcher) is often cancelled right after its fetch, which would cancel this one.
            Task { await refresh(reason: "queued") }
        }
    }

    private func recordFetchOutcome() {
        guard let error = usageManager.error else {
            lastUpdateTime = Date()
            // Data is flowing, whether the primary or the fallback served it. A primary
            // failure the fallback covered must not trip the circuit breaker, or a
            // web-only user would be throttled to the 10-minute backoff interval.
            pollingManager.recordSuccess()
            return
        }

        // A 429 from the primary gates ALL requests only when nothing else served data.
        // When the fallback covered it, UsageManager already parks the primary for the
        // Retry-After window and keeps serving from the fallback; arming the global cooldown
        // on top of that froze the fallback too, leaving the numbers stale for up to 10 min.
        if case .rateLimited(let retryAfter)? = usageManager.lastPrimaryError {
            pollingManager.recordRateLimitHit(retryAfter: retryAfter)
        } else if pollingManager.isNetworkAvailable,
                  let appError = error as? AppError,
                  appError != .networkUnavailable, appError != .cancelled {
            pollingManager.recordFailure()
        }
        // Offline failures are expected and not counted: the network returning triggers a
        // refresh of its own, and a breaker tripped meanwhile would delay it by 10 minutes.
        // A cancelled fetch says nothing about the server either.
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

    /// A limit that has just reset keeps showing its old percentage until the next poll,
    /// which can be minutes away. Poll right after the earliest upcoming reset instead, so
    /// the menu bar drops promptly and the reset notification fires on time.
    private func scheduleRefreshAfterNextReset(_ data: UsageData) {
        resetRefreshTask?.cancel()
        let now = Date()
        guard let nextReset = data.displayWindows.compactMap(\.resetsAt).filter({ $0 > now }).min() else {
            resetRefreshTask = nil
            return
        }

        let delay = nextReset.timeIntervalSince(now) + Constants.Polling.postResetRefreshDelay
        resetRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.refresh(reason: "limit_reset")
        }
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
            if !self.pollingManager.isFetching {
                self.usageManager.endStaleDataPlaceholder()
            }
            self.pollingManager.schedulePostWakeTimer()
        }
    }

    // MARK: - Network Recovery

    private func onNetworkBecameAvailable() {
        guard pollingManager.isRunning else { return }

        // Whatever is on screen was fetched before the outage, or is the cache. The breaker
        // may also be holding the timer at its 10-minute backoff: don't wait for it.
        guard usageData == nil || pollingManager.isDataStale(lastUpdateTime: lastUpdateTime) else { return }
        print("AppState: Network became available with stale data, triggering refresh")
        Task {
            await refresh(reason: "network_recovery")
        }
    }
}

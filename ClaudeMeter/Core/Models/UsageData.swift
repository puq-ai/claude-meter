//
//  UsageData.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation

// MARK: - Limit Severity

/// Server-reported severity for a limit. Decoding never throws on an unrecognized
/// value — the API introduces new severities without warning.
enum LimitSeverity: String, Codable, Equatable {
    case normal
    case warning
    case critical
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = LimitSeverity(rawValue: raw) ?? .unknown
    }
}

// MARK: - Limit Scope

/// One side of a limit's scope: `{ "display_name": "Fable", "id": null }`.
struct ScopeTarget: Codable, Equatable {
    let displayName: String?
    let id: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case id
    }

    init(displayName: String?, id: String? = nil) {
        self.displayName = displayName
        self.id = id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        id = try container.decodeIfPresent(String.self, forKey: .id)
    }
}

/// What a limit applies to. `model` is confirmed; `surface` has only ever been observed
/// as null, so its shape is an assumption.
///
/// The hand-written initializer decodes each field INDEPENDENTLY on purpose. If `surface`
/// turns out to have a different shape, a synthesized decoder would throw, which would
/// fail the whole `limits` array, which would silently drop the model limits we actually
/// came here for. Decoding separately means a surprise costs us the surface label only.
struct LimitScope: Codable, Equatable {
    let model: ScopeTarget?
    let surface: ScopeTarget?

    enum CodingKeys: String, CodingKey {
        case model
        case surface
    }

    init(model: ScopeTarget?, surface: ScopeTarget? = nil) {
        self.model = model
        self.surface = surface
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = (try? container.decodeIfPresent(ScopeTarget.self, forKey: .model)) ?? nil
        surface = (try? container.decodeIfPresent(ScopeTarget.self, forKey: .surface)) ?? nil
    }
}

// MARK: - Rate Limit Entry

/// One entry of the `limits` array — the API's current representation of every limit.
/// Replaces the old per-model `seven_day_*` keys, which the server now always returns null.
struct RateLimitEntry: Codable, Equatable {
    let group: String?        // "session" | "weekly"
    let kind: String?         // "session" | "weekly_all" | "weekly_scoped"
    let percent: Double?      // already 0-100; NOT passed through UsageWindow normalization
    let resetsAt: Date?
    let isActive: Bool?
    let severity: LimitSeverity?
    let scope: LimitScope?

    enum CodingKeys: String, CodingKey {
        case group
        case kind
        case percent
        case resetsAt = "resets_at"
        case isActive = "is_active"
        case severity
        case scope
    }

    init(
        group: String? = nil,
        kind: String? = nil,
        percent: Double? = nil,
        resetsAt: Date? = nil,
        isActive: Bool? = nil,
        severity: LimitSeverity? = nil,
        scope: LimitScope? = nil
    ) {
        self.group = group
        self.kind = kind
        self.percent = percent
        self.resetsAt = resetsAt
        self.isActive = isActive
        self.severity = severity
        self.scope = scope
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        group = try container.decodeIfPresent(String.self, forKey: .group)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        percent = try container.decodeIfPresent(Double.self, forKey: .percent)
        resetsAt = try container.decodeIfPresent(Date.self, forKey: .resetsAt)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive)
        severity = try container.decodeIfPresent(LimitSeverity.self, forKey: .severity)
        scope = (try? container.decodeIfPresent(LimitScope.self, forKey: .scope)) ?? nil
    }
}

// MARK: - Seven Day Breakdown

/// A share-of-consumption row, e.g. `{ "key": "claude_code", "display_name": "Claude Code",
/// "percent": 100 }`. NOTE: this is a share of the weekly window's consumption, NOT a
/// utilization percentage — never colour it with usage thresholds.
struct BreakdownRow: Codable, Equatable {
    let key: String?
    let displayName: String?
    let percent: Double?

    enum CodingKeys: String, CodingKey {
        case key
        case displayName = "display_name"
        case percent
    }

    init(key: String?, displayName: String?, percent: Double?) {
        self.key = key
        self.displayName = displayName
        self.percent = percent
    }
}

struct SevenDayBreakdown: Codable, Equatable {
    let asOf: Date?
    let windowStartedAt: Date?
    let rows: [BreakdownRow]?

    enum CodingKeys: String, CodingKey {
        case asOf = "as_of"
        case windowStartedAt = "window_started_at"
        case rows
    }

    init(asOf: Date? = nil, windowStartedAt: Date? = nil, rows: [BreakdownRow]? = nil) {
        self.asOf = asOf
        self.windowStartedAt = windowStartedAt
        self.rows = rows
    }

    /// Rows worth rendering — anything with a name and a non-zero share.
    var significantRows: [BreakdownRow] {
        (rows ?? []).filter { ($0.displayName?.isEmpty == false) && ($0.percent ?? 0) > 0 }
    }
}

// MARK: - Money

/// `{ "amount_minor": 1234, "currency": "USD", "exponent": 2 }` → $12.34
struct MoneyAmount: Codable, Equatable {
    let amountMinor: Double?
    let currency: String?
    let exponent: Int?

    enum CodingKeys: String, CodingKey {
        case amountMinor = "amount_minor"
        case currency
        case exponent
    }

    init(amountMinor: Double?, currency: String? = nil, exponent: Int? = 2) {
        self.amountMinor = amountMinor
        self.currency = currency
        self.exponent = exponent
    }

    /// Major-unit value, honouring the server's exponent rather than assuming cents.
    var amount: Double? {
        guard let amountMinor = amountMinor else { return nil }
        return amountMinor / pow(10.0, Double(exponent ?? 2))
    }
}

// MARK: - Spend

/// The `spend` object. Only fields whose type has actually been observed are decoded —
/// `limit`, `cap`, `balance` and `auto_reload` are always null in observed responses, so
/// guessing their type would risk failing the decode.
struct SpendInfo: Codable, Equatable {
    let enabled: Bool?
    let percent: Double?
    let severity: LimitSeverity?
    let used: MoneyAmount?
    let canPurchaseCredits: Bool?
    let canToggle: Bool?
    let disclaimer: String?

    enum CodingKeys: String, CodingKey {
        case enabled
        case percent
        case severity
        case used
        case canPurchaseCredits = "can_purchase_credits"
        case canToggle = "can_toggle"
        case disclaimer
    }

    init(
        enabled: Bool? = nil,
        percent: Double? = nil,
        severity: LimitSeverity? = nil,
        used: MoneyAmount? = nil,
        canPurchaseCredits: Bool? = nil,
        canToggle: Bool? = nil,
        disclaimer: String? = nil
    ) {
        self.enabled = enabled
        self.percent = percent
        self.severity = severity
        self.used = used
        self.canPurchaseCredits = canPurchaseCredits
        self.canToggle = canToggle
        self.disclaimer = disclaimer
    }
}

// MARK: - Usage Data

struct UsageData: Codable, Equatable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let sevenDayOpus: UsageWindow?
    let sevenDaySonnet: UsageWindow?
    let sevenDayOauthApps: UsageWindow?
    let sevenDayCowork: UsageWindow?
    let sevenDayDesign: UsageWindow?
    /// Current schema. When present this is the source of truth for every displayed limit;
    /// the `seven_day_*` fields above are the legacy fallback (see `displayWindows`).
    let limits: [RateLimitEntry]?
    let sevenDayBreakdown: SevenDayBreakdown?
    let spend: SpendInfo?
    let extraUsage: ExtraUsage?
    let fetchedAt: Date

    // CodingKeys for snake_case API response mapping
    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        // Legacy per-model keys. The server has returned null for all of these since the
        // `limits` array landed; kept for the claude.ai web fallback and older responses.
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOauthApps = "seven_day_oauth_apps"
        case sevenDayCowork = "seven_day_cowork"
        // Claude Design — server returns the internal codename for now
        case sevenDayDesign = "seven_day_omelette"
        case limits
        case sevenDayBreakdown = "seven_day_breakdown"
        case spend
        case extraUsage = "extra_usage"
        case fetchedAt = "fetched_at"
    }

    // Custom initializer for creating instances programmatically
    init(
        fiveHour: UsageWindow?,
        sevenDay: UsageWindow?,
        sevenDayOpus: UsageWindow?,
        sevenDaySonnet: UsageWindow? = nil,
        sevenDayOauthApps: UsageWindow? = nil,
        sevenDayCowork: UsageWindow? = nil,
        sevenDayDesign: UsageWindow? = nil,
        limits: [RateLimitEntry]? = nil,
        sevenDayBreakdown: SevenDayBreakdown? = nil,
        spend: SpendInfo? = nil,
        extraUsage: ExtraUsage? = nil,
        fetchedAt: Date = Date()
    ) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDayOpus = sevenDayOpus
        self.sevenDaySonnet = sevenDaySonnet
        self.sevenDayOauthApps = sevenDayOauthApps
        self.sevenDayCowork = sevenDayCowork
        self.sevenDayDesign = sevenDayDesign
        self.limits = limits
        self.sevenDayBreakdown = sevenDayBreakdown
        self.spend = spend
        self.extraUsage = extraUsage
        self.fetchedAt = fetchedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fiveHour = try container.decodeIfPresent(UsageWindow.self, forKey: .fiveHour)
        sevenDay = try container.decodeIfPresent(UsageWindow.self, forKey: .sevenDay)
        sevenDayOpus = try container.decodeIfPresent(UsageWindow.self, forKey: .sevenDayOpus)
        sevenDaySonnet = try container.decodeIfPresent(UsageWindow.self, forKey: .sevenDaySonnet)
        sevenDayOauthApps = try container.decodeIfPresent(UsageWindow.self, forKey: .sevenDayOauthApps)
        sevenDayCowork = try container.decodeIfPresent(UsageWindow.self, forKey: .sevenDayCowork)
        sevenDayDesign = try container.decodeIfPresent(UsageWindow.self, forKey: .sevenDayDesign)
        // The sections below are decoded leniently. This response shape changes often, and
        // an unexpected type in a NEW field must not blank the whole UI — losing one card
        // beats losing every card. `five_hour` / `seven_day` stay strict.
        limits = (try? container.decodeIfPresent([RateLimitEntry].self, forKey: .limits)) ?? nil
        sevenDayBreakdown = (try? container.decodeIfPresent(SevenDayBreakdown.self, forKey: .sevenDayBreakdown)) ?? nil
        spend = (try? container.decodeIfPresent(SpendInfo.self, forKey: .spend)) ?? nil
        extraUsage = (try? container.decodeIfPresent(ExtraUsage.self, forKey: .extraUsage)) ?? nil
        // fetchedAt may not come from API, default to now
        fetchedAt = try container.decodeIfPresent(Date.self, forKey: .fetchedAt) ?? Date()
    }
}

// MARK: - Display Limits

/// A limit ready to render. Built from `limits` when the server sends it, otherwise from
/// the legacy `seven_day_*` fields. Every consumer — popover cards, menu bar colour,
/// adaptive polling, notifications — reads this one list, so a newly introduced limit
/// shows up everywhere without another code change.
struct DisplayLimit: Identifiable, Equatable {
    /// Stable key. Also the notification threshold prefix persisted in UserDefaults,
    /// so `5h` and `7d` MUST keep their historical spelling (see `NotificationService`).
    let id: String
    let title: String
    /// Percentage 0-100, taken verbatim from the server.
    let usage: Double
    let resetsAt: Date?
    let severity: LimitSeverity?
    /// Scoped to a specific model or surface, and therefore hideable via settings.
    let isScoped: Bool
    /// The server's currently binding limit.
    let isActive: Bool

    /// Name used in notification copy. Card titles read "5-Hour Limit", but notification
    /// bodies supply their own noun ("… usage has been reset"), so the suffix is dropped
    /// to keep the wording identical to the pre-`limits` releases.
    var notificationName: String {
        guard title.hasSuffix(" Limit") else { return title }
        return String(title.dropLast(" Limit".count))
    }
}

extension UsageData {
    /// Every limit to display, in server order.
    var displayWindows: [DisplayLimit] {
        if let limits = limits, !limits.isEmpty {
            let built = limits.enumerated().compactMap { DisplayLimit(entry: $1, index: $0) }
            if !built.isEmpty { return built }
        }
        return legacyDisplayWindows
    }

    /// Usage for one limit id, or nil when the server does not report it. Lets callers that
    /// need a specific window (the menu bar's 5h/7d readout) share `displayWindows` as the
    /// single source of truth instead of reaching for the legacy fields directly.
    func usage(forLimitId id: String) -> Double? {
        displayWindows.first { $0.id == id }?.usage
    }

    /// Pre-`limits` response shape. Still reachable through the claude.ai web fallback.
    private var legacyDisplayWindows: [DisplayLimit] {
        var windows: [DisplayLimit] = []

        func append(_ window: UsageWindow?, id: String, title: String, isScoped: Bool) {
            guard let window = window else { return }
            windows.append(
                DisplayLimit(
                    id: id,
                    title: title,
                    usage: window.utilization,
                    resetsAt: window.resetsAt,
                    severity: nil,
                    isScoped: isScoped,
                    isActive: false
                )
            )
        }

        append(fiveHour, id: "5h", title: "5-Hour Limit", isScoped: false)
        append(sevenDay, id: "7d", title: "7-Day Limit", isScoped: false)
        append(sevenDayOpus, id: "opus", title: "Opus Weekly", isScoped: true)
        append(sevenDaySonnet, id: "sonnet", title: "Sonnet Weekly", isScoped: true)
        append(sevenDayDesign, id: "design", title: "Claude Design", isScoped: true)

        return windows
    }
}

extension DisplayLimit {
    /// Builds a display limit from one `limits` entry. Returns nil when there is no
    /// percentage to show.
    init?(entry: RateLimitEntry, index: Int) {
        guard let percent = entry.percent else { return nil }

        let modelName = entry.scope?.model?.displayName?.nonEmptyTrimmed
        let surfaceName = entry.scope?.surface?.displayName?.nonEmptyTrimmed
        let scopeName: String? = {
            switch (modelName, surfaceName) {
            case let (model?, surface?): return "\(model) · \(surface)"
            case let (model?, nil): return model
            case let (nil, surface?): return surface
            case (nil, nil): return nil
            }
        }()

        // `5h` and `7d` are load-bearing: persisted notification state is keyed by them.
        switch entry.kind {
        case "session":
            self.id = "5h"
            self.title = "5-Hour Limit"
        case "weekly_all":
            self.id = "7d"
            self.title = "7-Day Limit"
        default:
            let kindKey = entry.kind?.nonEmptyTrimmed ?? "limit"
            // Notification state is persisted against this id, so it must stay the same
            // from one poll to the next. The server's own scope id is preferred because it
            // survives a display-name change ("Fable" -> "Fable 5.1"); the slugged name is
            // the next best thing. The array index is the last resort: it is the only part
            // of this that a server-side reorder can change, so it is used only for entries
            // that carry no identity at all.
            let scopeKey = entry.scope?.model?.id?.nonEmptyTrimmed
                ?? entry.scope?.surface?.id?.nonEmptyTrimmed
                ?? (modelName ?? surfaceName)?.limitSlug
            self.id = "\(kindKey):\(scopeKey ?? String(index))"

            if let scopeName = scopeName {
                self.title = entry.group == "weekly" ? "\(scopeName) Weekly" : scopeName
            } else {
                // Unknown kind with no scope: show it rather than hide it.
                self.title = kindKey.humanizedLimitKind
            }
        }

        self.usage = percent
        self.resetsAt = entry.resetsAt
        self.severity = entry.severity
        self.isScoped = scopeName != nil
        self.isActive = entry.isActive ?? false
    }
}

// MARK: - String Helpers

private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// "Fable" -> "fable", "Claude Design" -> "claude_design"
    var limitSlug: String {
        let lowered = lowercased()
        let mapped = lowered.map { character -> Character in
            character.isLetter || character.isNumber ? character : "_"
        }
        return String(mapped)
    }

    /// "weekly_scoped" -> "Weekly Scoped"
    var humanizedLimitKind: String {
        split(whereSeparator: { $0 == "_" || $0 == "-" })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

// MARK: - Usage Window

struct UsageWindow: Codable, Equatable {
    let utilization: Double      // Always 0-100 percentage
    let resetsAt: Date?          // ISO 8601

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    init(utilization: Double, resetsAt: Date? = nil) {
        // Normalize: if value is in 0-1 range (exclusive of 0), treat as fraction
        self.utilization = utilization > 0 && utilization < 1.0 ? utilization * 100.0 : utilization
        self.resetsAt = resetsAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawUtilization = try container.decode(Double.self, forKey: .utilization)
        resetsAt = try container.decodeIfPresent(Date.self, forKey: .resetsAt)
        // Normalize: if value is in 0-1 range (exclusive of 0), treat as fraction
        utilization = rawUtilization > 0 && rawUtilization < 1.0 ? rawUtilization * 100.0 : rawUtilization
    }
}

// MARK: - Extra Usage

struct ExtraUsage: Codable, Equatable {
    let isEnabled: Bool
    let monthlyLimit: Double?
    let usedCredits: Double?
    let utilization: Double?
    let creditsEverEnabled: Bool?
    let userDisabled: Bool?
    let spendLimitReached: Bool?
    let currency: String?
    let disabledReason: String?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case utilization
        case creditsEverEnabled = "credits_ever_enabled"
        case userDisabled = "user_disabled"
        case spendLimitReached = "spend_limit_reached"
        case currency
        case disabledReason = "disabled_reason"
    }

    init(
        isEnabled: Bool,
        monthlyLimit: Double? = nil,
        usedCredits: Double? = nil,
        utilization: Double? = nil,
        creditsEverEnabled: Bool? = nil,
        userDisabled: Bool? = nil,
        spendLimitReached: Bool? = nil,
        currency: String? = nil,
        disabledReason: String? = nil
    ) {
        self.isEnabled = isEnabled
        self.monthlyLimit = monthlyLimit
        self.usedCredits = usedCredits
        self.utilization = utilization
        self.creditsEverEnabled = creditsEverEnabled
        self.userDisabled = userDisabled
        self.spendLimitReached = spendLimitReached
        self.currency = currency
        self.disabledReason = disabledReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        monthlyLimit = try container.decodeIfPresent(Double.self, forKey: .monthlyLimit)
        usedCredits = try container.decodeIfPresent(Double.self, forKey: .usedCredits)
        utilization = try container.decodeIfPresent(Double.self, forKey: .utilization)
        creditsEverEnabled = try container.decodeIfPresent(Bool.self, forKey: .creditsEverEnabled)
        userDisabled = try container.decodeIfPresent(Bool.self, forKey: .userDisabled)
        spendLimitReached = try container.decodeIfPresent(Bool.self, forKey: .spendLimitReached)
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
        disabledReason = try container.decodeIfPresent(String.self, forKey: .disabledReason)
    }
}

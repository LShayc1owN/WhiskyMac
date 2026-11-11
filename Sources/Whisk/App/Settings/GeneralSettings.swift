// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Combine
import Foundation
import ServiceManagement

/// The retention choices offered in Settings, mapped to the kernel's
/// time-based policy.
enum RetentionPeriodOption: String, CaseIterable, Identifiable {
    case forever
    case day
    case week
    case month

    var id: String { rawValue }

    var label: String {
        switch self {
        case .forever: localized("Forever")
        case .day: localized("24 hours")
        case .week: localized("7 days")
        case .month: localized("30 days")
        }
    }

    var maxAge: TimeInterval? {
        switch self {
        case .forever: nil
        case .day: 86_400
        case .week: 604_800
        case .month: 2_592_000
        }
    }
}

/// Former size presets, retained to load settings saved by earlier versions.
enum CardSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: localized("Small")
        case .medium: localized("Medium")
        case .large: localized("Large")
        }
    }

    /// The card's side in points, before the selection zoom.
    var side: CGFloat {
        switch self {
        case .small: 160
        case .medium: 200
        case .large: 250
        }
    }
}

/// An application whose copies are never recorded.
struct ExcludedApp: Codable, Equatable, Identifiable {
    let bundleID: String
    let name: String

    var id: String { bundleID }
}

/// History housekeeping settings, persisted and translated into the
/// kernel's RetentionPolicy.
final class GeneralSettingsStore: ObservableObject {
    /// 0 stands for unlimited.
    static let capacityChoices = [100, 250, 500, 1000, 0]
    static let cardSideRange: ClosedRange<Double> = 160...250
    static let defaultCardSide: Double = 200

    static func boundedCardSide(_ side: Double) -> Double {
        guard side.isFinite else { return defaultCardSide }
        return min(max(side, cardSideRange.lowerBound), cardSideRange.upperBound)
    }

    static func capacityLabel(_ choice: Int) -> String {
        choice == 0 ? localized("Unlimited") : localized("\(choice) items")
    }

    @Published var pinnedPresentation: PinnedPresentation {
        didSet { defaults.set(pinnedPresentation.rawValue, forKey: "pinnedPresentation") }
    }
    @Published var pinnedWindowStyle: PinnedWindowStyle {
        didSet { defaults.set(pinnedWindowStyle.rawValue, forKey: "pinnedWindowStyle") }
    }

    @Published var appFilterTrigger: AppFilterTrigger {
        didSet { defaults.set(appFilterTrigger.rawValue, forKey: "appFilterTrigger") }
    }

    @Published var copySound: CopySoundPreferences {
        didSet {
            if let data = try? JSONEncoder().encode(copySound) { defaults.set(data, forKey: "copySound") }
        }
    }

    @Published var interactions: InteractionBindings {
        didSet {
            if let data = try? JSONEncoder().encode(interactions) { defaults.set(data, forKey: "cardInteractions") }
        }
    }

    @Published var privacyInteractions: InteractionBindings {
        didSet {
            if privacyInteractions.singleClick == .edit || privacyInteractions.singleClick == .split {
                privacyInteractions.singleClick = .none
            }
            if privacyInteractions.doubleClick == .edit || privacyInteractions.doubleClick == .split {
                privacyInteractions.doubleClick = .none
            }
            if privacyInteractions.rightClick == .edit || privacyInteractions.rightClick == .split {
                privacyInteractions.rightClick = .none
            }
            if let data = try? JSONEncoder().encode(privacyInteractions) {
                defaults.set(data, forKey: "privacyCardInteractions")
            }
        }
    }

    @Published var retentionPeriod: RetentionPeriodOption {
        didSet { defaults.set(retentionPeriod.rawValue, forKey: "retentionPeriod") }
    }

    @Published var capacity: Int {
        didSet { defaults.set(capacity, forKey: "historyCapacity") }
    }

    @Published var checkForUpdates: Bool {
        didSet { defaults.set(checkForUpdates, forKey: "checkForUpdates") }
    }

    @Published var vimNavigation: Bool {
        didSet { defaults.set(vimNavigation, forKey: "vimNavigation") }
    }

    /// Whether copied links are looked up for their title and image — the
    /// one request that tells a site its address was copied.
    @Published var linkPreviews: Bool {
        didSet { defaults.set(linkPreviews, forKey: "linkPreviews") }
    }

    @Published private(set) var cardSide: Double {
        didSet { defaults.set(cardSide, forKey: "cardSide") }
    }

    @Published private(set) var previewCardSide: Double?

    var effectiveCardSide: Double { previewCardSide ?? cardSide }

    func setCardSide(_ side: Double) {
        cardSide = Self.boundedCardSide(side)
    }

    func beginCardSizePreview(_ side: Double) {
        previewCardSide = Self.boundedCardSide(side)
    }

    func saveCardSizePreview() {
        guard let previewCardSide else { return }
        setCardSide(previewCardSide)
        self.previewCardSide = nil
    }

    func cancelCardSizePreview() {
        if previewCardSide != nil { previewCardSide = nil }
    }

    @Published var excludedApps: [ExcludedApp] {
        didSet {
            do {
                defaults.set(try JSONEncoder().encode(excludedApps), forKey: "excludedApps")
            } catch {
                logger.log("excluded apps not saved — \(error)")
            }
        }
    }

    @Published var sensitiveApps: [ExcludedApp] {
        didSet {
            if let data = try? JSONEncoder().encode(sensitiveApps) { defaults.set(data, forKey: "sensitiveApps") }
        }
    }

    @Published var sensitiveRetentionMinutes: Int {
        didSet {
            let bounded = SensitiveRetention.bounded(sensitiveRetentionMinutes)
            if sensitiveRetentionMinutes != bounded { sensitiveRetentionMinutes = bounded }
            defaults.set(bounded, forKey: "sensitiveRetentionMinutes")
        }
    }

    var sensitiveBundleIDs: Set<String> { Set(sensitiveApps.map(\.bundleID)) }

    private let defaults: UserDefaults
    private let logger: any Logger

    init(defaults: UserDefaults = AppIdentity.defaults, logger: any Logger = ConsoleLogger()) {
        self.defaults = defaults
        pinnedPresentation =
            PinnedPresentation(rawValue: defaults.string(forKey: "pinnedPresentation") ?? "") ?? .separate
        pinnedWindowStyle =
            PinnedWindowStyle(rawValue: defaults.string(forKey: "pinnedWindowStyle") ?? "") ?? .mouseList
        appFilterTrigger = AppFilterTrigger(rawValue: defaults.string(forKey: "appFilterTrigger") ?? "") ?? .click
        copySound =
            defaults.data(forKey: "copySound").flatMap {
                try? JSONDecoder().decode(CopySoundPreferences.self, from: $0)
            } ?? CopySoundPreferences()
        self.logger = logger
        let normalInteractions =
            (defaults.data(forKey: "cardInteractions").flatMap {
                try? JSONDecoder().decode(InteractionBindings.self, from: $0)
            }) ?? InteractionBindings()
        interactions = normalInteractions
        let legacyPrivacy = InteractionBindings(
            singleClick: .none, doubleClick: .none, rightClick: .menu,
            hover: normalInteractions.hover, hoverDelay: normalInteractions.hoverDelay)
        var savedPrivacy =
            defaults.data(forKey: "privacyCardInteractions").flatMap {
                try? JSONDecoder().decode(InteractionBindings.self, from: $0)
            } ?? legacyPrivacy
        if savedPrivacy.singleClick == .edit || savedPrivacy.singleClick == .split { savedPrivacy.singleClick = .none }
        if savedPrivacy.doubleClick == .edit || savedPrivacy.doubleClick == .split { savedPrivacy.doubleClick = .none }
        if savedPrivacy.rightClick == .edit || savedPrivacy.rightClick == .split { savedPrivacy.rightClick = .none }
        privacyInteractions = savedPrivacy
        if defaults.data(forKey: "privacyCardInteractions") == nil,
            let data = try? JSONEncoder().encode(savedPrivacy)
        {
            defaults.set(data, forKey: "privacyCardInteractions")
        }
        retentionPeriod = RetentionPeriodOption(rawValue: defaults.string(forKey: "retentionPeriod") ?? "") ?? .forever
        capacity =
            defaults.object(forKey: "historyCapacity") == nil ? 500 : defaults.integer(forKey: "historyCapacity")
        checkForUpdates =
            defaults.object(forKey: "checkForUpdates") == nil ? false : defaults.bool(forKey: "checkForUpdates")
        vimNavigation = defaults.bool(forKey: "vimNavigation")
        linkPreviews = defaults.object(forKey: "linkPreviews") == nil ? false : defaults.bool(forKey: "linkPreviews")
        if let savedSide = defaults.object(forKey: "cardSide") as? NSNumber {
            cardSide = Self.boundedCardSide(savedSide.doubleValue)
        } else {
            let legacySize = CardSize(rawValue: defaults.string(forKey: "cardSize") ?? "")
            cardSide = legacySize.map { Double($0.side) } ?? Self.defaultCardSide
        }
        sensitiveApps =
            defaults.data(forKey: "sensitiveApps").flatMap {
                try? JSONDecoder().decode([ExcludedApp].self, from: $0)
            } ?? []
        sensitiveRetentionMinutes =
            defaults.object(forKey: "sensitiveRetentionMinutes") == nil
            ? SensitiveRetention.defaultMinutes
            : SensitiveRetention.bounded(defaults.integer(forKey: "sensitiveRetentionMinutes"))
        excludedApps = []
        if let data = defaults.data(forKey: "excludedApps") {
            do {
                excludedApps = try JSONDecoder().decode([ExcludedApp].self, from: data)
            } catch {
                logger.log("stored excluded apps unreadable — \(error); none apply")
            }
        }
    }

    var excludedBundleIDs: Set<String> {
        Set(excludedApps.map(\.bundleID))
    }

    func addSensitiveApp(_ app: ExcludedApp) {
        excludedApps.removeAll { $0.bundleID == app.bundleID }
        if !sensitiveApps.contains(where: { $0.bundleID == app.bundleID }) { sensitiveApps.append(app) }
    }

    func excludeApp(_ app: ExcludedApp) {
        sensitiveApps.removeAll { $0.bundleID == app.bundleID }
        if !excludedApps.contains(where: { $0.bundleID == app.bundleID }) { excludedApps.append(app) }
    }

    var policy: RetentionPolicy {
        RetentionPolicy(
            capacity: capacity == 0 ? .unlimited : (HistoryCapacity(capacity) ?? .standard),
            maxAge: retentionPeriod.maxAge
        )
    }
}

/// Registers the app as a login item. Only works from the installed
/// bundle — the bare debug binary reports the failure instead of crashing.
final class LoginItemManager: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var lastError: String?

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = String(
                format: localized("Launch at login needs the installed WhiskyMac.app: %@"),
                error.localizedDescription)
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}

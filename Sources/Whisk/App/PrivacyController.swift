// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Combine
import Foundation

/// Manual intent, automatic observations and effective protection are distinct.
/// Unknown is conservative while opted in. Only stable scoped-clear observations
/// may release the automatic latch; they never clear the user's manual choice.
final class PrivacyController: ObservableObject {
    @Published private(set) var isProtected: Bool
    @Published private(set) var isManuallyProtected: Bool
    @Published private(set) var automaticEnabled: Bool
    @Published private(set) var report = SharingReport(state: .unknown, reason: .checking)
    @Published private(set) var allowsSpotlight: Bool
    @Published var allowSearchWhileProtected: Bool {
        didSet {
            defaults.set(allowSearchWhileProtected, forKey: "privacyAllowSearch")
            displayPermissionsChanged?()
        }
    }
    @Published var showSourceAppsWhileProtected: Bool {
        didSet {
            defaults.set(showSourceAppsWhileProtected, forKey: "privacyShowSourceApps")
            displayPermissionsChanged?()
        }
    }
    var displayPermissionsChanged: (() -> Void)?
    var willChangeSpotlight: ((Bool) -> Void)?
    var willChangeProtection: ((Bool) -> Void)?
    var automaticSettingChanged: ((Bool) -> Void)?
    private let defaults: UserDefaults
    private let now: () -> TimeInterval
    private let schedulesTimer: Bool
    private var clearSince: TimeInterval?
    private var clearSamples = 0
    private var timer: Timer?
    static let releaseDelay: TimeInterval = 5

    init(
        defaults: UserDefaults = AppIdentity.defaults,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, schedulesTimer: Bool = true
    ) {
        self.defaults = defaults
        allowSearchWhileProtected = defaults.bool(forKey: "privacyAllowSearch")
        showSourceAppsWhileProtected = defaults.bool(forKey: "privacyShowSourceApps")
        self.now = now
        self.schedulesTimer = schedulesTimer
        isManuallyProtected = defaults.bool(forKey: "manualPrivacy")
        automaticEnabled = defaults.bool(forKey: "automaticPrivacy")
        isProtected = defaults.bool(forKey: "manualPrivacy") || defaults.bool(forKey: "automaticPrivacy")
        allowsSpotlight = defaults.bool(forKey: "manualPrivacy") && !defaults.bool(forKey: "automaticPrivacy")
    }

    deinit { timer?.invalidate() }

    func setProtected(_ protected: Bool) {
        isManuallyProtected = protected
        defaults.set(protected, forKey: "manualPrivacy")
        reconcile()
    }

    func toggle() { setProtected(!isManuallyProtected) }

    func setAutomaticEnabled(_ enabled: Bool) {
        guard enabled != automaticEnabled else { return }
        automaticEnabled = enabled
        defaults.set(enabled, forKey: "automaticPrivacy")
        report = SharingReport(state: .unknown, reason: .checking)
        clearSince = nil
        clearSamples = 0
        reconcile()
        automaticSettingChanged?(enabled)
    }

    /// Aggregate a complete sample from all enabled providers. An active
    /// source wins over failures; a failure prevents release after an active
    /// source disappears. An empty provider set is unknown, never clear.
    func receive(_ reports: [SharingReport]) {
        guard automaticEnabled else { return }
        if let active = reports.first(where: { $0.state == .active }) {
            report = active
        } else if let unknown = reports.first(where: { $0.state == .unknown }) {
            report = unknown
        } else {
            report = reports.first ?? SharingReport(state: .unknown, reason: .unavailable)
        }
        if report.state == .clearWithinCoverage {
            if clearSince == nil { clearSince = now() }
            clearSamples += 1
        } else {
            clearSince = nil
            clearSamples = 0
        }
        reconcile()
    }

    func reconcile() {
        timer?.invalidate()
        timer = nil
        let remaining = Self.releaseDelay - (now() - (clearSince ?? now()))
        let automaticProtection =
            automaticEnabled && (report.state != .clearWithinCoverage || remaining > 0 || clearSamples < 2)
        let spotlight = isManuallyProtected && !automaticProtection
        if spotlight != allowsSpotlight {
            willChangeSpotlight?(spotlight)
            allowsSpotlight = spotlight
        }
        let protected = isManuallyProtected || automaticProtection
        if protected != isProtected {
            willChangeProtection?(protected)
            isProtected = protected
        }
        if automaticEnabled, report.state == .clearWithinCoverage, remaining > 0, schedulesTimer {
            let timer = Timer(timeInterval: remaining, repeats: false) { [weak self] _ in self?.reconcile() }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    var statusText: String {
        if isManuallyProtected { return localized("Privacy Mode is on (manual)") }
        guard automaticEnabled else {
            return localized("Automatic detection is off. Use manual protection before sharing.")
        }
        switch report.state {
        case .active: return localized("Sharing toolbar detected. Content is hidden.")
        case .clearWithinCoverage:
            return isProtected
                ? localized("Waiting for a stable end. Content remains hidden.")
                : localized("No supported toolbar detected. Other sharing or recording may still be active.")
        case .unknown:
            return report.reason == .accessibilityRequired
                ? localized(
                    "Accessibility access is needed to check sharing toolbars. Content is hidden as a precaution.")
                : localized("Detection is uncertain. Content is hidden as a precaution.")
        }
    }
}

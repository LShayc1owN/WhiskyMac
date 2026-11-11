// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Testing

@testable import Whisk

@MainActor
@Suite struct SharingDetection {
    private let active = SharingReport(state: .active, reason: .toolbarPresent)
    private let clear = SharingReport(state: .clearWithinCoverage, reason: .noMatchingToolbar)
    private let unknown = SharingReport(state: .unknown, reason: .unavailable)

    @Test func app_launch_starts_in_default_mode_until_sharing_is_detected() throws {
        let sandbox = try IsolatedDefaults()
        sandbox.defaults.set(true, forKey: "manualPrivacy")
        sandbox.defaults.set(true, forKey: "automaticPrivacy")
        let appearance = AppearanceSettingsStore(defaults: sandbox.defaults)
        let privacy = PrivacyController(defaults: sandbox.defaults, schedulesTimer: false, startInDefaultMode: true)
        #expect(!privacy.isProtected)
        #expect(appearance.statusSymbolName(protected: privacy.isProtected, paused: false) == "WhiskyMac")
        #expect(!privacy.isManuallyProtected)
        #expect(privacy.automaticEnabled)
        #expect(!sandbox.defaults.bool(forKey: "manualPrivacy"))
        privacy.receive([unknown])
        #expect(!privacy.isProtected)
        privacy.receive([active])
        #expect(privacy.isProtected)
        #expect(appearance.statusSymbolName(protected: privacy.isProtected, paused: false) == "LemonSlice")
        privacy.receive([unknown])
        #expect(privacy.isProtected)
    }

    @Test func manual_intent_survives_automatic_transitions_and_restart() throws {
        let sandbox = try IsolatedDefaults()
        var time: TimeInterval = 0
        let privacy = PrivacyController(defaults: sandbox.defaults, now: { time }, schedulesTimer: false)
        #expect(!privacy.automaticEnabled)
        privacy.setProtected(true)
        privacy.setAutomaticEnabled(true)
        privacy.receive([clear])
        time = 6
        privacy.receive([clear])
        #expect(privacy.isProtected)
        #expect(privacy.isManuallyProtected)
        privacy.setAutomaticEnabled(false)
        #expect(privacy.isProtected)
        let reopened = PrivacyController(defaults: sandbox.defaults)
        #expect(reopened.isManuallyProtected)
        privacy.setProtected(false)
        #expect(!privacy.isProtected)
    }

    @Test func automatic_latch_needs_two_stable_clear_observations_and_unknown_resets_it() throws {
        let sandbox = try IsolatedDefaults()
        var time: TimeInterval = 0
        let privacy = PrivacyController(defaults: sandbox.defaults, now: { time }, schedulesTimer: false)
        privacy.setAutomaticEnabled(true)
        #expect(privacy.isProtected)
        privacy.receive([active, clear])
        #expect(privacy.report.state == .active)
        privacy.setProtected(false)
        #expect(privacy.isProtected)
        privacy.receive([clear])
        time = 10
        privacy.reconcile()
        #expect(privacy.isProtected)
        privacy.receive([unknown, clear])
        #expect(privacy.report.state == .unknown)
        privacy.receive([clear])
        time = 14
        privacy.receive([clear])
        #expect(privacy.isProtected)
        time = 15
        privacy.reconcile()
        #expect(!privacy.isProtected)
        privacy.receive([clear, active])
        #expect(privacy.isProtected)
        privacy.receive([])
        #expect(privacy.report.state == .unknown)
        #expect(privacy.isProtected)
        privacy.setAutomaticEnabled(false)
        #expect(!privacy.isProtected)
        privacy.receive([active])
        #expect(!privacy.isProtected)
        privacy.setAutomaticEnabled(false)
    }

    @Test func status_never_claims_systemwide_clear_or_confuses_automatic_with_manual() throws {
        let sandbox = try IsolatedDefaults()
        var time: TimeInterval = 0
        let privacy = PrivacyController(defaults: sandbox.defaults, now: { time }, schedulesTimer: false)
        #expect(privacy.statusText == localized("Automatic detection is off. Use manual protection before sharing."))
        privacy.setAutomaticEnabled(true)
        #expect(privacy.statusText == localized("Detection is uncertain. Content is hidden as a precaution."))
        privacy.receive([SharingReport(state: .unknown, reason: .accessibilityRequired)])
        #expect(
            privacy.statusText
                == localized(
                    "Accessibility access is needed to check sharing toolbars. Content is hidden as a precaution."))
        privacy.receive([active])
        #expect(privacy.statusText == localized("Sharing toolbar detected. Content is hidden."))
        privacy.receive([clear])
        #expect(privacy.statusText == localized("Waiting for a stable end. Content remains hidden."))
        time = 6
        privacy.receive([clear])
        #expect(
            privacy.statusText
                == localized("No supported toolbar detected. Other sharing or recording may still be active."))
        privacy.setProtected(true)
        #expect(privacy.statusText == localized("Privacy Mode is on (manual)"))
        let restored = PrivacyController(defaults: sandbox.defaults)
        #expect(restored.automaticEnabled)
        #expect(restored.isProtected)
        restored.toggle()
        #expect(!restored.isManuallyProtected)
        #expect(restored.isProtected)
    }

    @Test func protection_callback_masks_sensitive_reveal_before_effective_state_is_published() throws {
        let sandbox = try IsolatedDefaults()
        let privacy = PrivacyController(defaults: sandbox.defaults)
        let state = HistoryViewStateStore()
        state.sensitiveSession.receive(PasteboardSnapshot(payload: .text("canary"), source: nil))
        let id = try #require(state.sensitiveSession.ids.first)
        state.sensitiveSession.setPanelVisible(true)
        state.sensitiveSession.reveal(id)
        var called = false
        privacy.willChangeProtection = { protected in
            #expect(!privacy.isProtected)
            state.setPrivacy(protected)
            called = true
        }
        privacy.setAutomaticEnabled(true)
        #expect(called)
        #expect(state.sensitiveSession.revealedPayload(id) == nil)
        #expect(state.isProtected)
    }

    @Test func public_detector_only_matches_allowlisted_native_toolbar_titles() {
        #expect(PublicSharingDetector.matches(bundleID: "us.zoom.xos", title: "as_toolbar"))
        #expect(PublicSharingDetector.matches(bundleID: "us.zoom.xos", title: "Zoom Share Statusbar Window"))
        #expect(PublicSharingDetector.matches(bundleID: "com.microsoft.teams2", title: "Sharing control bar"))
        #expect(PublicSharingDetector.matches(bundleID: "com.microsoft.teams", title: "Screen sharing toolbar"))
        #expect(!PublicSharingDetector.matches(bundleID: "com.evil", title: "as_toolbar"))
        #expect(!PublicSharingDetector.matches(bundleID: "us.zoom.xos", title: "Meeting about screen sharing"))
        var reads = 0
        let noCandidates = PublicSharingDetector(
            applications: { [.init(bundleID: "com.evil", processID: 1)] },
            trusted: { false },
            readWindows: { _ in
                reads += 1; return .titles(["as_toolbar"])
            })
        #expect(noCandidates.sample() == clear)
        #expect(reads == 0)
        #expect(noCandidates.kind == .publicAPI)
    }

    @Test func denied_permission_and_failed_reads_are_unknown_but_an_active_source_still_wins() {
        let candidates: [PublicSharingDetector.Application] = [
            .init(bundleID: "us.zoom.xos", processID: 1),
            .init(bundleID: "com.microsoft.teams2", processID: 2),
        ]
        let denied = PublicSharingDetector(
            applications: { candidates }, trusted: { false },
            readWindows: { _ in
                Issue.record("Must not read AX before permission"); return .titles([])
            })
        #expect(denied.sample() == SharingReport(state: .unknown, reason: .accessibilityRequired))
        let partial = PublicSharingDetector(
            applications: { candidates }, trusted: { true },
            readWindows: { pid in
                pid == 1 ? .unavailable : .titles(["Sharing control bar"])
            })
        #expect(partial.sample() == active)
        let failed = PublicSharingDetector(
            applications: { candidates }, trusted: { true }, readWindows: { _ in .unavailable })
        #expect(failed.sample() == unknown)
        let idle = PublicSharingDetector(
            applications: { candidates }, trusted: { true }, readWindows: { _ in .titles(["ordinary window"]) })
        #expect(idle.sample() == clear)
        let tooMany = PublicSharingDetector(
            applications: { Array(repeating: candidates[0], count: 9) }, trusted: { true },
            readWindows: { _ in .titles([]) })
        #expect(tooMany.sample() == unknown)
    }
}

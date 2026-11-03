// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Testing

@testable import Whisk

/// A controlled IPC substitute. Counts are protected because sampling is on
/// the monitor's utility worker; the actual desktop is never inspected.
private final class ControlledSharingDetector: SharingDetector {
    let kind = SharingDetectorKind.publicAPI
    let gate = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var count = 0
    var result = SharingReport(state: .clearWithinCoverage, reason: .noMatchingToolbar)
    var waits = false

    var calls: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func sample() -> SharingReport {
        lock.lock()
        count += 1
        let shouldWait = waits
        let value = result
        lock.unlock()
        if shouldWait { gate.wait() }
        return value
    }
}

@MainActor
@Suite struct SharingMonitorLifecycle {
    private func eventually(_ predicate: () -> Bool) async throws {
        // Full-suite offscreen rendering can occupy the main actor for several
        // seconds. This is an eventual lifecycle assertion, not a latency benchmark.
        let deadline = ProcessInfo.processInfo.systemUptime + 15
        while !predicate(), ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(predicate())
    }

    @Test func events_coalesce_while_ipc_is_running_and_stop_rejects_old_results() async throws {
        let detector = ControlledSharingDetector()
        detector.waits = true
        defer { for _ in 0..<4 { detector.gate.signal() } }
        let center = NotificationCenter()
        var reports: [SharingReport] = []
        var monitor: SharingMonitor? = SharingMonitor(
            detector: detector, center: center,
            hasCandidates: { false }, interval: { _ in 60 }, deliver: { reports.append($0) })
        monitor?.start()
        monitor?.start()
        try await eventually { detector.calls == 1 }
        center.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        detector.gate.signal()
        try await eventually { detector.calls == 2 }
        #expect(reports.count == 1)
        monitor?.stop()
        detector.gate.signal()
        try await Task.sleep(for: .milliseconds(30))
        #expect(reports.count == 1)
        center.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        #expect(detector.calls == 2)
        weak var weakMonitor = monitor
        monitor = nil
        #expect(weakMonitor == nil)
    }

    @Test func sleep_suspends_events_wake_restarts_and_periodic_fallback_runs() async throws {
        let detector = ControlledSharingDetector()
        let center = NotificationCenter()
        var reports: [SharingReport] = []
        let monitor = SharingMonitor(
            detector: detector, center: center, hasCandidates: { true },
            interval: { _ in 0.02 }, deliver: { reports.append($0) })
        monitor.start()
        try await eventually { reports.count >= 2 }
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        #expect(reports.last?.state == .unknown)
        let count = detector.calls
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        try await Task.sleep(for: .milliseconds(40))
        #expect(detector.calls == count)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await eventually { detector.calls > count }
        center.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        #expect(reports.last?.state == .unknown)
        center.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        try await eventually { reports.last?.state == .clearWithinCoverage }
        monitor.stop()
    }

    @Test func restart_during_a_sample_discards_old_generation_and_resamples() async throws {
        let detector = ControlledSharingDetector()
        detector.waits = true
        defer { for _ in 0..<4 { detector.gate.signal() } }
        var reports: [SharingReport] = []
        let monitor = SharingMonitor(
            detector: detector, center: NotificationCenter(),
            hasCandidates: { false }, interval: { _ in 60 }, deliver: { reports.append($0) })
        monitor.start()
        try await eventually { detector.calls == 1 }
        monitor.stop()
        monitor.start()
        detector.gate.signal()
        try await eventually { detector.calls == 2 }
        #expect(reports.isEmpty)
        detector.gate.signal()
        try await eventually { reports.count == 1 }
        monitor.stop()
    }

    @Test func real_timers_release_stable_automatic_latch_and_expire_sensitive_lease() async throws {
        let sandbox = try IsolatedDefaults()
        var time: TimeInterval = 0
        let privacy = PrivacyController(defaults: sandbox.defaults, now: { time })
        privacy.setAutomaticEnabled(true)
        let clear = SharingReport(state: .clearWithinCoverage, reason: .noMatchingToolbar)
        privacy.receive([clear])
        time = 4.99
        privacy.receive([clear])
        time = 6
        try await eventually { !privacy.isProtected }
        let session = SensitiveSessionStore(now: { time })
        session.setPanelVisible(true)
        session.receive(PasteboardSnapshot(payload: .text("synthetic"), source: nil))
        let id = try #require(session.ids.first)
        session.reveal(id)
        time = 15.99
        session.sweep()
        time = 17
        try await eventually { session.revealedID == nil }
        time = 125.99
        session.sweep()
        time = 127
        try await eventually { session.ids.isEmpty }
    }
}

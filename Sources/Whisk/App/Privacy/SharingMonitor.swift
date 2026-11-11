// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit

/// Main-thread lifecycle; AX IPC stays on one bounded worker. At most one sample
/// is in flight, event bursts coalesce, and generation rejects stopped results.
final class SharingMonitor {
    private let detector: any SharingDetector
    private let center: NotificationCenter
    private let hasCandidates: () -> Bool
    private let interval: (Bool) -> TimeInterval
    private let deliver: (SharingReport) -> Void
    private let queue = DispatchQueue(label: "dev.whisky.maclx.sharing", qos: .utility)
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var generation = 0
    private var enabled = false
    private var sleeping = false
    private var busy = false
    private var pending = false

    init(
        detector: any SharingDetector = PublicSharingDetector(),
        center: NotificationCenter = NSWorkspace.shared.notificationCenter,
        hasCandidates: @escaping () -> Bool = {
            NSWorkspace.shared.runningApplications.contains {
                PublicSharingDetector.supportedBundleIDs.contains($0.bundleIdentifier ?? "")
            }
        }, interval: @escaping (Bool) -> TimeInterval = { $0 ? 3 : 15 },
        deliver: @escaping (SharingReport) -> Void
    ) {
        self.detector = detector
        self.center = center
        self.hasCandidates = hasCandidates
        self.interval = interval
        self.deliver = deliver
    }

    deinit { stop() }

    func start() {
        guard !enabled else { return }
        enabled = true
        sleeping = false
        for name in [
            NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
        ] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.requestSample()
                })
        }
        for name in [
            NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.sleeping = false
                    self?.requestSample()
                })
        }
        for name in [
            NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    guard let self else { return }
                    self.sleeping = true
                    self.generation += 1
                    self.timer?.invalidate()
                    self.deliver(SharingReport(state: .unknown, reason: .unavailable))
                })
        }
        requestSample()
    }

    func stop() {
        enabled = false
        generation += 1
        pending = false
        timer?.invalidate()
        timer = nil
        observers.forEach { center.removeObserver($0) }
        observers = []
    }

    func requestSample() {
        guard enabled, !sleeping else { return }
        timer?.invalidate()
        if busy { pending = true; return }
        busy = true
        let token = generation
        let detector = detector
        queue.async { [weak self] in
            let result = autoreleasepool { detector.sample() }
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                guard self.enabled, !self.sleeping, self.generation == token else {
                    if self.enabled, !self.sleeping { self.requestSample() }
                    return
                }
                self.deliver(result)
                if self.pending {
                    self.pending = false
                    self.requestSample()
                } else {
                    // No AX IPC without candidates; workspace events wake us
                    // promptly. Three seconds is a measured-test parameter,
                    // not a guarantee that the first shared frame is hidden.
                    let hasCandidate = self.hasCandidates()
                    let timer = Timer(timeInterval: self.interval(hasCandidate), repeats: false) { [weak self] _ in
                        self?.requestSample()
                    }
                    timer.tolerance = hasCandidate ? 0.3 : 2
                    self.timer = timer
                    RunLoop.main.add(timer, forMode: .common)
                }
            }
        }
    }
}

// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Combine
import Foundation

/// A short-lived, bounded session. No HistoryStore, logger, decoder or preview
/// cache is reachable from here. Releasing Swift values is not secure erasure
/// and cannot prevent OS swap or copies made by another application.
final class SensitiveSessionStore: ObservableObject {
    @Published private(set) var ids: [UUID] = []
    @Published private(set) var revealedID: UUID?
    @Published private(set) var isProtected = false
    private struct Entry {
        let id: UUID
        let payload: Payload
        let rtf: Data?
        let capturedAt: TimeInterval
        var expires: TimeInterval
        let bytes: Int
    }
    private var entries: [Entry] = []
    private var revealUntil: TimeInterval?
    private var panelVisible = false
    private var timer: Timer?
    private let now: () -> TimeInterval
    private let schedulesTimer: Bool
    private(set) var retentionMinutes = SensitiveRetention.defaultMinutes
    static let revealDuration: TimeInterval = 10
    static let maximumBytes = 16 * 1024 * 1024
    var copyToPasteboard: ((Payload, Data?) -> Void)?

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, schedulesTimer: Bool = true) {
        self.now = now
        self.schedulesTimer = schedulesTimer
    }

    deinit { timer?.invalidate() }

    /// Shortening retention applies to existing entries. Lengthening it only
    /// affects future captures, never postponing a previously promised expiry.
    func setRetention(minutes: Int) {
        retentionMinutes = SensitiveRetention.bounded(minutes)
        for index in entries.indices {
            entries[index].expires = min(entries[index].expires, entries[index].capturedAt + lifetime)
        }
        sweep()
    }

    private var lifetime: TimeInterval { TimeInterval(retentionMinutes) * 60 }

    func receive(_ snapshot: PasteboardSnapshot) {
        sweep()
        let bytes = Self.byteCount(snapshot.payload) + (snapshot.rtf?.count ?? 0)
        guard bytes <= Self.maximumBytes else { return }
        hide()
        while entries.count >= 10 || entries.reduce(0, { $0 + $1.bytes }) + bytes > Self.maximumBytes {
            entries.removeLast()
        }
        let capturedAt = now()
        entries.insert(
            Entry(
                id: UUID(), payload: snapshot.payload, rtf: snapshot.rtf, capturedAt: capturedAt,
                expires: capturedAt + lifetime, bytes: bytes), at: 0)
        publish()
    }

    func setProtected(_ protected: Bool) {
        isProtected = protected
        hide()
    }

    func setPanelVisible(_ visible: Bool) {
        sweep()
        panelVisible = visible
        if !visible { hide() }
    }

    func reveal(_ id: UUID) {
        sweep()
        guard panelVisible, !isProtected, let entry = entries.first(where: { $0.id == id }) else { return }
        revealedID = id
        revealUntil = min(entry.expires, now() + Self.revealDuration)
        armTimer()
    }

    /// Raw data is available only during the explicit reveal lease. The view
    /// uses plain text for RTF and never invokes LinkPresentation/Quick Look.
    func revealedPayload(_ id: UUID) -> Payload? {
        guard panelVisible, !isProtected, revealedID == id, let deadline = revealUntil, deadline > now() else {
            return nil
        }
        return entries.first { $0.id == id && $0.expires > now() }?.payload
    }

    func copy(_ id: UUID) {
        sweep()
        guard revealedPayload(id) != nil, let entry = entries.first(where: { $0.id == id }) else { return }
        copyToPasteboard?(entry.payload, entry.rtf)
    }

    func hide() {
        revealedID = nil
        revealUntil = nil
        armTimer()
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        if revealedID == id { hide() }
        publish()
    }

    func clear() {
        entries = []
        hide()
        publish()
    }

    func sweep() {
        let instant = now()
        let oldCount = entries.count
        entries.removeAll { $0.expires <= instant }
        if let id = revealedID, !entries.contains(where: { $0.id == id }) {
            hide()
        } else if let deadline = revealUntil, deadline <= instant {
            hide()
        }
        if entries.count != oldCount { publish() } else { armTimer() }
    }

    private func publish() {
        ids = entries.map(\.id)
        armTimer()
    }

    private func armTimer() {
        timer?.invalidate()
        timer = nil
        guard schedulesTimer else { return }
        let deadlines = entries.map(\.expires) + [revealUntil].compactMap { $0 }
        guard let deadline = deadlines.min() else { return }
        let timer = Timer(timeInterval: max(0.01, deadline - now()), repeats: false) { [weak self] _ in
            self?.sweep()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private static func byteCount(_ payload: Payload) -> Int {
        switch payload {
        case .text(let value): value.utf8.count
        case .link(let url): url.absoluteString.utf8.count
        case .image(let data): data.count
        case .fileReferences(let paths): paths.reduce(0) { $0 + $1.utf8.count }
        }
    }
}

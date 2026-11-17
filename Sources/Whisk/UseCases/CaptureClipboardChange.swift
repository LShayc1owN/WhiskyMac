// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

/// Records a pasteboard change into the history and persists the result.
struct CaptureClipboardChange<Board: Pasteboard, Time: Clock, Store: HistoryStore> {
    private let pasteboard: Board
    private let clock: Time
    private let store: Store

    init(pasteboard: Board, clock: Time, store: Store) {
        self.pasteboard = pasteboard
        self.clock = clock
        self.store = store
    }

    /// Records a change unless its source application is excluded; an
    /// excluded change is still consumed so it is never captured later.
    func callAsFunction(
        into history: History, excluding excludedBundleIDs: Set<String> = [],
        sensitiveBundleIDs: Set<String> = [],
        retainSensitive: (PasteboardSnapshot) -> Void = { _ in },
        didRecord: () -> Void = {}, snapshot suppliedSnapshot: PasteboardSnapshot? = nil
    ) throws -> History {
        guard let snapshot = suppliedSnapshot ?? pasteboard.readIfChanged() else { return history }
        if let bundleID = snapshot.source?.bundleID, excludedBundleIDs.contains(bundleID) {
            return history
        }
        // Explicit exclusions win. Sensitive copies never enter History, storage,
        // undo, search or presenter caches, even if the session declines them.
        if let bundleID = snapshot.source?.bundleID, sensitiveBundleIDs.contains(bundleID) {
            retainSensitive(snapshot)
            return history
        }
        let outcome = history.recordingReportingChange(
            snapshot.payload, from: snapshot.source, rtf: snapshot.rtf, at: clock.now(),
            matches: store.duplicateMatcher(payload: snapshot.payload, rtf: snapshot.rtf))
        try store.save(outcome.history.items, changedContentIDs: outcome.contentChanged ? [outcome.recordedID] : [])
        didRecord()
        return History(items: try store.compact(outcome.history.items), capacity: outcome.history.capacity)
    }
}

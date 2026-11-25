import Foundation
@testable import Whisk

/// Deterministic doubles for the kernel's ports, shared by every test
/// target. Nothing here reads real time, the real pasteboard, or disk.

final class FakeClock: Clock {
    private var current: Date

    init(startingAt date: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        current = date
    }

    func now() -> Date { current }

    func advance(by seconds: TimeInterval) {
        current = current.addingTimeInterval(seconds)
    }
}

final class InMemoryHistoryStore: HistoryStore {
    var stored: [ClipboardItem] = []
    private(set) var saveCount = 0
    private(set) var lastChangedContentIDs: Set<UUID>?

    init() {}

    func load() throws -> [ClipboardItem] { stored }

    func save(_ items: [ClipboardItem], changedContentIDs: Set<UUID>?) throws {
        stored = items
        saveCount += 1
        lastChangedContentIDs = changedContentIDs
    }
}

final class FailingHistoryStore: HistoryStore {
    init() {}

    func load() throws -> [ClipboardItem] {
        throw HistoryStoreError.unreadable("failing store")
    }

    func save(_ items: [ClipboardItem], changedContentIDs: Set<UUID>?) throws {
        throw HistoryStoreError.unwritable("failing store")
    }
}

/// Loads what it was given but refuses every save — a disk that filled up
/// after launch.
final class SaveFailingHistoryStore: HistoryStore {
    var stored: [ClipboardItem] = []

    init() {}

    func load() throws -> [ClipboardItem] { stored }

    func save(_ items: [ClipboardItem], changedContentIDs: Set<UUID>?) throws {
        throw HistoryStoreError.unwritable("disk full")
    }
}

final class RecordingLogger: Logger {
    private(set) var messages: [DiagnosticEvent] = []
    private(set) var statuses: [Int?] = []

    init() {}

    func log(_ event: DiagnosticEvent, status: Int?) {
        messages.append(event)
        statuses.append(status)
    }
}

/// Most controller tests never look at the log: they get a fresh recorder
/// without naming one.
extension ClipboardController where Log == RecordingLogger {
    convenience init(
        pasteboard: Board,
        store: Store,
        clock: Time,
        retention: RetentionPolicy = .standard,
        present: @escaping (HistoryViewState) -> Void
    ) {
        self.init(
            pasteboard: pasteboard, store: store, clock: clock, retention: retention, logger: RecordingLogger(),
            present: present)
    }
}

final class ScriptedPasteboard: Pasteboard {
    var pendingSnapshots: [PasteboardSnapshot] = []
    var access: PasteboardAccess = .granted
    private(set) var written: [Payload] = []
    private(set) var writtenRTF: [Data?] = []
    private(set) var accessRequests = 0

    private var paused = false
    func setCapturePaused(_ paused: Bool) {
        if self.paused && !paused { pendingSnapshots.removeAll() }
        self.paused = paused
    }

    init() {}

    func readIfChanged() -> PasteboardSnapshot? {
        guard !paused, access == .granted else { return nil }
        return pendingSnapshots.isEmpty ? nil : pendingSnapshots.removeFirst()
    }

    func requestAccess() {
        accessRequests += 1
    }

    func write(_ payload: Payload, rtf: Data?) {
        written.append(payload)
        writtenRTF.append(rtf)
    }
}

func anItem(
    _ payload: Payload,
    from source: String? = "Tests",
    bundle: String? = nil,
    at date: Date = Date(timeIntervalSince1970: 1_700_000_000),
    pinned: Bool = false
) -> ClipboardItem {
    ClipboardItem(
        id: UUID(),
        payload: payload,
        source: SourceApp(name: source, bundleID: bundle),
        copiedAt: date,
        isPinned: pinned
    )
}

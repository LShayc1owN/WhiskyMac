import AppKit
import Foundation
import Testing

@testable import Whisk

/// Round-two memory work: presenter pruning, incremental content saves,
/// undo restoration, and the bounded icon cache. Nothing touches the real
/// pasteboard, user history or preferences.

@Suite struct PresenterPruning {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func deleted_text_entries_leave_the_cache_immediately() {
        let presenter = HistoryPresenter()
        let keep = anItem(.text("kept"), at: now)
        let gone = anItem(.text("gone"), at: now)
        _ = presenter.present(items: [keep, gone], query: "", now: now)
        #expect(presenter.cachedPreviewCount == 2)

        presenter.prune(keeping: [keep.id])
        #expect(presenter.cachedPreviewCount == 1)
        presenter.prune(keeping: [])
        #expect(presenter.cachedPreviewCount == 0)
    }

    @Test func image_payloads_never_land_in_the_preview_cache() {
        let presenter = HistoryPresenter()
        let image = anItem(.image(Data(repeating: 7, count: 64)), at: now)
        _ = presenter.present(items: [image], query: "", now: now)
        #expect(presenter.cachedPreviewCount == 0)

        presenter.prune(keeping: [])
        #expect(presenter.cachedPreviewCount == 0)
    }
}

@Suite struct IncrementalContentSaves {
    @Test func only_the_changed_content_rows_are_written() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteHistoryStore(databaseURL: directory.appendingPathComponent("history.sqlite"))
        let first = anItem(.text("first"))
        let second = anItem(.image(Data(repeating: 9, count: 32)))

        try store.save([first, second], changedContentIDs: [first.id])
        #expect(store.lastContentWriteIDs == [first.id])

        try store.save([first, second], changedContentIDs: [])
        #expect(store.lastContentWriteIDs.isEmpty)

        try store.save([first, second], changedContentIDs: nil)
        #expect(Set(store.lastContentWriteIDs) == [first.id, second.id])
    }

    @Test func capture_reports_the_recorded_id_and_a_duplicate_reports_none() throws {
        let board = ScriptedPasteboard()
        let store = InMemoryHistoryStore()
        let controller = ClipboardController(
            pasteboard: board, store: store, clock: FakeClock(), present: { _ in })
        let payload = Payload.text("hello")
        board.pendingSnapshots = [PasteboardSnapshot(payload: payload, source: nil)]
        controller.pollTick()
        let firstID = try #require(store.stored.first?.id)
        #expect(store.lastChangedContentIDs == [firstID])

        board.pendingSnapshots = [PasteboardSnapshot(payload: payload, source: nil)]
        controller.pollTick()
        #expect(store.lastChangedContentIDs == [])
        #expect(store.stored.count == 1)
    }
}

@Suite struct UndoRestoration {
    @Test func undo_reinserts_deleted_image_content_into_the_database() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("history.sqlite")
        let store = try SQLiteHistoryStore(databaseURL: databaseURL)
        let board = ScriptedPasteboard()
        var latestState: HistoryViewState?
        let controller = ClipboardController(
            pasteboard: board, store: store, clock: FakeClock(), present: { latestState = $0 })
        let bytes = Data(repeating: 42, count: 128)
        board.pendingSnapshots = [PasteboardSnapshot(payload: .image(bytes), source: nil)]
        controller.pollTick()
        let capturedID = try #require(latestState?.cards.first?.id)
        controller.delete(capturedID)
        #expect(controller.item(for: capturedID) == nil)

        #expect(controller.undo())
        let restored = try #require(controller.item(for: capturedID))
        #expect(restored.payload == .image(bytes))

        // A fresh connection sees the same content — the undo wrote the
        // blob back instead of leaving a tombstone.
        let reopened = try SQLiteHistoryStore(databaseURL: databaseURL)
        #expect(try reopened.load().contains(where: { $0.id == capturedID && $0.payload == .image(bytes) }))
    }
}

@MainActor
@Suite struct SourceAppStyleBounds {
    @Test func the_icon_cache_stops_growing_past_its_limit() {
        let queue = OperationQueue()
        queue.isSuspended = true
        let cache = SourceAppStyleCache(queue: queue, load: { _ in nil })
        defer { cache.releaseCache(); queue.isSuspended = false }
        for index in 0..<(SourceAppStyle.limit + 1) {
            _ = cache.resolve(bundleID: "whisk.tests.missing.\(index)")
        }
        #expect(cache.cachedCount <= SourceAppStyle.limit)
        #expect(cache.pendingCount <= SourceAppStyle.limit)
    }
}

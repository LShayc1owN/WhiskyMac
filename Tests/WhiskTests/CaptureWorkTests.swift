// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Testing

@testable import Whisk

@MainActor
@Suite struct CaptureWorkTests {
    private final class ImageProvider: NSObject, NSPasteboardItemDataProvider {
        private let lock = NSLock()
        private var count = 0
        var reads: Int { lock.withLock { count } }
        func pasteboard(
            _ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType
        ) {
            lock.withLock { count += 1 }
            item.setData(Data(repeating: 3, count: 1024 * 1024), forType: type)
        }
    }

    @Test func pause_never_materializes_promised_images_and_resume_skips_the_last_paused_copy() async {
        let board = NSPasteboard(name: .init("whisk-work-\(UUID())"))
        defer { board.releaseGlobally() }
        let queue = DispatchQueue(label: "whisk.tests.capture-work")
        let gateway = AppKitPasteboard(board: board, readQueue: queue)
        let store = InMemoryHistoryStore()
        let controller = ClipboardController(pasteboard: gateway, store: store, clock: FakeClock(), present: { _ in })
        func settle() async {
            await withCheckedContinuation { continuation in
                queue.async { DispatchQueue.main.async { continuation.resume() } }
            }
        }
        let provider = ImageProvider()
        controller.setPaused(true)
        for _ in 0..<8 {
            let item = NSPasteboardItem()
            item.setDataProvider(provider, forTypes: [.png])
            board.clearContents()
            #expect(board.writeObjects([item]))
            controller.pollTick()
            await settle()
        }
        #expect(provider.reads == 0)
        board.clearContents()
        board.setString("last copy while paused", forType: .string)
        controller.setPaused(false)
        controller.pollTick()
        await settle()
        #expect(store.stored.isEmpty)
        board.clearContents()
        board.setString("first after resume", forType: .string)
        controller.pollTick()
        await settle()
        #expect(store.stored.map(\.payload) == [.text("first after resume")])
    }
}

extension CaptureWorkTests {
    @Test func sparse_versions_keep_row_order_and_latest_representatives() {
        let clock = FakeClock()
        func rich(_ text: String, _ offset: Double) -> ClipboardItem {
            ClipboardItem(
                id: UUID(), payload: .text(text), source: nil, copiedAt: clock.now().addingTimeInterval(offset),
                isPinned: false, rtf: Data("format \(offset)".utf8))
        }
        let a = rich("A", 1), b = rich("B", 3), c = rich("A", 2), d = rich("B", 2), e = rich("A", 0)
        let plain = anItem(.text("A"))
        let rows = HistoryPresenter().present(
            items: [a, plain, b, c, d, e], query: "", now: clock.now(), selectedID: e.id)
        #expect(rows.cards.map(\.id) == [c.id, plain.id, b.id])
        #expect(rows.cards.map(\.variantIDs) == [[c.id, a.id, e.id], [plain.id], [b.id, d.id]])
        #expect(rows.cards.map(\.isSelected) == [true, false, false])
    }

    @Test func exact_recopy_reuses_stored_revisions_and_preserves_distinct_unicode_bytes() throws {
        let raw = Data("formatted".utf8)
        let ref = StoredBytes(key: "revision", byteCount: raw.count, read: { raw }, matches: { $0 == raw })
        let old = ClipboardItem(
            id: UUID(), payload: .text("é"), source: nil, copiedAt: .distantPast, isPinned: true, richText: .stored(ref)
        )
        let spelling = "e\u{301}"
        let next = History(items: [old]).recording(.text(spelling), from: nil, rtf: raw, at: .now)
        let current = try #require(next.items.first)
        #expect(next.items.count == 1 && current.id == old.id && current.isPinned)
        #expect(current.richText?.reference === ref)
        #expect(current.payload.transformableText?.utf8.elementsEqual(spelling.utf8) == true)
        #expect(try current.materialized().richText == .inline(raw))
    }

    @Test func a_read_queued_before_pausing_cannot_request_bytes_or_advance_the_resumed_cursor() async {
        let board = NSPasteboard(name: .init("whisk-work-\(UUID())"))
        defer { board.releaseGlobally() }
        let queue = DispatchQueue(label: "whisk.tests.queued-pause")
        let gateway = AppKitPasteboard(board: board, readQueue: queue)
        let provider = ImageProvider()
        let item = NSPasteboardItem()
        item.setDataProvider(provider, forTypes: [.png])
        board.clearContents()
        #expect(board.writeObjects([item]))
        queue.suspend()
        let stale: PasteboardSnapshot? = await withCheckedContinuation { continuation in
            gateway.readIfChangedAsync { continuation.resume(returning: $0) }
            gateway.setCapturePaused(true)
            gateway.setCapturePaused(false)
            queue.resume()
        }
        #expect(stale == nil && provider.reads == 0)
        #expect(gateway.readIfChanged() == nil)
        gateway.write(.text("our write"), rtf: nil)
        #expect(gateway.readIfChanged() == nil)
        board.clearContents()
        board.setString("after resume", forType: .string)
        #expect(gateway.readIfChanged()?.payload == .text("after resume"))
    }

    @Test func protected_links_track_history_and_policy_without_republishing_during_search() throws {
        let url = try #require(URL(string: "https://example.invalid/private"))
        let hidden = anItem(.link(url), pinned: true).withPinnedMetadata(.init(hidesContent: true))
        let duplicate = anItem(.link(url), pinned: true).withPinnedMetadata(.init(hidesContent: true))
        let board = ScriptedPasteboard()
        let store = InMemoryHistoryStore()
        store.stored = [hidden, duplicate]
        let controller = ClipboardController(pasteboard: board, store: store, clock: FakeClock(), present: { _ in })
        var notices: [Set<String>] = []
        controller.hiddenLinksChanged = { notices.append($0) }
        for query in ["p", "pr", "pri", ""] { controller.search(query) }
        controller.updatePinnedMetadata(hidden.id, value: .init())
        controller.delete(duplicate.id)
        #expect(controller.undo())
        #expect(notices == [[url.absoluteString], [], [url.absoluteString]])
        let credential = try #require(URL(string: "https://example.invalid/?token=SYNTHETIC123456789abcdefgh"))
        board.pendingSnapshots = [.init(payload: .link(credential), source: nil)]
        controller.pollTick()
        #expect(notices.last == [url.absoluteString, credential.absoluteString])
        controller.setSecretRecognition(.init(enabled: false))
        #expect(notices.last == [url.absoluteString])
    }

    @Test func retention_and_access_changes_still_apply_during_pause() {
        let clock = FakeClock()
        let board = ScriptedPasteboard()
        let disk = InMemoryHistoryStore()
        disk.stored = [anItem(.text("expires"), at: clock.now())]
        var view = HistoryViewState.empty
        let controller = ClipboardController(
            pasteboard: board, store: disk, clock: clock, retention: .init(maxAge: 10), present: { view = $0 })
        controller.setPaused(true)
        board.access = .denied
        clock.advance(by: 11)
        controller.pollTick()
        #expect(disk.stored.isEmpty && view.accessPrompt != nil)
        board.access = .granted
        controller.pollTick()
        #expect(view.accessPrompt == nil)
    }
}

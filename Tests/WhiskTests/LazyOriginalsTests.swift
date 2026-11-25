import AppKit
import Foundation
import SQLite3
import Testing

@testable import Whisk

@Suite struct LazyOriginals {
    private func database(cache: Int = 24 * 1024 * 1024) throws -> (URL, SQLiteHistoryStore) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("whisk-lazy-\(UUID().uuidString)")
        return (
            directory,
            try SQLiteHistoryStore(
                databaseURL: directory.appendingPathComponent("history.sqlite"), contentCacheBytes: cache)
        )
    }

    private func sql(_ directory: URL, _ query: String) throws {
        var db: OpaquePointer?
        try #require(sqlite3_open(directory.appendingPathComponent("history.sqlite").path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        try #require(sqlite3_exec(db, query, nil, nil, nil) == SQLITE_OK)
    }

    @Test func list_and_presenter_hold_references_without_reading_images_or_rtf() throws {
        let (directory, store) = try database()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = anItem(.image(Data(repeating: 1, count: 1024 * 1024)))
        let text = ClipboardItem(
            id: UUID(), payload: .text("formatted"), source: nil, copiedAt: .now, isPinned: false,
            rtf: Data(#"{\rtf1 formatted}"#.utf8))
        try store.save([image, text])
        let items = try store.loadList()
        guard case .storedImage = items[0].payload else { Issue.record("Image must be a disk handle"); return }
        #expect(items[1].richText?.reference != nil)
        let state = HistoryPresenter().present(items: items, query: "", now: .now)
        #expect(state.cards[1].richText?.reference != nil)
        #expect(store.contentStorage.readCount == 0)
        #expect(store.contentStorage.cachedBytes == 0)
        #expect(try items[0].payload.materialized() == image.payload)
        #expect(try items[1].richText?.read() == text.rtf)
        #expect(store.contentStorage.readCount == 2)
    }

    @Test func caches_deduplicate_reads_evict_by_bytes_and_skip_oversized_content() throws {
        let (directory, store) = try database(cache: 4096)
        defer { try? FileManager.default.removeItem(at: directory) }
        let entries = (1...3).map { anItem(.image(Data(repeating: UInt8($0), count: $0 == 3 ? 8192 : 4096))) }
        try store.save(entries)
        let items = try store.loadList()
        _ = try items[0].payload.materialized()
        _ = try items[0].payload.materialized()
        #expect(store.contentStorage.readCount == 1)
        #expect(store.contentStorage.cachedBytes == 4096)
        _ = try items[1].payload.materialized()
        #expect(store.contentStorage.cachedBytes == 4096)
        _ = try items[0].payload.materialized()
        #expect(store.contentStorage.readCount == 3)
        _ = try items[2].payload.materialized()
        #expect(store.contentStorage.cachedBytes == 4096)
        store.setContentCacheEnabled(false)
        #expect(store.contentStorage.cachedBytes == 0)
        _ = try items[0].payload.materialized()
        #expect(store.contentStorage.cachedBytes == 0)
    }

    @Test func capture_compacts_new_bytes_and_recopy_deduplicates_without_original_reads() throws {
        let (directory, store) = try database()
        defer { try? FileManager.default.removeItem(at: directory) }
        let board = ScriptedPasteboard()
        let clock = FakeClock()
        let controller = ClipboardController(pasteboard: board, store: store, clock: clock, present: { _ in })
        let bytes = Data(repeating: 3, count: 1024 * 1024)
        board.pendingSnapshots = [PasteboardSnapshot(payload: .image(bytes), source: nil)]
        controller.pollTick()
        let first = try #require(store.loadList().first)
        guard case .storedImage = controller.item(for: first.id)?.payload else {
            Issue.record("Capture retained inline data"); return
        }
        clock.advance(by: 1)
        board.pendingSnapshots = [PasteboardSnapshot(payload: .image(bytes), source: nil)]
        controller.pollTick()
        #expect(try store.loadList().map(\.id) == [first.id])
        #expect(store.contentStorage.readCount == 0)
        #expect(controller.select(first.id))
        #expect(board.written.last == .image(bytes))
        #expect(store.contentStorage.readCount == 1)
    }

    @Test func delete_clear_edit_and_undo_preserve_original_revisions_on_disk() throws {
        let (directory, store) = try database()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rich = ClipboardItem(
            id: UUID(), payload: .text("original"), source: nil, copiedAt: FakeClock().now(), isPinned: false,
            rtf: Data(#"{\rtf1\b original}"#.utf8))
        let image = anItem(.image(Data(repeating: 8, count: 8192)))
        try store.save([rich, image])
        let controller = ClipboardController(
            pasteboard: ScriptedPasteboard(), store: store, clock: FakeClock(), present: { _ in })
        controller.editRich(rich.id, text: "changed", rtf: Data(#"{\rtf1 changed}"#.utf8))
        #expect(store.contentStorage.readCount == 0)
        #expect(controller.undo())
        #expect(try controller.item(for: rich.id)?.richText?.read() == rich.rtf)
        controller.delete(image.id)
        store.releaseContentCache()
        #expect(controller.undo())
        #expect(try controller.item(for: image.id)?.payload.materialized() == image.payload)
        controller.clear()
        store.releaseContentCache()
        #expect(controller.undo())
        #expect(try store.load() == [rich, image])
        #expect(
            try SQLiteHistoryStore(databaseURL: directory.appendingPathComponent("history.sqlite")).load() == [
                rich, image,
            ])
    }

    @Test func replacing_content_under_the_same_id_keeps_old_handles_valid() throws {
        let (directory, store) = try database()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = anItem(.image(Data(repeating: 1, count: 256)))
        try store.save([original])
        let old = try #require(store.loadList().first)
        let changed = original.replacing(payload: .image(Data(repeating: 2, count: 256)))
        try store.save([changed])
        let new = try #require(store.loadList().first)
        #expect(try old.payload.materialized() == original.payload)
        #expect(try new.payload.materialized() == changed.payload)
        #expect(old.payload != new.payload)
    }

    @Test func missing_content_fails_export_without_overwriting_the_pasteboard_or_saving_loss() throws {
        let (directory, store) = try database()
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.save([anItem(.image(Data(repeating: 4, count: 64)))])
        let board = ScriptedPasteboard()
        let controller = ClipboardController(pasteboard: board, store: store, clock: FakeClock(), present: { _ in })
        let id = try #require(store.loadList().first?.id)
        try sql(directory, "DELETE FROM binary_content")
        #expect(!controller.select(id))
        #expect(board.written.isEmpty)
        #expect(throws: HistoryStoreError.self) { try store.loadList() }
    }

    @Test func legacy_schema_migrates_binary_payloads_and_split_rtf_transactionally() throws {
        let (directory, store) = try database()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = anItem(.text("source"))
        let group = SplitGroup(
            parts: [SplitPart(id: UUID(), text: "part", link: nil, rtf: Data(#"{\rtf1 part}"#.utf8))], plainText: false)
        let saved = original.withSplitGroup(group)
        try store.save([saved])
        // Emulate pre-reference blobs and pre-reference split JSON.
        try sql(directory, "UPDATE content SET rtf=X'7B5C72746631206F6C647D', rtf_ref=NULL")
        let encoded = try JSONEncoder().encode(group).map { String(format: "%02x", $0) }.joined()
        try sql(directory, "UPDATE split_groups SET data=X'\(encoded)'")
        let reopened = try SQLiteHistoryStore(databaseURL: directory.appendingPathComponent("history.sqlite"))
        let list = try #require(reopened.loadList().first)
        #expect(list.hasRichText)
        #expect(list.splitGroup?.parts.first?.richText?.reference != nil)
        #expect(try list.splitGroup?.parts.first?.richText?.read() == group.parts.first?.rtf)
        #expect(list.rtf == Data(#"{\rtf1 old}"#.utf8))
    }

    @Test func reordering_does_not_rewrite_unchanged_split_rtf_links() throws {
        let (directory, store) = try database()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = Data(#"{\rtf1 same formatting}"#.utf8)
        let parts = ["first", "second"].map { SplitPart(id: UUID(), text: $0, link: nil, rtf: bytes) }
        let group = anItem(.text("original")).withSplitGroup(SplitGroup(parts: parts, plainText: false))
        try store.save([group, anItem(.text("second item"))])
        try sql(
            directory,
            """
            CREATE TRIGGER refuse_link_rewrite BEFORE DELETE ON split_blob_links
            BEGIN SELECT RAISE(ABORT, 'unexpected split link rewrite'); END
            """)
        try store.save(Array(try store.loadList().reversed()), changedContentIDs: [])
        #expect(store.contentStorage.readCount == 0)
        #expect(try store.load().last?.splitGroup?.parts.map(\.rtf) == [bytes, bytes])
        try sql(directory, "DROP TRIGGER refuse_link_rewrite")
        try store.save([group.withSplitGroup(nil)], changedContentIDs: [])
        #expect(try store.loadList().first?.splitGroup == nil)
    }

    @Test func sparse_details_follow_the_snapshot_across_connections_and_retries() throws {
        let (directory, writer) = try database()
        defer { try? FileManager.default.removeItem(at: directory) }
        let other = try SQLiteHistoryStore(databaseURL: directory.appendingPathComponent("history.sqlite"))
        let rtf = Data(#"{\rtf1\ansi\b Keep me}"#.utf8)
        let part = SplitPart(id: UUID(), text: "Keep me", link: nil, rtf: rtf)
        let group = SplitGroup(parts: [part], plainText: false)
        let parent = anItem(.text("parent"), pinned: true)
        let child = ClipboardItem(
            id: UUID(), payload: .text("child"), source: nil, copiedAt: parent.copiedAt,
            isPinned: false, splitSourceID: parent.id)
        let tagged = parent.withPinnedMetadata(PinnedMetadata(note: "note", tags: [.red])).withSplitGroup(group)
        let keep = ClipboardItem(
            id: UUID(), payload: .text("retained"), source: nil, copiedAt: parent.copiedAt,
            isPinned: true, pinnedMetadata: PinnedMetadata(note: "retained"),
            splitGroup: group, splitSourceID: parent.id)
        let plainChild = anItem(.text("unrelated"))
        try writer.save([keep])
        try other.save([keep, tagged, child])
        let next = [plainChild, keep, parent]
        try sql(
            directory,
            "CREATE TRIGGER reject_pin_removal BEFORE DELETE ON pin_details BEGIN SELECT RAISE(ABORT,'test'); END")
        #expect(throws: HistoryStoreError.self) { try writer.save(next) }
        #expect(try other.load() == [keep, tagged, child])
        try sql(directory, "DROP TRIGGER reject_pin_removal")
        try writer.save(next)
        #expect(try other.load() == next)
        #expect(try other.load()[1].splitGroup?.parts.first?.rtf == rtf)
    }

    @Test func binary_equality_and_hashes_do_not_hydrate_payloads() throws {
        let (directory, store) = try database()
        defer { try? FileManager.default.removeItem(at: directory) }
        let full = anItem(.image(Data(repeating: 5, count: 256)))
        try store.save([full])
        let light = try #require(store.loadList().first)
        #expect(light == full)
        #expect(Set([light, full]).count == 1)
        #expect(store.contentStorage.readCount == 0)
    }

    @Test func plaintext_copy_does_not_load_original_rtf() throws {
        let (directory, store) = try database()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = ClipboardItem(
            id: UUID(), payload: .text("plain"), source: nil, copiedAt: FakeClock().now(), isPinned: false,
            rtf: Data(#"{\rtf1 plain}"#.utf8))
        try store.save([item])
        let board = ScriptedPasteboard()
        let controller = ClipboardController(pasteboard: board, store: store, clock: FakeClock(), present: { _ in })
        #expect(controller.select(item.id, plain: true))
        #expect(board.writtenRTF == [nil])
        #expect(store.contentStorage.readCount == 0)
    }
}

@Suite struct SymbolNameAvailability {
    @Test func names_are_filtered_by_os_metadata_without_creating_images() {
        let versions = ["old": "10.15", "new": "26.0", "point": "15.4"]
        #expect(SymbolCatalog.isAvailable("old", versions: versions, major: 15, minor: 0))
        #expect(!SymbolCatalog.isAvailable("new", versions: versions, major: 15, minor: 8))
        #expect(!SymbolCatalog.isAvailable("point", versions: versions, major: 15, minor: 3))
        #expect(SymbolCatalog.isAvailable("point", versions: versions, major: 15, minor: 4))
    }
}

extension LazyOriginals {
    @Test func concurrent_readers_share_one_cached_original() async throws {
        let (directory, store) = try database()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = Data(repeating: 13, count: 1024 * 1024)
        try store.save([anItem(.image(bytes))])
        let item = try #require(store.loadList().first)
        guard case .storedImage(let reference) = item.payload else { Issue.record("Missing disk reference"); return }
        let results = try await withThrowingTaskGroup(of: Data.self) { group in
            for _ in 0..<8 { group.addTask { try reference.read() } }
            var values: [Data] = []
            for try await value in group { values.append(value) }
            return values
        }
        #expect(results.count == 8 && results.allSatisfy { $0 == bytes })
        #expect(store.contentStorage.readCount == 1)
    }

    private func scalar(_ directory: URL, _ query: String) throws -> Int {
        var db: OpaquePointer?
        try #require(sqlite3_open(directory.appendingPathComponent("history.sqlite").path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        try #require(sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        try #require(sqlite3_step(statement) == SQLITE_ROW)
        return Int(sqlite3_column_int64(statement, 0))
    }

    @Test func unreferenced_revisions_are_collected_but_live_undo_handles_remain_readable() throws {
        let (directory, store) = try database()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = Data(repeating: 21, count: 1024)
        try store.save([anItem(.image(bytes))])
        var snapshot: ClipboardItem? = try #require(store.loadList().first)
        try store.save([])
        #expect(try scalar(directory, "SELECT COUNT(*) FROM binary_content") == 1)
        #expect(try snapshot?.payload.materialized() == .image(bytes))
        snapshot = nil
        try store.save([])
        #expect(try scalar(directory, "SELECT COUNT(*) FROM binary_content") == 0)
    }

    @Test func a_failed_legacy_conversion_preserves_original_bytes_and_schema_transaction() throws {
        let (directory, store) = try database()
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.save([anItem(.text("legacy"))])
        try sql(
            directory,
            """
            UPDATE content SET rtf=X'7B5C72746631206F6C647D';
            CREATE TRIGGER refuse_migration BEFORE UPDATE ON content
            BEGIN SELECT RAISE(ABORT, 'leave original intact'); END;
            """)
        #expect(throws: HistoryStoreError.self) {
            try SQLiteHistoryStore(databaseURL: directory.appendingPathComponent("history.sqlite"))
        }
        #expect(try scalar(directory, "SELECT LENGTH(rtf) FROM content") == 11)
        #expect(try scalar(directory, "SELECT COUNT(*) FROM binary_content") == 0)
        try sql(directory, "DROP TRIGGER refuse_migration")
        let reopened = try SQLiteHistoryStore(databaseURL: directory.appendingPathComponent("history.sqlite"))
        #expect(try reopened.load().first?.rtf == Data(#"{\rtf1 old}"#.utf8))
    }

    @Test func changed_inline_source_metadata_is_persisted_when_recopied() throws {
        let (directory, store) = try database()
        defer { try? FileManager.default.removeItem(at: directory) }
        let payload = Payload.text("same content")
        let old = ClipboardItem(
            id: UUID(), payload: payload, source: SourceApp(name: nil, bundleID: nil, origin: .handoffMarker),
            copiedAt: FakeClock().now(), isPinned: false)
        try store.save([old])
        let board = ScriptedPasteboard()
        let controller = ClipboardController(pasteboard: board, store: store, clock: FakeClock(), present: { _ in })
        let source = SourceApp(name: "Editor", bundleID: "test.editor")
        board.pendingSnapshots = [PasteboardSnapshot(payload: payload, source: source)]
        controller.pollTick()
        #expect(try store.load().first?.source == source)
        #expect(try store.load().first?.id == old.id)
    }
}

@MainActor
@Suite struct LazyPreviewResources {
    @Test func resized_link_image_does_not_keep_the_original_or_its_high_resolution_representation() throws {
        let store = LinkPreviewStore()
        weak var original: NSImage?
        try autoreleasepool {
            let bitmap = try #require(
                NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: 1600, pixelsHigh: 1200, bitsPerSample: 8, samplesPerPixel: 4,
                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let image = NSImage(size: NSSize(width: 400, height: 300))
            image.addRepresentation(bitmap)
            original = image
            store.store(
                LinkPreview(title: "page", host: "example.com", icon: nil, image: image),
                for: "https://example.com/photo")
        }
        #expect(original == nil)
        let resized = try #require(store.preview(for: "https://example.com/photo")?.image)
        let bitmap = try #require(resized.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(max(bitmap.width, bitmap.height) <= 640)
        store.releaseCache()
        #expect(store.cachedBytes == 0)
        #expect(store.previews.isEmpty)
    }

    @Test func panel_close_notifies_the_content_cache_and_view_tree_is_released() throws {
        let isolated = try IsolatedDefaults()
        let state = HistoryViewStateStore()
        var visibility: [Bool] = []
        state.contentCacheVisibility = { visibility.append($0) }
        let spy = PanelActionSpy()
        let controller = PanelController(
            uiFactory: MacOS15UIFactory(), stateStore: state, actions: spy.actions,
            keyBindings: KeyBindingsStore(defaults: isolated.defaults),
            vimBindings: VimBindingsStore(defaults: isolated.defaults), vimMode: { false })
        weak var host: NSView?
        autoreleasepool {
            controller.preparePresentation(pins: false, style: nil)
            let window = controller.activeWindow
            window.setFrame(NSRect(x: -10000, y: 0, width: 1000, height: 360), display: false)
            host = window.contentView
            window.orderFront(nil)
            state.setPanelVisible(true)
            controller.hide()
            #expect(visibility.last == false)
            #expect(window.contentView == nil)
        }
        let deadline = Date().addingTimeInterval(1)
        while host != nil && Date() < deadline {
            autoreleasepool { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        }
        #expect(host == nil)
    }
}

// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SQLite3
import Testing

@testable import Whisk

@MainActor
@Suite struct HandoffAttribution {
    @Test func marker_is_only_a_hint_and_never_uses_the_frontmost_mac_app() throws {
        let marker = NSPasteboard.PasteboardType("com.apple.is-remote-clipboard")
        let source = try #require(
            AppKitPasteboard.source(types: [marker], appName: "Safari", bundleID: "com.apple.Safari"))
        #expect(source.origin == .handoffMarker)
        #expect(source.name == nil && source.bundleID == nil)
        #expect(source.filterKey == "origin:handoff-marker")
        let local = AppKitPasteboard.source(types: [.string], appName: "Safari", bundleID: "com.apple.Safari")
        #expect(local?.origin == .observedApplication)
        #expect(local?.name == "Safari")
        #expect(!source.matches(try #require(local)))
        #expect(source.matches(try #require(SourceApp(name: nil, origin: .handoffMarker))))
        #expect(AppKitPasteboard.source(types: [], appName: nil, bundleID: nil) == nil)
        let item = ClipboardItem(
            id: UUID(), payload: .text("synthetic"), source: source, copiedAt: Date(), isPinned: false)
        let view = HistoryPresenter().present(
            items: [item], query: "", now: item.copiedAt,
            filters: FilterContext(chips: [.app(source)], activeSourceKeys: [source.filterKey]))
        #expect(view.cards.first?.sourceLabel == localized("Handoff (system marker)"))
        #expect(view.cards.first?.sourceBundleID == nil)
        #expect(view.filters.apps.first?.label == localized("Handoff (system marker)"))
        #expect(FilterHistory()(History(items: [item]), filter: HistoryFilter(sources: [source])) == [item])
    }

    @Test func marked_private_pasteboard_capture_respects_concealed_content() throws {
        let board = NSPasteboard(name: NSPasteboard.Name("handoff-tests-\(UUID())"))
        defer { board.releaseGlobally() }
        let gateway = AppKitPasteboard(board: board)
        board.clearContents()
        board.setString("synthetic Handoff", forType: .string)
        board.setData(Data(), forType: .init("com.apple.is-remote-clipboard"))
        #expect(gateway.readIfChanged()?.source?.origin == .handoffMarker)
        board.clearContents()
        board.setString("synthetic concealed", forType: .string)
        board.setData(Data(), forType: .init("com.apple.is-remote-clipboard"))
        board.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
        #expect(gateway.readIfChanged() == nil)
    }

    @Test func recopy_crossing_handoff_boundary_updates_attribution_while_selection_preserves_it() throws {
        let remote = SourceApp(name: nil, origin: .handoffMarker)
        let local = SourceApp(name: "Notes", bundleID: "com.apple.Notes")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var history = History().recording(.text("same"), from: local, at: now)
        let id = try #require(history.items.first?.id)
        history = history.togglingPin(id)
        history = history.recording(.text("same"), from: remote, at: now.addingTimeInterval(1))
        #expect(history.items.count == 1)
        #expect(history.items[0].id == id && history.items[0].isPinned)
        #expect(history.items[0].source == remote)
        history = history.selecting(id, at: now.addingTimeInterval(2))
        #expect(history.items[0].source == remote)
        history = history.recording(.text("same"), from: local, at: now.addingTimeInterval(3))
        #expect(history.items[0].source == local)
    }

    @Test func additive_schema_preserves_legacy_content_and_round_trips_origin() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("history.sqlite")
        let id = UUID()
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        let sql = """
            CREATE TABLE content(id TEXT PRIMARY KEY, kind TEXT NOT NULL, text TEXT, link TEXT, image BLOB,
                rtf BLOB, files TEXT, source_app TEXT, source_bundle TEXT);
            CREATE TABLE ordering(id TEXT PRIMARY KEY, position INTEGER NOT NULL, copied_at_ms INTEGER NOT NULL,
                is_pinned INTEGER NOT NULL);
            INSERT INTO content(id,kind,text,source_app,source_bundle) VALUES('\(id)','text','legacy canary','Notes','com.apple.Notes');
            INSERT INTO ordering VALUES('\(id)',0,1700000000000,1);
            """
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
        var store: SQLiteHistoryStore? = try SQLiteHistoryStore(databaseURL: url)
        let old = try #require(try store?.load().first)
        #expect(old.payload == .text("legacy canary"))
        #expect(old.isPinned && old.id == id)
        #expect(old.source?.origin == .observedApplication)
        let remote = ClipboardItem(
            id: UUID(), payload: .text("remote canary"),
            source: SourceApp(name: nil, origin: .handoffMarker), copiedAt: old.copiedAt, isPinned: false,
            rtf: Data([1]))
        try store?.save([remote, old])
        store = nil
        let reopened = try SQLiteHistoryStore(databaseURL: url)
        #expect(try reopened.load() == [remote, old])
        // Updating the same identity back to an observed source must clear the origin hint.
        let changed = ClipboardItem(
            id: remote.id, payload: remote.payload, source: old.source,
            copiedAt: old.copiedAt, isPinned: false, rtf: remote.rtf)
        try reopened.save([changed, old])
        #expect(try SQLiteHistoryStore(databaseURL: url).load() == [changed, old])
    }
}

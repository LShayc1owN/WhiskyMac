// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI
import Testing

@testable import Whisk

@MainActor
@Suite struct SensitiveSessions {
    private let source = SourceApp(name: "Synthetic sensitive app", bundleID: "test.sensitive")

    @Test func capture_routes_before_storage_and_exclusions_win() throws {
        let board = ScriptedPasteboard()
        let disk = InMemoryHistoryStore()
        let capture = CaptureClipboardChange(pasteboard: board, clock: FakeClock(), store: disk)
        let session = SensitiveSessionStore(schedulesTimer: false)
        session.setPanelVisible(true)
        let snapshot = PasteboardSnapshot(payload: .text("SECRET-CANARY"), source: source, rtf: Data([1, 2]))
        board.pendingSnapshots = [snapshot, snapshot]
        let history = try capture(
            into: History(), sensitiveBundleIDs: ["test.sensitive"],
            retainSensitive: session.receive)
        #expect(history.items.isEmpty)
        #expect(disk.saveCount == 0)
        #expect(session.ids.count == 1)
        _ = try capture(
            into: history, excluding: ["test.sensitive"],
            sensitiveBundleIDs: ["test.sensitive"], retainSensitive: session.receive)
        #expect(session.ids.count == 1)
        #expect(board.pendingSnapshots.isEmpty)
    }

    @Test func controller_keeps_sensitive_data_out_of_database_wal_search_undo_and_logs() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteHistoryStore(databaseURL: root.appendingPathComponent("synthetic.sqlite"))
        let normal = anItem(.text("ordinary item"))
        try store.save([normal])
        let board = ScriptedPasteboard()
        let logger = RecordingLogger()
        var published = HistoryViewState.empty
        let controller = ClipboardController(pasteboard: board, store: store, clock: FakeClock(), logger: logger) {
            published = $0
        }
        let session = SensitiveSessionStore(schedulesTimer: false)
        session.setPanelVisible(true)
        controller.applySensitiveSources(["test.sensitive"])
        controller.retainSensitive = session.receive
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let before = try files.map { try Data(contentsOf: $0) }
        for payload: Payload in [
            .text("UNIQUE-SECRET"), .link(URL(string: "https://example.invalid/UNIQUE-SECRET")!),
            .image(Data("UNIQUE-SECRET".utf8)), .fileReferences(["/UNIQUE-SECRET"]),
        ] {
            board.pendingSnapshots = [
                PasteboardSnapshot(
                    payload: payload, source: source,
                    rtf: Data("RTF-SECRET".utf8))
            ]
            controller.pollTick()
        }
        #expect(session.ids.count == 4)
        #expect(try store.load() == [normal])
        #expect(try files.map { try Data(contentsOf: $0) } == before)
        #expect(
            try Set(FileManager.default.contentsOfDirectory(atPath: root.path)) == Set(files.map(\.lastPathComponent)))
        controller.search("UNIQUE-SECRET")
        #expect(published.cards.isEmpty)
        controller.clear()
        controller.undo()
        #expect(try store.load() == [normal])
        #expect(logger.messages.isEmpty)
        #expect(SensitiveSessionStore(schedulesTimer: false).ids.isEmpty)
    }

    @Test func session_is_hidden_by_default_expires_and_never_exports_without_a_live_reveal() throws {
        var time: TimeInterval = 0
        let session = SensitiveSessionStore(now: { time }, schedulesTimer: false)
        session.setPanelVisible(true)
        var copies: [Payload] = []
        var copiedRTF: Data?
        session.copyToPasteboard = { payload, rtf in
            copies.append(payload); copiedRTF = rtf
        }
        session.receive(PasteboardSnapshot(payload: .text("secret"), source: source, rtf: Data([42])))
        let id = try #require(session.ids.first)
        #expect(session.revealedPayload(id) == nil)
        session.copy(id)
        #expect(copies.isEmpty)
        session.reveal(id)
        #expect(session.revealedPayload(id) == .text("secret"))
        session.copy(id)
        #expect(copies == [.text("secret")])
        #expect(copiedRTF == Data([42]))
        time = 10
        #expect(session.revealedPayload(id) == nil)
        session.copy(id)
        #expect(copies.count == 1)
        session.sweep()
        #expect(session.revealedID == nil)
        time = 119
        session.reveal(id)
        time = 120
        session.sweep()
        #expect(session.ids.isEmpty)
        #expect(session.revealedPayload(id) == nil)
    }

    @Test func global_privacy_and_panel_close_revoke_reveal_without_revealing_on_restore() throws {
        let state = HistoryViewStateStore()
        let session = state.sensitiveSession
        session.setPanelVisible(true)
        session.receive(PasteboardSnapshot(payload: .text("secret"), source: source))
        let id = try #require(session.ids.first)
        session.reveal(id)
        state.panelDidClose()
        #expect(session.revealedPayload(id) == nil)
        session.reveal(id)
        #expect(session.revealedID == nil)
        session.setPanelVisible(true)
        session.reveal(id)
        state.setPrivacy(true)
        session.reveal(id)
        #expect(session.revealedPayload(id) == nil)
        state.setPrivacy(false)
        #expect(session.revealedPayload(id) == nil)
        #expect(session.ids == [id])
        session.reveal(UUID())
        #expect(session.revealedID == nil)
        session.remove(id)
        #expect(session.ids.isEmpty)
    }

    @Test func bounded_session_evicts_oldest_declines_oversize_and_handles_payload_kinds() throws {
        let session = SensitiveSessionStore(schedulesTimer: false)
        session.setPanelVisible(true)
        for i in 0..<12 {
            session.receive(PasteboardSnapshot(payload: .text("\(i)"), source: nil))
        }
        #expect(session.ids.count == 10)
        let newest = try #require(session.ids.first)
        session.reveal(newest)
        #expect(session.revealedPayload(newest) == .text("11"))
        session.receive(
            PasteboardSnapshot(payload: .image(Data(count: SensitiveSessionStore.maximumBytes + 1)), source: nil))
        #expect(session.ids.count == 10)
        session.receive(
            PasteboardSnapshot(payload: .image(Data(count: SensitiveSessionStore.maximumBytes)), source: nil))
        #expect(session.ids.count == 1)
        session.receive(PasteboardSnapshot(payload: .fileReferences(["/synthetic"]), source: nil))
        session.receive(PasteboardSnapshot(payload: .link(URL(string: "https://example.invalid")!), source: nil))
        #expect(session.ids.count == 2)
        session.clear()
        #expect(session.ids.isEmpty)
    }

    @Test func selected_sources_and_retention_are_opt_in_and_persist_independently() throws {
        let sandbox = try IsolatedDefaults()
        let general = GeneralSettingsStore(defaults: sandbox.defaults)
        #expect(general.sensitiveApps.isEmpty)
        #expect(!general.retainSensitiveCopies)
        general.sensitiveApps = [ExcludedApp(bundleID: "test.sensitive", name: "Synthetic")]
        let restored = GeneralSettingsStore(defaults: sandbox.defaults)
        #expect(restored.sensitiveBundleIDs == ["test.sensitive"])
        #expect(!restored.retainSensitiveCopies)
        general.retainSensitiveCopies = true
        #expect(GeneralSettingsStore(defaults: sandbox.defaults).retainSensitiveCopies)
        #expect(general.excludedApps.isEmpty)
    }

    @Test func sensitive_exports_keep_no_record_markers_and_marked_input_is_always_refused() throws {
        let board = NSPasteboard(name: NSPasteboard.Name("sensitive-tests-\(UUID())"))
        defer { board.releaseGlobally() }
        let writer = AppKitPasteboard(board: board)
        let observer = AppKitPasteboard(board: board)
        writer.writeSensitive(.text("synthetic password"), rtf: Data([9]))
        #expect(board.string(forType: .string) == "synthetic password")
        #expect(board.types?.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) == true)
        #expect(observer.readIfChanged() == nil)
        #expect(writer.readIfChanged() == nil)
        for marker in [
            "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType",
        ] {
            board.clearContents()
            board.setString("marked canary", forType: .string)
            board.setData(Data(), forType: NSPasteboard.PasteboardType(marker))
            #expect(observer.readIfChanged() == nil)
        }
    }

    @Test func revealed_session_renders_payloads_and_hidden_lease_exposes_no_canary() throws {
        _ = NSApplication.shared
        let session = SensitiveSessionStore(schedulesTimer: false)
        session.setPanelVisible(true)
        for payload: Payload in [
            .text("SENSITIVE-VIEW-CANARY"), .link(URL(string: "https://example.invalid/SENSITIVE-VIEW-CANARY")!),
            .fileReferences(["/SENSITIVE-VIEW-CANARY"]), .image(Data([0])),
        ] {
            session.receive(PasteboardSnapshot(payload: payload, source: source))
            let id = try #require(session.ids.first)
            session.reveal(id)
            let renderer = ImageRenderer(content: SensitiveSessionView(session: session).frame(width: 600, height: 100))
            #expect(renderer.nsImage != nil)
        }
        session.receive(PasteboardSnapshot(payload: .text("SENSITIVE-VIEW-CANARY"), source: source))
        let revealed = try #require(session.ids.first)
        session.reveal(revealed)
        let host = NSHostingView(rootView: SensitiveSessionView(session: session))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 100)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        func snapshot(_ name: String) throws {
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            #expect(bitmap.pixelsWide > 0)
            if let path = ProcessInfo.processInfo.environment["WHISK_UI_ARTIFACTS"] {
                let directory = URL(fileURLWithPath: path, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try bitmap.representation(using: .png, properties: [:])?.write(
                    to: directory.appendingPathComponent(name))
            }
        }
        #expect(session.revealedPayload(revealed) == .text("SENSITIVE-VIEW-CANARY"))
        try snapshot("sensitive-revealed.png")
        session.hide()
        host.rootView = SensitiveSessionView(session: session)
        host.layoutSubtreeIfNeeded()
        #expect(session.revealedPayload(revealed) == nil)
        try snapshot("sensitive-hidden.png")
        session.setProtected(true)
        #expect(session.revealedPayload(try #require(session.ids.first)) == nil)
    }
}

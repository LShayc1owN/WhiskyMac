// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI
import Testing
import Vision

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

    @Test func sensitive_rules_and_custom_retention_persist_without_a_second_opt_in() throws {
        let sandbox = try IsolatedDefaults()
        let general = GeneralSettingsStore(defaults: sandbox.defaults)
        #expect(general.sensitiveApps.isEmpty)
        #expect(general.sensitiveRetentionMinutes == 2)
        let app = ExcludedApp(bundleID: "test.sensitive", name: "Synthetic")
        general.addSensitiveApp(app)
        general.sensitiveRetentionMinutes = 7
        let restored = GeneralSettingsStore(defaults: sandbox.defaults)
        #expect(restored.sensitiveBundleIDs == ["test.sensitive"])
        #expect(restored.sensitiveRetentionMinutes == 7)
        #expect(restored.excludedApps.isEmpty)
        restored.excludeApp(app)
        #expect(restored.sensitiveApps.isEmpty)
        #expect(restored.excludedBundleIDs == ["test.sensitive"])
        restored.addSensitiveApp(app)
        restored.addSensitiveApp(app)
        #expect(restored.excludedApps.isEmpty)
        #expect(restored.sensitiveApps == [app])
    }

    @Test func minute_input_is_bounded_and_invalid_drafts_do_not_become_preferences() throws {
        #expect(SensitiveRetention.minutes(from: " 15 ") == 15)
        #expect(SensitiveRetention.minutes(from: "0") == 1)
        #expect(SensitiveRetention.minutes(from: "9999") == 1440)
        for invalid in ["", "-2", "1.5", "nan", "∞", "9999999999999999999999999"] {
            #expect(SensitiveRetention.minutes(from: invalid) == nil)
        }
        let sandbox = try IsolatedDefaults()
        let settings = GeneralSettingsStore(defaults: sandbox.defaults)
        settings.sensitiveRetentionMinutes = -5
        #expect(settings.sensitiveRetentionMinutes == 1)
        settings.sensitiveRetentionMinutes = Int.max
        #expect(GeneralSettingsStore(defaults: sandbox.defaults).sensitiveRetentionMinutes == 1440)
    }

    @Test func custom_deadlines_delete_entries_and_never_restart_on_reveal_or_copy() throws {
        var time: TimeInterval = 0
        let session = SensitiveSessionStore(now: { time }, schedulesTimer: false)
        session.setRetention(minutes: 3)
        session.setPanelVisible(true)
        var copied = 0
        session.copyToPasteboard = { _, _ in copied += 1 }
        session.receive(PasteboardSnapshot(payload: .text("SHORT-LIVED"), source: source))
        let id = try #require(session.ids.first)
        time = 179
        session.reveal(id)
        session.copy(id)
        #expect(copied == 1)
        time = 180
        session.copy(id)
        session.reveal(id)
        #expect(copied == 1)
        #expect(session.ids.isEmpty)
        #expect(session.revealedPayload(id) == nil)
        session.setRetention(minutes: 10)
        session.setPanelVisible(true)
        #expect(session.ids.isEmpty)
        #expect(SensitiveSessionStore(schedulesTimer: false).ids.isEmpty)
    }

    @Test func lowering_retention_expires_old_copies_and_raising_it_does_not_extend_them() throws {
        var time: TimeInterval = 0
        let session = SensitiveSessionStore(now: { time }, schedulesTimer: false)
        session.setPanelVisible(true)
        session.setRetention(minutes: 5)
        session.receive(PasteboardSnapshot(payload: .text("FIRST"), source: source))
        let first = try #require(session.ids.first)
        time = 119
        session.reveal(first)
        session.setRetention(minutes: 2)
        time = 120
        session.setRetention(minutes: 10)
        #expect(session.ids.isEmpty)
        #expect(session.revealedID == nil)
        session.receive(PasteboardSnapshot(payload: .text("SECOND"), source: source))
        let second = try #require(session.ids.first)
        time = 719
        session.sweep()
        #expect(session.ids == [second])
        time = 720
        session.sweep()
        #expect(session.ids.isEmpty)
        session.setRetention(minutes: 1)
        session.receive(PasteboardSnapshot(payload: .text("THIRD"), source: source))
        time = 781
        session.setRetention(minutes: 10)
        #expect(session.ids.isEmpty)
    }

    @Test func sensitive_access_navigation_shows_both_rules_without_leaking_names_on_other_pages_or_during_protection()
        throws
    {
        _ = NSApplication.shared
        let previousLanguage = AppLocalization.language
        AppLocalization.language = "en"
        defer { AppLocalization.language = previousLanguage }
        let sandbox = try IsolatedDefaults()
        let general = GeneralSettingsStore(defaults: sandbox.defaults)
        general.addSensitiveApp(ExcludedApp(bundleID: "test.sensitive", name: "SENSITIVE-APP-CANARY"))
        general.excludeApp(ExcludedApp(bundleID: "test.excluded", name: "EXCLUDED-APP-CANARY"))
        let appearance = AppearanceSettingsStore(defaults: sandbox.defaults)
        let privacy = PrivacyController(defaults: sandbox.defaults)
        for navigation in SettingsNavigation.allCases {
            appearance.navigation = navigation
            privacy.setProtected(false)
            let host = NSHostingView(
                rootView: SettingsView(
                    store: KeyBindingsStore(defaults: sandbox.defaults), general: general,
                    loginItem: LoginItemManager(),
                    vimBindings: VimBindingsStore(defaults: sandbox.defaults), privacy: privacy, appearance: appearance,
                    selectedPage: .privacy))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 960, height: 820),
                styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            window.contentView = host
            host.frame = window.contentLayoutRect
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            NotificationCenter.default.post(
                name: .settingsPageRequested,
                object: SettingsDestination(section: .sensitiveAccess))
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            host.layoutSubtreeIfNeeded()
            func visibleText() throws -> String {
                host.layoutSubtreeIfNeeded()
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let image = try #require(bitmap.cgImage)
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["en-US"]
                request.usesLanguageCorrection = false
                try VNImageRequestHandler(cgImage: image).perform([request])
                return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                    .joined().filter { $0.isLetter }.uppercased()
            }
            let visible = try visibleText()
            #expect(visible.contains("SENSITIVEAPPCANARY"))
            #expect(visible.contains("EXCLUDEDAPPCANARY"))
            #expect(visible.contains("KEEPSENSITIVECOPIESFOR"))
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            if let output = ProcessInfo.processInfo.environment["WHISK_UI_ARTIFACTS"] {
                let directory = URL(fileURLWithPath: output)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try bitmap.representation(using: .png, properties: [:])?.write(
                    to: directory.appendingPathComponent("sensitive-access-\(navigation.rawValue).png"))
            }
            // Moving to another parent page must discard the app-list view,
            // including after visiting another About subsection.
            for (index, heading) in [(1, "ABOUTTHEDEVELOPER"), (2, "DOCUMENT")] {
                NotificationCenter.default.post(
                    name: .settingsPageRequested,
                    object: SettingsDestination(page: .about, sectionIndex: index))
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
                let text = try visibleText()
                #expect(text.contains(heading))
                #expect(!text.contains("APPCANARY"))
            }
            NotificationCenter.default.post(
                name: .settingsPageRequested,
                object: SettingsDestination(section: .sensitiveAccess))
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            privacy.setProtected(true)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            #expect(try !visibleText().contains("APPCANARY"))
        }
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

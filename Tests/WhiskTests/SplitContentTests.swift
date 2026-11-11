// WhiskyMac: modified or added 2026-11-10 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SQLite3
import SwiftUI
import Testing

@testable import Whisk

@MainActor
@Suite struct SplitContentTests {
    private func item(_ text: String, rtf: Data? = nil, pinned: Bool = false) -> ClipboardItem {
        ClipboardItem(
            id: UUID(), payload: .text(text), source: SourceApp(name: "Synthetic", bundleID: "test.split"),
            copiedAt: Date(timeIntervalSince1970: 1_700_000_000), isPinned: pinned, rtf: rtf)
    }
    private func parts(_ text: String, options: SplitOptions = SplitOptions()) throws -> [SplitPart] {
        try SplitContentCodec.analyze(item(text), options: options).map(\.part)
    }
    private func rtf(_ value: NSAttributedString) throws -> Data {
        try value.data(
            from: NSRange(location: 0, length: value.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }

    @Test func actual_lines_paragraphs_empty_results_and_composed_characters() throws {
        let text = "  张三👨‍👩‍👧‍👦\r\n\r\n李四e\u{301}\n\t\n王五\r最后"
        #expect(try parts(text).map(\.text) == ["张三👨‍👩‍👧‍👦", "李四e\u{301}", "王五", "最后"])
        var options = SplitOptions(); options.rule = .paragraphs
        #expect(try parts(text, options: options).map(\.text) == ["张三👨‍👩‍👧‍👦", "李四e\u{301}", "王五\r最后"])
        options.rule = .lines; options.trimWhitespace = false
        #expect(try parts("  indented\n\nnext", options: options).map(\.text) == ["  indented", "next"])
        #expect(try parts("   \n\r\n\t").isEmpty)
        #expect(try parts(String(repeating: "\n", count: 5000) + "one").count == 1)
    }
    @Test func delimiters_are_literal_support_chinese_and_preserve_punctuation_on_request() throws {
        var options = SplitOptions(); options.rule = .delimiters
        options.delimiters = [.comma, .semicolon, .enumeration, .tab]; options.customDelimiter = "||"
        #expect(
            try parts("a,b，c;d；e、f\tg||h", options: options).map(\.text) == ["a", "b", "c", "d", "e", "f", "g", "h"])
        options.keepDelimiter = true
        #expect(try parts("a,b||c", options: options).map(\.text) == ["a,", "b||", "c"])
        options.keepDelimiter = false; options.delimiters = []; options.customDelimiter = ".*"
        #expect(try parts("a.*b", options: options).map(\.text) == ["a", "b"])
        options.customDelimiter = ""
        #expect(throws: SplitFailure.noDelimiter) { try parts("a,b", options: options) }
        options.customDelimiter = "\u{301}"
        #expect(throws: SplitFailure.invalidBoundary) { try parts("e\u{301}x", options: options) }
    }
    @Test func URL_extraction_does_not_cut_queries_or_include_sentence_punctuation() throws {
        var options = SplitOptions(); options.rule = .links
        let text =
            "First https://example.com/a?q=1&next=2, then https://example.org/b. Again https://example.com/a?q=1&next=2"
        let output = try parts(text, options: options)
        #expect(
            output.map(\.text) == [
                "https://example.com/a?q=1&next=2", "https://example.org/b", "https://example.com/a?q=1&next=2",
            ])
        #expect(output.allSatisfy { $0.link != nil })
        options.linksOnly = false
        let mixed = try parts("prefix https://example.com suffix", options: options)
        #expect(mixed.map(\.text) == ["prefix", "https://example.com", "suffix"])
        #expect(mixed.map { $0.link != nil } == [false, true, false])
        options.linksOnly = true
        #expect(try parts("mail user@example.com ftp://example.com", options: options).isEmpty)
    }
    @Test func rich_text_slices_keep_attributes_and_embedded_targets_without_networking() throws {
        let rich = NSMutableAttributedString(
            string: "赤い字\nclick here",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 16), .foregroundColor: NSColor.red])
        rich.addAttribute(
            .link, value: URL(string: "https://example.invalid/secret?q=1")!,
            range: (rich.string as NSString).range(of: "click here"))
        let source = item(rich.string, rtf: try rtf(rich))
        let candidates = try SplitContentCodec.analyze(source, options: SplitOptions())
        #expect(candidates.map(\.part.text) == ["赤い字", "click here"])
        let first = try #require(candidates.first?.part.rtf)
        let decoded = try NSAttributedString(
            data: first, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        #expect(decoded.string == "赤い字")
        #expect(decoded.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == NSColor.red)
        #expect(decoded.attribute(.font, at: 0, effectiveRange: nil) != nil)
        var options = SplitOptions(); options.rule = .links
        let links = try SplitContentCodec.analyze(source, options: options)
        #expect(links.map(\.part.text) == ["https://example.invalid/secret?q=1"])
        let visible = NSAttributedString(
            string: "https://example.com", attributes: [.link: URL(string: "https://example.com")!])
        #expect(try SplitContentCodec.analyze(item(visible.string, rtf: rtf(visible)), options: options).count == 1)
        let combined = try SplitContentCodec.combine(candidates.map(\.part), plainText: false)
        #expect(combined.0 == .text(rich.string))
        #expect(combined.1 != nil)
        #expect(try SplitContentCodec.combine(candidates.map(\.part), plainText: true).1 == nil)
    }
    @Test func malformed_RTF_requires_explicit_plain_text_and_limits_never_truncate() throws {
        let source = item("a\nb", rtf: Data([0, 1, 2]))
        #expect(throws: SplitFailure.richTextUnavailable) {
            try SplitContentCodec.analyze(source, options: SplitOptions())
        }
        var options = SplitOptions(); options.plainText = true
        #expect(try SplitContentCodec.analyze(source, options: options).map(\.part.text) == ["a", "b"])
        #expect(throws: SplitFailure.tooLarge) {
            try parts(String(repeating: "x", count: SplitLimits.maximumUTF16 + 1))
        }
        #expect(throws: SplitFailure.tooManyParts) {
            try parts(Array(repeating: "x", count: 1001).joined(separator: "\n"))
        }
        #expect(try parts(Array(repeating: "x", count: 1000).joined(separator: "\n")).count == 1000)
        let mismatch = item("plain", rtf: try rtf(NSAttributedString(string: "other")))
        #expect(throws: SplitFailure.richTextUnavailable) {
            try SplitContentCodec.analyze(mismatch, options: SplitOptions())
        }
    }
    @Test func all_save_modes_keep_order_duplicates_metadata_and_original_rules() throws {
        let original = item("a\na", pinned: true).withPinnedMetadata(PinnedMetadata(note: "Alias", tags: [.blue]))
        let children = try parts("a\na")
        let history = History(items: [original])
        for mode in SplitSaveMode.allCases {
            let request = SplitSaveRequest(source: original, parts: children, mode: mode, plainText: false)
            let next = try SaveSplit.prepare(request, in: history, policy: .standard, now: original.copiedAt).history
            if mode == .group {
                #expect(next.items.count == 1)
                #expect(next.items[0].id == original.id)
                #expect(next.items[0].splitGroup?.parts == children)
                #expect(next.items[0].pinnedMetadata == original.pinnedMetadata)
            } else {
                #expect(next.items.prefix(2).map(\.payload) == [.text("a"), .text("a")])
                #expect(next.items.prefix(2).map(\.id) == children.map(\.id))
                #expect(
                    next.items.prefix(2).allSatisfy {
                        $0.isPinned && $0.source == original.source && $0.pinnedMetadata.tags == [.blue]
                    })
                #expect(next.items.prefix(2).map(\.pinnedMetadata.note) == ["Alias · 1", "Alias · 2"])
                #expect(next.items.contains(original) == (mode == .keepOriginal))
            }
        }
    }
    @Test func capacity_assessment_keeps_selected_results_and_requires_confirmation_for_old_evictions() throws {
        let source = item("a\nb")
        let old = item("old")
        let policy = RetentionPolicy(capacity: try #require(HistoryCapacity(3)))
        let request = SplitSaveRequest(source: source, parts: try parts("a\nb"), mode: .keepOriginal, plainText: false)
        let assessment = try SaveSplit.prepare(
            request, in: History(items: [source, old]), policy: policy, now: source.copiedAt)
        #expect(assessment.evictedCount == 1)
        #expect(assessment.history.items.contains(source))
        let tiny = RetentionPolicy(capacity: try #require(HistoryCapacity(1)))
        #expect(throws: SplitFailure.capacity) {
            try SaveSplit.prepare(request, in: History(items: [source]), policy: tiny, now: source.copiedAt)
        }
    }
    @Test func controller_saves_once_undo_restores_and_group_selection_never_directly_exports() throws {
        let source = item("a\nb")
        let board = ScriptedPasteboard()
        let disk = InMemoryHistoryStore(); disk.stored = [source]
        let controller = ClipboardController(
            pasteboard: board, store: disk, clock: FakeClock(), logger: RecordingLogger()
        ) { _ in }
        let initialSaves = disk.saveCount
        let request = SplitSaveRequest(source: source, parts: try parts("a\nb"), mode: .group, plainText: false)
        try controller.saveSplit(request, confirmEviction: false)
        #expect(disk.saveCount == initialSaves + 1)
        #expect(board.written.isEmpty)
        let group = try #require(controller.item(for: source.id))
        var selections = 0
        controller.requestGroupSelection = { id, _, _ in
            #expect(id == source.id); selections += 1
        }
        #expect(!controller.select(source.id))
        #expect(!controller.activateSelected())
        #expect(!controller.activate(at: 0))
        #expect(selections == 3 && board.written.isEmpty)
        controller.toggleStack(source.id)
        #expect(!controller.popStack())
        let selected = Set(group.splitGroup!.parts.map(\.id))
        try controller.exportGroup(
            group, selected: selected, original: false, plain: false, forPaste: false,
            combine: SplitContentCodec.combine)
        #expect(board.written == [.text("a\nb")])
        controller.undo()
        #expect(disk.stored == [source])
    }
    @Test func groups_persist_as_one_root_and_failures_roll_back_whole_transaction() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.sqlite")
        let source = item("a\nb")
        let group = source.withSplitGroup(SplitGroup(parts: try parts("a\nb"), plainText: false))
        var store: SQLiteHistoryStore? = try SQLiteHistoryStore(databaseURL: url)
        try store?.save([group])
        store = nil; store = try SQLiteHistoryStore(databaseURL: url)
        #expect(try store?.load() == [group])
        var db: OpaquePointer?; #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        #expect(
            sqlite3_exec(
                db,
                "CREATE TRIGGER deny_split BEFORE UPDATE ON split_groups BEGIN SELECT RAISE(ABORT, 'synthetic'); END",
                nil, nil, nil) == SQLITE_OK)
        let changed = source.replacing(payload: .text("changed")).withSplitGroup(
            SplitGroup(parts: try parts("c\nd"), plainText: true))
        #expect(throws: (any Error).self) { try store?.save([changed]) }
        #expect(try store?.load() == [group])
        try store?.save([])
        #expect(try store?.load().isEmpty == true)
    }
    @Test func group_search_retention_and_capture_identity_do_not_flatten_children() throws {
        let source = item("original")
        let group = source.withSplitGroup(SplitGroup(parts: try parts("unique-child\nsecond"), plainText: false))
        let history = History(items: [group])
        #expect(FilterHistory()(history, filter: HistoryFilter(query: "unique-child")).map(\.id) == [group.id])
        #expect(RichTextGroups.groups([group]).count == 1)
        #expect(history.recording(source.payload, from: source.source, at: source.copiedAt).items.count == 2)
        #expect(history.removingUnpinned(olderThan: source.copiedAt.addingTimeInterval(1)).items.isEmpty)
        #expect(history.deleting(group.id).items.isEmpty)
    }
    @Test func session_cancellation_stale_source_and_save_failure_keep_privacy_and_drafts() async throws {
        var source = item("a\nb")
        var allowed = true
        var saved = 0
        let initial = source
        let session = SplitSession(
            source: source, current: { _ in source }, allowed: { allowed },
            assess: { request in
                try SaveSplit.prepare(request, in: History(items: [source]), policy: .standard, now: source.copiedAt)
            },
            save: { _, _ in
                saved += 1; throw SplitFailure.storage
            })
        for _ in 0..<100 where session.analyzing { try await Task.sleep(for: .milliseconds(10)) }
        #expect(session.candidates.count == 2)
        #expect(!session.commit())
        #expect(session.candidates.count == 2 && saved == 1 && session.source == initial)
        session.options.rule = .delimiters
        session.options.customDelimiter = "\\n"
        session.options.rule = .lines
        allowed = false
        session.invalidateIfNeeded()
        try await Task.sleep(for: .milliseconds(40))
        #expect(session.source == nil && session.candidates.isEmpty && !session.canSave)
        allowed = true
        source = initial
        let stale = SplitSession(
            source: source, current: { _ in source }, allowed: { true },
            assess: { _ in throw SplitFailure.stale }, save: { _, _ in saved += 1 })
        source = source.pinToggled()
        stale.invalidateIfNeeded()
        #expect(stale.source == nil && !stale.commit())
    }
    @Test func group_selector_is_exclusive_defaults_first_and_revalidates_before_export() throws {
        let source = item("full").withSplitGroup(SplitGroup(parts: try parts("one\ntwo"), plainText: false))
        var current: ClipboardItem? = source
        var output: [UUID] = []
        let session = SplitGroupSession(
            source: source, action: .copy, plain: false, query: "two",
            current: { _ in current }, allowed: { true },
            export: { _, selected, original, _, paste in
                #expect(!paste && !original); output = Array(selected)
            })
        #expect(session.selected == [source.splitGroup!.parts[0].id])
        #expect(session.matches(source.splitGroup!.parts[1]))
        session.original = true
        #expect(session.selected.isEmpty)
        session.toggle(source.splitGroup!.parts[1].id, enabled: true)
        #expect(!session.original && session.commit())
        #expect(output == [source.splitGroup!.parts[1].id])
        current = nil
        session.invalidateIfNeeded()
        #expect(session.source == nil && session.selected.isEmpty && !session.commit())
    }
}

@MainActor
@Suite struct SplitIntegrationTests {
    private func source(_ text: String = "a\nb") -> ClipboardItem {
        anItem(.text(text))
    }
    @Test func independent_RTF_parts_do_not_regroup_and_origin_survives_reopen() throws {
        let text = NSMutableAttributedString(string: "same\nsame", attributes: [.foregroundColor: NSColor.red])
        let rtf = try text.data(
            from: NSRange(location: 0, length: text.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        let item = ClipboardItem(
            id: UUID(), payload: .text(text.string), source: nil, copiedAt: .now, isPinned: false, rtf: rtf)
        let parts = try SplitContentCodec.analyze(item, options: SplitOptions()).map(\.part)
        let request = SplitSaveRequest(source: item, parts: parts, mode: .replace, plainText: false)
        let next = try SaveSplit.prepare(
            request, in: History(items: [item]), policy: .standard, now: Date(timeIntervalSince1970: 1_700_000_000)
        ).history
        #expect(RichTextGroups.groups(next.items).count == 2)
        #expect(next.items.allSatisfy { $0.splitSourceID == item.id })
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("origins.sqlite")
        do { let store = try SQLiteHistoryStore(databaseURL: url); try store.save(next.items) }
        #expect(try SQLiteHistoryStore(databaseURL: url).load() == next.items)
    }
    @Test func commit_failure_does_not_add_an_undo_entry_or_touch_the_pasteboard() throws {
        let original = source()
        let board = ScriptedPasteboard()
        let store = SaveFailingHistoryStore(); store.stored = [original]
        let controller = ClipboardController(
            pasteboard: board, store: store, clock: FakeClock(), logger: RecordingLogger()
        ) { _ in }
        let parts = try SplitContentCodec.analyze(original, options: SplitOptions()).map(\.part)
        #expect(throws: SplitFailure.storage) {
            try controller.saveSplit(
                SplitSaveRequest(source: original, parts: parts, mode: .replace, plainText: false),
                confirmEviction: true)
        }
        #expect(controller.item(for: original.id) == original)
        #expect(!controller.undo() && board.written.isEmpty)
    }
    @Test func eviction_requires_a_new_confirmation_and_selected_parts_are_never_silently_lost() throws {
        let original = source()
        let disk = InMemoryHistoryStore(); disk.stored = [original, source("older")]
        let controller = ClipboardController(
            pasteboard: ScriptedPasteboard(), store: disk, clock: FakeClock(),
            retention: RetentionPolicy(capacity: try #require(HistoryCapacity(3))), logger: RecordingLogger()
        ) { _ in }
        let parts = try SplitContentCodec.analyze(original, options: SplitOptions()).map(\.part)
        let request = SplitSaveRequest(source: original, parts: parts, mode: .keepOriginal, plainText: false)
        #expect(try controller.assessSplit(request).evictedCount == 1)
        #expect(throws: SplitFailure.needsEvictionConfirmation) {
            try controller.saveSplit(request, confirmEviction: false)
        }
        #expect(disk.stored.count == 2)
        try controller.saveSplit(request, confirmEviction: true)
        #expect(disk.stored.map(\.id) == parts.map(\.id) + [original.id])
        #expect(controller.undo())
        #expect(disk.stored.count == 2)
    }
    @Test func hidden_items_groups_and_empty_selection_cannot_be_split_or_committed() throws {
        let original = source()
        let hidden = original.withPinnedMetadata(PinnedMetadata(hidesContent: true))
        #expect(throws: SplitFailure.unavailable) { try SplitContentCodec.analyze(hidden, options: SplitOptions()) }
        let parts = try SplitContentCodec.analyze(original, options: SplitOptions()).map(\.part)
        let group = original.withSplitGroup(SplitGroup(parts: parts, plainText: false))
        #expect(throws: SplitFailure.unavailable) { try SplitContentCodec.analyze(group, options: SplitOptions()) }
        let request = SplitSaveRequest(source: original, parts: [], mode: .keepOriginal, plainText: false)
        #expect(throws: SplitFailure.noSelection) {
            try SaveSplit.prepare(request, in: History(items: [original]), policy: .standard, now: .now)
        }
        #expect(throws: SplitFailure.noSelection) { try SplitContentCodec.combine([], plainText: true) }
        let model = HistoryViewStateStore()
        model.setPanelVisible(true)
        model.setPrivacy(true)
        model.chooseSplitVersion([original])
        #expect(model.splitVersions.isEmpty)
    }
    @Test func group_exports_respect_parent_order_original_exclusivity_and_source_revalidation() throws {
        let root = source("full")
        let parts = try SplitContentCodec.analyze(source("one\ntwo\nthree"), options: SplitOptions()).map(\.part)
        let group = root.withSplitGroup(SplitGroup(parts: parts, plainText: true))
        let disk = InMemoryHistoryStore(); disk.stored = [group]
        let board = ScriptedPasteboard()
        let controller = ClipboardController(
            pasteboard: board, store: disk, clock: FakeClock(), logger: RecordingLogger()
        ) { _ in }
        try controller.exportGroup(
            group, selected: [parts[2].id, parts[0].id], original: false, plain: false,
            forPaste: false, combine: SplitContentCodec.combine)
        #expect(board.written == [.text("one\nthree")])
        #expect(board.writtenRTF == [nil])
        let current = try #require(controller.item(for: root.id))
        #expect(throws: SplitFailure.noSelection) {
            try controller.exportGroup(
                current, selected: [parts[0].id], original: true, plain: false,
                forPaste: false, combine: SplitContentCodec.combine)
        }
        try controller.exportGroup(
            current, selected: [], original: true, plain: false, forPaste: false, combine: SplitContentCodec.combine)
        #expect(board.written.last == root.payload)
        controller.delete(root.id)
        #expect(throws: SplitFailure.stale) {
            try controller.exportGroup(
                current, selected: [], original: true, plain: false, forPaste: false, combine: SplitContentCodec.combine
            )
        }
    }
}

@MainActor
@Suite struct SplitUITests {
    private func wait(_ session: SplitSession) async throws {
        for _ in 0..<100 where session.analyzing { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!session.analyzing)
    }
    @Test func result_preview_and_group_selector_render_without_network_requests() async throws {
        _ = NSApplication.shared
        let previousLanguage = AppLocalization.language
        AppLocalization.language = "en"
        defer { AppLocalization.language = previousLanguage }
        let source = anItem(.text("Name,Phone\nhttps://example.invalid/private?q=synthetic"))
        let session = SplitSession(
            source: source, current: { _ in source }, allowed: { true },
            assess: { request in
                try SaveSplit.prepare(request, in: History(items: [source]), policy: .standard, now: source.copiedAt)
            },
            save: { _, _ in })
        try await wait(session)
        func snapshot<Content: View>(_ content: Content, name: String) throws {
            let host = NSHostingView(rootView: content)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 800),
                styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            window.contentView = host; host.frame = window.contentLayoutRect
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            #expect(bitmap.pixelsWide > 0)
            if let output = ProcessInfo.processInfo.environment["WHISK_UI_ARTIFACTS"] {
                let directory = URL(fileURLWithPath: output)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try bitmap.representation(using: .png, properties: [:])?.write(
                    to: directory.appendingPathComponent(name))
            }
        }
        try snapshot(SplitContentView(session: session, close: {}), name: "split-lines.png")
        session.options.rule = .delimiters
        try await wait(session)
        session.mode = .replace
        try snapshot(SplitContentView(session: session, close: {}), name: "split-delimiters.png")
        session.options.rule = .links
        try await wait(session)
        #expect(session.candidates.first?.part.link?.host == "example.invalid")
        session.mode = .group
        try snapshot(SplitContentView(session: session, close: {}), name: "split-links.png")
        let group = source.withSplitGroup(SplitGroup(parts: session.candidates.map(\.part), plainText: false))
        let chooser = SplitGroupSession(
            source: group, action: .copy, plain: false, query: "example",
            current: { _ in group }, allowed: { true }, export: { _, _, _, _, _ in })
        try snapshot(SplitGroupView(session: chooser, close: {}), name: "split-group.png")
        try snapshot(SplitGroupPreview(source: group), name: "split-group-preview.png")
        session.invalidate()
        #expect(session.options == SplitOptions())
        try snapshot(SplitContentView(session: session, close: {}), name: "split-expired.png")
        let model = HistoryViewStateStore()
        model.setPanelVisible(true)
        model.chooseSplitVersion([source])
        try snapshot(SplitVersionView(store: model), name: "split-versions.png")
        model.panelDidClose()
        #expect(model.splitVersions.isEmpty)
        for rule in SplitRule.allCases { #expect(!rule.label.isEmpty) }
        for mode in SplitSaveMode.allCases { #expect(!mode.label.isEmpty) }
        for delimiter in SplitDelimiter.allCases { #expect(!delimiter.label.isEmpty) }
        for failure: SplitFailure in [
            .unavailable, .stale, .tooLarge, .tooManyParts, .noDelimiter, .invalidBoundary,
            .richTextUnavailable, .noSelection, .capacity, .needsEvictionConfirmation, .storage,
        ] {
            #expect(!failure.message.isEmpty)
        }
    }
    @Test func changing_capacity_after_preview_requires_confirmation_again() async throws {
        let source = anItem(.text("a\nb"))
        var count = 0
        var saved = false
        let session = SplitSession(
            source: source, current: { _ in source }, allowed: { true },
            assess: { _ in SplitSaveAssessment(history: History(items: [source]), evictedCount: count) },
            save: { _, _ in saved = true })
        try await wait(session)
        #expect(session.evictedCount == 0)
        count = 2
        #expect(!session.commit() && !saved)
        #expect(session.evictedCount == 2 && !session.confirmEviction)
        session.confirmEviction = true
        #expect(session.commit() && saved)
    }
    @Test func root_state_clears_sessions_on_privacy_close_and_source_updates() async throws {
        var source = anItem(.text("a\nb"))
        let state = HistoryViewStateStore()
        state.setPanelVisible(true)
        state.detailSource = { _ in source }
        let session = SplitSession(
            source: source, current: { _ in source }, allowed: { !state.isProtected },
            assess: { _ in throw SplitFailure.stale }, save: { _, _ in })
        state.splitSession = session
        try await wait(session)
        source = source.pinToggled()
        state.update(HistoryPresenter().present(items: [source], query: "", now: .now))
        #expect(session.source == nil && session.candidates.isEmpty)
        state.setPrivacy(true)
        #expect(state.splitSession == nil)
        state.setPrivacy(false)
        let second = SplitSession(
            source: source, current: { _ in source }, allowed: { true },
            assess: { _ in throw SplitFailure.stale }, save: { _, _ in })
        state.splitSession = second
        state.panelDidClose()
        #expect(second.source == nil && state.splitSession == nil)
    }
}

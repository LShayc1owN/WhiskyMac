// WhiskyMac: modified or added 2026-11-15 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Testing

@testable import Whisk

@MainActor
@Suite struct LongTextBehaviour {
    @Test(arguments: [false, true])
    func cards_bound_unicode_text_without_truncating_exports_editing_or_details(code: Bool) throws {
        let prefix = code ? "func run() { return 1 }\n" : "Project notes\n"
        let original = prefix + String(repeating: "家庭👨‍👩‍👧‍👦 café e\u{301}\n", count: 5000) + "ORIGINAL-END"
        let item = anItem(.text(original))
        let state = HistoryPresenter().present(items: [item], query: "", now: item.copiedAt, selectedID: item.id)
        let card = try #require(state.selectedCard)
        let excerpt: String
        switch card.preview {
        case .text(let value), .code(let value, _): excerpt = value
        default: throw Failure.unexpectedPreview
        }
        #expect(excerpt.count == 1024)
        #expect(original.hasPrefix(excerpt))
        #expect(!excerpt.contains("ORIGINAL-END"))
        #expect(card.dragPayload == .text(original))
        #expect(card.detailLabel == localized("\(original.count) characters"))

        let store = HistoryViewStateStore()
        store.detailSource = { $0 == item.id ? item : nil }
        store.update(state)
        store.setPanelVisible(true)
        store.beginEditing(card)
        #expect(store.editingText == original)
        store.endEditing()
        store.preparePreview()
        #expect(store.previewItems.first?.payload == .text(original))

        let board = ScriptedPasteboard()
        let history = InMemoryHistoryStore()
        history.stored = [item]
        let controller = ClipboardController(pasteboard: board, store: history, clock: FakeClock(), present: { _ in })
        #expect(controller.select(item.id))
        #expect(board.written == [.text(original)])
    }

    @Test func editing_only_the_tail_invalidates_the_cached_full_character_count() throws {
        let original = anItem(.text(String(repeating: "word ", count: 2000) + "old"))
        let edited = original.replacing(payload: .text(String(repeating: "word ", count: 2000) + "new tail"))
        let presenter = HistoryPresenter()
        let first = try #require(presenter.present(items: [original], query: "", now: original.copiedAt).cards.first)
        let second = try #require(presenter.present(items: [edited], query: "", now: edited.copiedAt).cards.first)
        #expect(first.preview == second.preview)
        #expect(first.detailLabel != second.detailLabel)
        #expect(second.detailLabel == localized("\(10_008) characters"))
        #expect(second.dragPayload == .text(String(repeating: "word ", count: 2000) + "new tail"))
    }

    @Test func search_can_find_text_beyond_the_excerpt_without_creating_out_of_bounds_highlights() throws {
        let item = anItem(.text(String(repeating: "😀 notes ", count: 2000) + "zebramarker"))
        let items = FilterHistory()(History(items: [item]), filter: HistoryFilter(query: "zebramarker"))
        #expect(items.map(\.id) == [item.id])
        let card = try #require(
            HistoryPresenter().present(items: items, query: "zebramarker", now: item.copiedAt).cards.first)
        #expect(card.matches.isEmpty)
        guard case .text(let excerpt) = card.preview else { throw Failure.unexpectedPreview }
        #expect(excerpt.count == 1024)
        #expect(!excerpt.contains("zebramarker"))
    }

    private enum Failure: Error { case unexpectedPreview }
}

@MainActor
@Suite struct NativeTextPreviews {
    @Test(arguments: [false, true])
    func full_text_stays_selectable_and_repeated_updates_preserve_selection(code: Bool) throws {
        _ = NSApplication.shared
        let original =
            "func run() { return 1 }\n" + String(repeating: "Long preview line\n", count: 60_000) + "END-MARKER"
        let surface = TextPreviewView.Surface(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let tokens = code ? CodeHighlighter.tokens(in: original) : []
        surface.update(text: original, tokens: tokens, monospaced: code)
        #expect(surface.textView.string == original)
        #expect(surface.textView.isSelectable && !surface.textView.isEditable)
        #expect(surface.textView.layoutManager?.allowsNonContiguousLayout == true)
        let end = NSRange(location: original.utf16.count - 10, length: 10)
        surface.textView.setSelectedRange(end)
        surface.update(text: original, tokens: tokens, monospaced: code)
        #expect(surface.textView.selectedRange() == end)
        if code {
            #expect(
                surface.textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
                    == .systemPurple)
        }
        surface.clear()
        #expect(surface.textView.string.isEmpty)
    }
}

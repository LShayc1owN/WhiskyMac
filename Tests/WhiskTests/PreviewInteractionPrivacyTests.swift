// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI
import Testing

@testable import Whisk

@MainActor
@Suite struct PreviewInteractionPrivacy {
    private func rich(_ text: String, format: String) -> ClipboardItem {
        ClipboardItem(
            id: UUID(), payload: .text(text), source: SourceApp(name: "SYNTHETIC_SOURCE"),
            copiedAt: Date(timeIntervalSince1970: 1_700_000_000), isPinned: false,
            rtf: RichTextCodec.encode(
                NSAttributedString(
                    string: text,
                    attributes: [
                        .foregroundColor: format == "red" ? NSColor.red : NSColor.blue,
                        .font: NSFont.boldSystemFont(ofSize: 18),
                    ])))
    }

    @Test func rich_formats_round_trip_and_invalid_or_oversized_input_falls_back() throws {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let original = NSAttributedString(
            string: "hello\nworld",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 18), .foregroundColor: NSColor.red,
                .link: URL(string: "https://example.com")!, .paragraphStyle: paragraph,
            ])
        let data = try #require(RichTextCodec.encode(original))
        let decoded = RichTextCodec.decode(data, fallback: "wrong")
        #expect(decoded.string == original.string)
        #expect((decoded.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 18)
        #expect(decoded.attribute(.link, at: 0, effectiveRange: nil) != nil)
        let font = try #require(decoded.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        let color = try #require(
            (decoded.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)?.usingColorSpace(.deviceRGB))
        #expect(color.redComponent > 0.9 && color.blueComponent < 0.1)
        #expect(
            (decoded.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment == .center)
        #expect(RichTextCodec.decode(Data("broken".utf8), fallback: "safe").string == "safe")
        #expect(
            RichTextCodec.decode(Data(repeating: 0, count: RichTextCodec.maximumBytes + 1), fallback: "safe").string
                == "safe")
    }

    @Test func formatted_versions_group_but_plain_copies_stay_independent() throws {
        let first = rich("same", format: "red")
        let second = rich("same", format: "blue")
        let plain = anItem(.text("same"))
        let state = HistoryPresenter().present(
            items: [first, second, plain], query: "", now: first.copiedAt, selectedID: first.id)
        #expect(state.cards.count == 2)
        #expect(state.cards[0].variantIDs == [first.id, second.id])
        #expect(state.cards[1].variantIDs == [plain.id])
        let store = HistoryViewStateStore()
        var reads = 0
        store.detailSource = { id in
            reads += 1; return [first, second].first { $0.id == id }
        }
        store.update(state)
        #expect(reads == 0)
        store.preparePreview()
        #expect(store.previewItems == [first, second])
        store.closePreview()
        #expect(store.previewItems.isEmpty)
    }

    @Test func grouped_click_chooses_version_before_the_configured_action() throws {
        let first = rich("same", format: "red")
        let second = rich("same", format: "blue")
        let store = HistoryViewStateStore()
        store.detailSource = { id in [first, second].first { $0.id == id } }
        store.update(
            HistoryPresenter().present(items: [first, second], query: "", now: first.copiedAt, selectedID: first.id))
        var opens = 0
        store.showPreview = {
            opens += 1; store.preparePreview()
        }
        let spy = PanelActionSpy()
        store.interact(try #require(store.state.selectedCard), action: .copy, actions: spy.actions)
        #expect(opens == 1)
        #expect(!spy.calls.contains { $0.hasPrefix("copy:") })
        store.chooseVersion(second.id, actions: spy.actions)
        #expect(spy.calls.last == "copy:\(second.id)")
    }

    @Test func interactions_persist_all_four_triggers_and_start_conservatively() throws {
        let sandbox = try IsolatedDefaults()
        let settings = GeneralSettingsStore(defaults: sandbox.defaults)
        #expect(settings.interactions == InteractionBindings())
        settings.interactions = InteractionBindings(
            singleClick: .copy, doubleClick: .edit, rightClick: .preview, hover: .preview)
        let restored = GeneralSettingsStore(defaults: sandbox.defaults).interactions
        #expect(restored.action(for: .singleClick) == .copy)
        #expect(restored.action(for: .doubleClick) == .edit)
        #expect(restored.action(for: .rightClick) == .preview)
        #expect(restored.action(for: .hover) == .preview)
        #expect(KeyBindingsStore(defaults: sandbox.defaults).enabledGlobalActions.isEmpty)
    }

    @Test func manual_privacy_persists_and_masks_before_exposing_state() throws {
        let sandbox = try IsolatedDefaults()
        let privacy = PrivacyController(defaults: sandbox.defaults)
        let store = HistoryViewStateStore()
        let item = rich("CANARY_SECRET", format: "red")
        let original = HistoryPresenter().present(
            items: [item], query: "CANARY_QUERY", now: item.copiedAt, selectedID: item.id)
        store.detailSource = { _ in item }
        store.update(original)
        store.preparePreview()
        store.beginEditing(try #require(store.state.selectedCard))
        privacy.willChangeProtection = { store.setPrivacy($0) }
        privacy.setProtected(true)
        #expect(store.state == .empty)
        #expect(store.previewItems.isEmpty)
        #expect(store.editing == nil)
        #expect(store.editingText.isEmpty)
        #expect(store.editingRichText == nil)
        // New captures and query changes cannot repopulate protected DTOs.
        store.update(original)
        store.preparePreview()
        #expect(store.state == .empty)
        #expect(store.previewItems.isEmpty)
        #expect(PrivacyController(defaults: sandbox.defaults).isProtected)
        privacy.setProtected(false)
        #expect(store.state == original)
    }

    @Test func protected_actions_block_stale_menus_drag_and_keyboard_consumption() throws {
        let spy = PanelActionSpy()
        var protected = true
        let actions = spy.actions.guarded { protected }
        let id = UUID()
        actions.copy(id)
        actions.select(id)
        actions.dragBegan()
        actions.openLink(URL(string: "https://example.com")!)
        actions.revealFiles(["/CANARY_PATH"])
        actions.saveToDisk(.text("CANARY_SECRET"))
        actions.activateCard(0)
        actions.edit(id, "CANARY_EDIT")
        actions.search("CANARY_QUERY")
        #expect(spy.calls.isEmpty)
        protected = false
        actions.copy(id)
        #expect(spy.calls == ["copy:\(id)"])
    }

    @Test func protected_views_render_only_placeholder_and_drop_accessibility_content() throws {
        let store = HistoryViewStateStore()
        let item = rich("CANARY_SECRET", format: "red")
        store.update(HistoryPresenter().present(items: [item], query: "CANARY_QUERY", now: item.copiedAt))
        store.setPrivacy(true)
        let view = HistoryPanelView(store: store, actions: PanelActionSpy().actions)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: 1000, height: 430)
        #expect(renderer.nsImage != nil)
        let host = HistoryPanelHosting.make(store: store, actions: PanelActionSpy().actions)
        host.frame = NSRect(x: 0, y: 0, width: 1000, height: 430)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        func labels(_ object: AnyObject, depth: Int = 0) -> String {
            guard depth < 20, let node = object as? NSAccessibilityProtocol else { return "" }
            let own = [node.accessibilityLabel(), node.accessibilityValue() as? String, node.accessibilityHelp()]
                .compactMap { $0 }.joined(separator: " ")
            return own
                + (node.accessibilityChildren() ?? []).map { labels($0 as AnyObject, depth: depth + 1) }.joined(
                    separator: " ")
        }
        let accessible = labels(host)
        #expect(accessible.contains(localized("Content hidden by Privacy Mode")))
        #expect(!accessible.contains("CANARY"))
        #expect(!accessible.contains("SYNTHETIC_SOURCE"))
    }

    @Test func rich_edit_saves_both_plain_text_and_rtf_to_a_reopened_database() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        let item = rich("before", format: "red")
        try SQLiteHistoryStore(databaseURL: url).save([item])
        let controller = ClipboardController(
            pasteboard: ScriptedPasteboard(), store: try SQLiteHistoryStore(databaseURL: url),
            clock: FakeClock(), logger: RecordingLogger(), present: { _ in })
        let rtf = try #require(RichTextCodec.encode(NSAttributedString(string: "after")))
        controller.editRich(item.id, text: "after", rtf: rtf)
        let saved = try #require(try SQLiteHistoryStore(databaseURL: url).load().first)
        #expect(saved.id == item.id)
        #expect(saved.payload == .text("after"))
        #expect(saved.rtf == rtf)
        controller.undo()
        #expect(try SQLiteHistoryStore(databaseURL: url).load() == [item])
    }

    @Test func privacy_clears_preview_caches_and_refuses_late_results() {
        let links = LinkPreviewStore()
        let files = FileThumbnailStore()
        let image = NSImage(size: NSSize(width: 2, height: 2))
        links.store(LinkPreview(title: "CANARY_TITLE", host: "CANARY_HOST", icon: nil, image: nil), for: "CANARY_URL")
        files.store(image, for: "CANARY_FILE")
        links.setPrivacy(true)
        files.setPrivacy(true)
        links.store(LinkPreview(title: "LATE_SECRET", host: nil, icon: nil, image: nil), for: "LATE_URL")
        files.store(image, for: "LATE_FILE")
        #expect(links.previews.isEmpty)
        #expect(files.thumbnails.isEmpty)
        #expect(links.preview(for: "CANARY_URL") == nil)
        #expect(files.thumbnail(for: "CANARY_FILE") == nil)
        links.setPrivacy(false)
        files.setPrivacy(false)
        #expect(links.preview(for: "LATE_URL") == nil)
        #expect(files.thumbnail(for: "LATE_FILE") == nil)
    }

    @Test func preview_selection_and_expansion_are_cleared_when_selection_changes() throws {
        let first = rich("same", format: "red")
        let second = rich("same", format: "blue")
        let third = rich("same", format: "red")
        let other = anItem(.text("other"))
        let items = [first, second, third, other]
        let store = HistoryViewStateStore()
        store.detailSource = { id in items.first { $0.id == id } }
        store.update(HistoryPresenter().present(items: items, query: "", now: first.copiedAt, selectedID: first.id))
        store.preparePreview()
        #expect(store.previewItems.count == 3)
        store.expandedVersions = true
        store.pendingAction = .paste
        store.update(HistoryPresenter().present(items: items, query: "", now: first.copiedAt, selectedID: other.id))
        #expect(!store.expandedVersions)
        #expect(store.pendingAction == nil)
        #expect(store.previewItems == [other])
    }

    @Test func rich_drafts_save_as_rtf_and_privacy_abandons_pending_actions() throws {
        let item = rich("original", format: "red")
        let store = HistoryViewStateStore()
        store.detailSource = { _ in item }
        store.update(HistoryPresenter().present(items: [item], query: "", now: item.copiedAt, selectedID: item.id))
        store.beginEditing(try #require(store.state.selectedCard))
        store.editingRichText = NSAttributedString(string: "edited", attributes: [.font: NSFont.systemFont(ofSize: 20)])
        var saved: (UUID, String, Data)?
        var actions = PanelActionSpy().actions
        actions.editRich = { saved = ($0, $1, $2) }
        store.saveEditing(actions: actions)
        #expect(saved?.0 == item.id)
        #expect(saved?.1 == "edited")
        #expect(RichTextCodec.decode(saved?.2, fallback: "wrong").string == "edited")
        #expect(store.editing == nil)
        store.pendingAction = .paste
        store.setPrivacy(true)
        store.chooseVersion(item.id, actions: actions)
        #expect(store.pendingAction == nil)
    }

    @Test func public_materials_render_in_both_appearances() throws {
        let item = anItem(.text("Synthetic visual fixture"))
        let card = try #require(HistoryPresenter().present(items: [item], query: "", now: item.copiedAt).cards.first)
        for scheme in [ColorScheme.light, .dark] {
            let view = ItemCardView(card: card, actions: PanelActionSpy().actions)
                .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = ProposedViewSize(width: 240, height: 240)
            #expect(renderer.nsImage != nil)
        }
    }

    @Test func preview_renders_two_formats_expanded_formats_and_manual_placeholder() throws {
        let items = [
            rich("Synthetic preview", format: "red"), rich("Synthetic preview", format: "blue"),
            rich("Synthetic preview", format: "red"),
        ]
        let store = HistoryViewStateStore()
        store.detailSource = { id in items.first { $0.id == id } }
        store.update(
            HistoryPresenter().present(items: items, query: "", now: items[0].copiedAt, selectedID: items[0].id))
        store.preparePreview()
        for protected in [false, true] {
            store.setPrivacy(protected)
            for expanded in [false, true] {
                store.expandedVersions = expanded
                let view = PreviewOverlayView(store: store, actions: PanelActionSpy().actions)
                let host = NSHostingView(rootView: view)
                host.frame = NSRect(x: 0, y: 0, width: 900, height: 360)
                let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.03))
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                #expect(bitmap.pixelsWide > 0)
                if let directory = ProcessInfo.processInfo.environment["WHISK_UI_ARTIFACTS"] {
                    let target = URL(fileURLWithPath: directory, isDirectory: true)
                    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                    try bitmap.representation(using: .png, properties: [:])?.write(
                        to: target.appendingPathComponent("preview-\(protected)-\(expanded).png"))
                }
                window.close()
            }
        }
    }
}

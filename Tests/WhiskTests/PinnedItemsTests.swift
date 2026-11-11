// WhiskyMac: modified or added 2026-11-08 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Carbon.HIToolbox
import SQLite3
import SwiftUI
import Testing
import Vision

@testable import Whisk

@MainActor
@Suite struct PinnedItemsTests {
    private let details = PinnedMetadata(note: "Shipping details", hidesContent: true, tags: [.red, .blue])

    @Test func identity_operations_keep_metadata_and_pinned_rtf_versions_are_independent() {
        let original = anItem(.text("secret"), pinned: true).withPinnedMetadata(details)
        let history = History(items: [original])
        let copied = history.recording(original.payload, from: original.source, at: .now)
        #expect(copied.items.first?.id == original.id)
        #expect(copied.items.first?.pinnedMetadata == details)
        #expect(original.copied(at: .now).pinnedMetadata == details)
        #expect(original.replacing(payload: .text("edited")).pinnedMetadata == details)
        #expect(original.pinToggled().pinnedMetadata == details)
        #expect(history.updatingPinnedMetadata(UUID(), value: details) == history)
        let unpinned = original.pinToggled()
        #expect(
            History(items: [unpinned]).updatingPinnedMetadata(original.id, value: PinnedMetadata()).items == [unpinned])
        let first = ClipboardItem(
            id: UUID(), payload: .text("same"), source: nil, copiedAt: .now,
            isPinned: true, rtf: Data([1]), pinnedMetadata: details)
        let second = ClipboardItem(
            id: UUID(), payload: .text("same"), source: nil, copiedAt: .now,
            isPinned: false, rtf: Data([2]))
        #expect(RichTextGroups.groups([first, second]).count == 2)
        #expect(PinnedMetadata(note: "  name  ").normalized.note == "name")
        #expect(PinnedMetadata(note: String(repeating: "a", count: 250)).normalized.note.count == 200)
    }

    @Test func sqlite_metadata_reopens_without_updating_payload_blobs_and_failure_rolls_back() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("pins.sqlite")
        let base = anItem(.image(Data([1, 2, 3])), pinned: true)
        var store: SQLiteHistoryStore? = try SQLiteHistoryStore(databaseURL: url)
        try store?.save([base])
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        func sql(_ text: String) throws {
            #expect(sqlite3_exec(db, text, nil, nil, nil) == SQLITE_OK)
        }
        try sql(
            "CREATE TRIGGER no_blob_rewrite BEFORE UPDATE ON content BEGIN SELECT RAISE(ABORT, 'unchanged blobs'); END")
        let modified = base.withPinnedMetadata(details)
        try store?.save([modified])
        store = nil
        store = try SQLiteHistoryStore(databaseURL: url)
        #expect(try store?.load() == [modified])
        try sql(
            "CREATE TRIGGER refuse_details BEFORE DELETE ON pin_details BEGIN SELECT RAISE(ABORT, 'test failure'); END")
        #expect(throws: (any Error).self) { try store?.save([base]) }
        #expect(try store?.load() == [modified])
        try sql("DROP TRIGGER refuse_details")
        try sql("UPDATE pin_details SET metadata = 'broken'")
        #expect(throws: (any Error).self) { try store?.load() }
    }

    @Test func hidden_cards_publish_no_original_bytes_paths_rtf_or_drag_content() throws {
        let presenter = HistoryPresenter()
        for payload: Payload in [
            .text("SECRET-CANARY"), .image(Data("SECRET-CANARY".utf8)),
            .fileReferences(["/private/SECRET-CANARY.txt"]),
            .link(URL(string: "https://user:password@SECRET-CANARY.example.com:8443/a?token=SECRET-CANARY#private")!),
        ] {
            let item = ClipboardItem(
                id: UUID(), payload: payload, source: nil, copiedAt: .now,
                isPinned: true, rtf: Data("SECRET-RTF".utf8), pinnedMetadata: details)
            let state = presenter.present(items: [item], query: "SECRET-CANARY", now: .now, selectedID: item.id)
            let card = try #require(state.cards.first)
            #expect(card.contentHidden)
            #expect(card.pinnedMetadata.note == "Shipping details")
            #expect(!String(describing: card).contains("SECRET"))
            #expect(card.rtf == nil)
            #expect(card.detailLabel == nil)
            #expect(card.dragPayload == .text(""))
            #expect(!card.transformable && !card.saveable && card.matches.isEmpty)
            #expect(presenter.cachedPreviewCount == 0)
        }
        #expect(
            HistoryPresenter.hiddenSummary(.link(URL(string: "https://private.example.com/path?q=secret")!))
                == "https://••••••.com")
        #expect(HistoryPresenter.hiddenSummary(.link(URL(string: "https://127.0.0.1/private")!)) == "https://••••••")
    }

    @Test func notes_are_searchable_hidden_payloads_are_not_and_color_tags_filter_with_or() {
        let hidden = anItem(.text("CONFIDENTIAL"), pinned: true).withPinnedMetadata(details)
        let green = anItem(.text("ordinary"), pinned: true).withPinnedMetadata(PinnedMetadata(tags: [.green]))
        let ordinary = anItem(.text("unpinned"))
        let history = History(items: [hidden, green, ordinary])
        let filter = FilterHistory()
        #expect(filter(history, filter: HistoryFilter(query: "CONFIDENTIAL")).isEmpty)
        #expect(filter(history, filter: HistoryFilter(query: "Shipping")).map(\.id) == [hidden.id])
        #expect(filter(history, filter: HistoryFilter(tags: [.red, .blue])).map(\.id) == [hidden.id])
        #expect(Set(filter(history, filter: HistoryFilter(tags: [.blue, .green])).map(\.id)) == [hidden.id, green.id])
    }

    @Test func separate_scope_never_exposes_unpinned_items_and_aggregate_scope_can_be_reset() throws {
        let store = InMemoryHistoryStore()
        let pin = anItem(.text("pin"), pinned: true).withPinnedMetadata(details)
        let ordinary = anItem(.text("ordinary"))
        store.stored = [pin, ordinary]
        var state = HistoryViewState.empty
        let controller = ClipboardController(
            pasteboard: ScriptedPasteboard(), store: store, clock: FakeClock(),
            logger: RecordingLogger()
        ) { state = $0 }
        controller.openPinnedWorkspace(locked: true)
        #expect(state.cards.map(\.id) == [pin.id])
        #expect(state.filters.tags.map(\.id) == [PinTagColor.red.filterKey, PinTagColor.blue.filterKey])
        controller.clear()
        controller.deleteAll(fromSource: pin.source!.filterKey)
        #expect(store.stored.count == 2)
        controller.toggleCategoryFilter(PinTagColor.red.filterKey)
        #expect(state.filters.tags.first?.isActive == true)
        controller.toggleCategoryFilter(allFiltersChipID)
        #expect(state.cards.map(\.id) == [pin.id])
        controller.togglePin(pin.id)
        #expect(state.cards.isEmpty)
        controller.panelWillShow()
        #expect(state.cards.count == 2)
        controller.togglePin(pin.id)
        controller.openPinnedWorkspace(locked: false)
        #expect(state.cards.map(\.id) == [pin.id])
        controller.toggleCategoryFilter(allFiltersChipID)
        #expect(state.cards.count == 2)
    }

    @Test func metadata_changes_survive_undo_of_an_older_edit_and_storage_failure_is_atomic() throws {
        let store = InMemoryHistoryStore()
        let pin = anItem(.text("original"), pinned: true)
        store.stored = [pin]
        let controller = ClipboardController(
            pasteboard: ScriptedPasteboard(), store: store, clock: FakeClock(),
            logger: RecordingLogger()
        ) { _ in }
        controller.edit(pin.id, text: "rewritten")
        controller.updatePinnedMetadata(pin.id, value: details)
        controller.undo()
        #expect(controller.item(for: pin.id)?.payload == pin.payload)
        #expect(controller.item(for: pin.id)?.pinnedMetadata == details)
        let disk = SaveFailingHistoryStore()
        disk.stored = [pin]
        let failing = ClipboardController(
            pasteboard: ScriptedPasteboard(), store: disk, clock: FakeClock(),
            logger: RecordingLogger()
        ) { _ in }
        failing.updatePinnedMetadata(pin.id, value: details)
        #expect(failing.item(for: pin.id) == pin)
    }

    @Test func hidden_state_blocks_preview_edit_and_manual_privacy_spotlight_even_for_old_cards() throws {
        let raw = anItem(.text("SECRET-CANARY"), pinned: true)
        var item = raw
        let state = HistoryViewStateStore()
        let presenter = HistoryPresenter()
        state.detailSource = { _ in item }
        state.update(presenter.present(items: [raw], query: "", now: .now, selectedID: raw.id))
        let previousCard = try #require(state.state.selectedCard)
        state.preparePreview()
        #expect(state.previewItems == [raw])
        var previews = 0
        state.showPreview = { previews += 1 }
        item = raw.withPinnedMetadata(details)
        state.update(presenter.present(items: [item], query: "", now: .now, selectedID: item.id))
        #expect(state.previewItems.isEmpty)
        state.interact(previousCard, action: .preview, actions: PanelActionSpy().actions)
        state.beginEditing(previousCard)
        state.toggleExplicitPreview()
        #expect(previews == 0 && state.editing == nil)
        state.preparePreview()
        #expect(state.previewItems.isEmpty)
        state.setPanelVisible(true)
        state.setPrivacy(true)
        state.setSpotlightAllowed(true)
        #expect(state.protectedRevealPayload(for: item.id) == nil)
    }

    @Test func hidden_link_policy_clears_old_metadata_and_refuses_late_metadata() {
        let store = LinkPreviewStore()
        let address = "https://example.invalid/private"
        let metadata = LinkPreview(title: "SECRET-CANARY", host: "example.invalid", icon: nil, image: nil)
        store.store(metadata, for: address)
        #expect(store.preview(for: address)?.title == "SECRET-CANARY")
        store.setHiddenAddresses([address])
        store.load(address)  // Guard must reject before a provider or request is created.
        store.store(metadata, for: address)
        #expect(store.preview(for: address) == nil)
        #expect(store.previews[address] == nil)
        store.setHiddenAddresses([])
        #expect(store.preview(for: address) == nil)
    }

    @Test func pinned_defaults_are_separate_mouse_list_and_shortcut_is_independent_and_opt_in() throws {
        let sandbox = try IsolatedDefaults()
        let preferences = GeneralSettingsStore(defaults: sandbox.defaults)
        #expect(preferences.pinnedPresentation == .separate && preferences.pinnedWindowStyle == .mouseList)
        preferences.pinnedPresentation = .aggregated
        preferences.pinnedWindowStyle = .bottomCards
        let restored = GeneralSettingsStore(defaults: sandbox.defaults)
        #expect(restored.pinnedPresentation == .aggregated && restored.pinnedWindowStyle == .bottomCards)
        let keys = KeyBindingsStore(defaults: sandbox.defaults)
        #expect(KeyAction.togglePinned.isGlobal)
        #expect(!keys.isGlobalEnabled(.togglePinned))
        #expect(keys.binding(for: .togglePinned) != keys.binding(for: .togglePanel))
        keys.setGlobalEnabled(true, for: .togglePinned)
        #expect(KeyBindingsStore(defaults: sandbox.defaults).isGlobalEnabled(.togglePinned))
    }

    @Test func copying_a_hidden_pin_exports_the_original_rtf_and_does_not_discard_its_details() throws {
        let board = ScriptedPasteboard()
        let disk = InMemoryHistoryStore()
        let item = ClipboardItem(
            id: UUID(), payload: .text("SECRET-CANARY"), source: nil, copiedAt: .now,
            isPinned: true, rtf: Data([4, 5, 6]), pinnedMetadata: details)
        disk.stored = [item]
        let controller = ClipboardController(
            pasteboard: board, store: disk, clock: FakeClock(),
            logger: RecordingLogger()
        ) { _ in }
        controller.select(item.id)
        #expect(board.written == [item.payload])
        #expect(board.writtenRTF == [item.rtf])
        #expect(controller.item(for: item.id)?.pinnedMetadata == details)
        controller.editRich(item.id, text: "new", rtf: Data([7]))
        #expect(controller.item(for: item.id)?.pinnedMetadata == details)
        controller.undo()
        #expect(controller.item(for: item.id)?.pinnedMetadata == details)
    }

    @Test func list_and_metadata_editor_render_notes_but_global_protection_removes_them() throws {
        _ = NSApplication.shared
        let previousLanguage = AppLocalization.language
        AppLocalization.language = "en"
        defer { AppLocalization.language = previousLanguage }
        let item = anItem(.text("SECRET-CANARY"), pinned: true).withPinnedMetadata(details)
        let state = HistoryViewStateStore()
        state.update(HistoryPresenter().present(items: [item], query: "", now: .now, selectedID: item.id))
        let host = NSHostingView(rootView: PinnedListView(store: state, actions: PanelActionSpy().actions))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 560),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = host
        host.frame = window.contentLayoutRect
        func visibleText(_ name: String) throws -> String {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            try VNImageRequestHandler(cgImage: #require(bitmap.cgImage)).perform([request])
            if let output = ProcessInfo.processInfo.environment["WHISK_UI_ARTIFACTS"] {
                let directory = URL(fileURLWithPath: output)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try bitmap.representation(using: .png, properties: [:])?.write(
                    to: directory.appendingPathComponent(name))
            }
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        }
        let visible = try visibleText("pins-list.png")
        #expect(visible.localizedCaseInsensitiveContains("Shipping details"))
        #expect(!visible.contains("SECRET"))
        state.setPrivacy(true)
        let protected = try visibleText("pins-protected.png")
        #expect(!protected.localizedCaseInsensitiveContains("Shipping details"))
        #expect(!protected.contains("SECRET"))
        let editor = ImageRenderer(content: PinnedItemEditor(value: details, save: { _ in }).padding())
        #expect(editor.nsImage != nil)
        for tag in PinTagColor.allCases { #expect(!tag.label.isEmpty); _ = tag.color }
    }

    @Test func pinned_surface_reuses_a_second_window_without_activation_and_restores_main_scope() throws {
        _ = NSApplication.shared
        let sandbox = try IsolatedDefaults()
        let state = HistoryViewStateStore()
        let spy = PanelActionSpy()
        var requests: [Bool] = []
        var actions = spy.actions
        actions.preparePinned = { requests.append($0) }
        var controller: PanelController? = PanelController(
            stateStore: state, actions: actions,
            keyBindings: KeyBindingsStore(defaults: sandbox.defaults),
            vimBindings: VimBindingsStore(defaults: sandbox.defaults),
            vimMode: { false })
        let main = try #require(controller?.activeWindow)
        controller?.preparePresentation(pins: true, style: .mouseList)
        let pins = try #require(controller?.activeWindow)
        #expect(pins !== main)
        #expect(!pins.isVisible && !main.isVisible)
        #expect(state.isPinnedWorkspace && state.isPinnedList)
        controller?.preparePresentation(pins: true, style: .bottomCards)
        #expect(controller?.activeWindow === pins)
        #expect(state.isPinnedWorkspace && !state.isPinnedList)
        controller?.preparePresentation(pins: true, style: nil)
        #expect(controller?.activeWindow === main)
        #expect(requests == [true, true, false])
        controller?.preparePresentation(pins: false, style: nil)
        #expect(controller?.activeWindow === main)
        #expect(!state.isPinnedWorkspace && !state.isPinnedList)
        #expect(!main.isVisible)
        weak var released = controller
        controller = nil
        #expect(released == nil)
        #expect(main.contentView == nil && pins.contentView == nil)
    }

    @Test func metadata_text_input_owns_shortcuts_and_vertical_keys_move_between_records() throws {
        let sandbox = try IsolatedDefaults()
        let state = HistoryViewStateStore()
        let spy = PanelActionSpy()
        let keys = KeyBindingsStore(defaults: sandbox.defaults)
        let router = PanelKeyRouter(
            stateStore: state, actions: spy.actions, keyBindings: keys,
            vimBindings: VimBindingsStore(defaults: sandbox.defaults), togglePreview: {}, closePanel: {})
        func event(_ code: Int, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try #require(
                NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: modifiers,
                    timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                    isARepeat: false, keyCode: UInt16(code)))
        }
        state.isPinnedList = true
        state.pinMetadataEditing = true
        #expect(try !router.handle(event(kVK_Return)))
        #expect(try !router.handle(event(kVK_Delete, modifiers: [.command])))
        #expect(spy.calls.isEmpty)
        state.pinMetadataEditing = false
        state.cardMenuOpen = true
        #expect(try !router.handle(event(kVK_UpArrow)))
        #expect(try !router.handle(event(kVK_Delete, modifiers: [.command])))
        #expect(spy.calls.isEmpty)
        state.cardMenuOpen = false
        #expect(try router.handle(event(kVK_UpArrow)))
        #expect(try router.handle(event(kVK_DownArrow)))
        #expect(spy.calls == ["navigate:left", "navigate:right"])
    }

    @Test func pointer_layout_stays_inside_small_and_negative_coordinate_displays() {
        for frame in [
            CGRect(x: -1920, y: -300, width: 1920, height: 1080), CGRect(x: 0, y: 0, width: 300, height: 400),
        ] {
            for pointer in [frame.origin, CGPoint(x: frame.maxX, y: frame.maxY), CGPoint(x: -9999, y: 9999)] {
                let result = PinnedWindowLayout.frame(pointer: pointer, visibleFrame: frame)
                #expect(frame.contains(result))
            }
        }
        for mode in PinnedPresentation.allCases { #expect(!mode.label.isEmpty) }
        for style in PinnedWindowStyle.allCases { #expect(!style.label.isEmpty) }
    }
}

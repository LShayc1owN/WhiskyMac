// WhiskyMac: modified or added 2026-11-18 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Carbon.HIToolbox
import SwiftUI
import Testing

@testable import Whisk

@MainActor
@Suite(.serialized) struct TemporaryHistoryVisibilityTests {
    private final class Fixture {
        let board = ScriptedPasteboard()
        let disk = InMemoryHistoryStore()
        let clock = FakeClock()
        let state = HistoryViewStateStore()
        let controller: ClipboardController<ScriptedPasteboard, FakeClock, InMemoryHistoryStore, RecordingLogger>

        init(items: [ClipboardItem]? = nil) {
            disk.stored =
                items ?? [
                    anItem(
                        .text("OLD SECRET"), from: "Old App", bundle: "test.old", at: clock.now().addingTimeInterval(-1)
                    ),
                    anItem(
                        .text("PINNED SECRET"), from: "Pinned App", bundle: "test.pinned", at: clock.now(), pinned: true
                    ).withPinnedMetadata(PinnedMetadata(tags: [.red])),
                ]
            let state = state
            controller = ClipboardController(pasteboard: board, store: disk, clock: clock) { state.update($0) }
            state.setPanelVisible(true)
        }

        var actions: PanelActions {
            var actions = PanelActionSpy().actions
            actions.clearHistory = { self.controller.clear() }
            actions.toggleHistoryVisibility = { self.controller.toggleHistoryVisibility() }
            actions.setHistoryHiding = { self.controller.setHistoryHiding($0) }
            actions.clearTypeHistoryHiding = { self.controller.clearTypeHistoryHiding() }
            return actions.guarded(by: { self.state.isProtected })
        }

        func capture(_ text: String = "NEW COPY") {
            clock.advance(by: 1)
            board.pendingSnapshots = [
                PasteboardSnapshot(payload: .text(text), source: SourceApp(name: "New App", bundleID: "test.new"))
            ]
            controller.pollTick()
        }
    }

    @Test func hides_all_existing_cards_at_the_cutoff_without_saving_and_keeps_new_copies_visible() {
        let fixture = Fixture()
        let old = fixture.disk.stored
        fixture.state.toggleHistoryVisibility(actions: fixture.actions)
        #expect(fixture.state.isHistoryHidden)
        #expect(fixture.state.state.cards.isEmpty && fixture.state.state.filters.isEmpty)
        #expect(fixture.disk.stored == old && fixture.disk.saveCount == 0)
        #expect(!fixture.controller.activate(at: 0))
        #expect(!fixture.controller.activateSelected())
        #expect(fixture.board.written.isEmpty)

        fixture.capture()
        #expect(fixture.state.state.cards.map(\.preview) == [.text("NEW COPY")])
        #expect(fixture.state.state.filters.apps.map(\.id) == ["test.new"])
        let saved = fixture.disk.stored
        fixture.state.panelDidClose()
        fixture.controller.panelWillShow()
        fixture.state.setPanelVisible(true)
        #expect(fixture.state.isHistoryHidden)
        #expect(fixture.state.state.cards.map(\.preview) == [.text("NEW COPY")])
        fixture.state.toggleHistoryVisibility(actions: fixture.actions)
        #expect(!fixture.state.isHistoryHidden && fixture.state.state.cards.count == 3)
        #expect(fixture.disk.stored == saved && fixture.disk.saveCount == 1)
    }

    @Test func search_cannot_reveal_hidden_cards_but_recopying_the_same_item_can() {
        let fixture = Fixture()
        let id = fixture.disk.stored[0].id
        fixture.controller.toggleHistoryVisibility()
        fixture.controller.search("OLD SECRET")
        #expect(fixture.state.state.cards.isEmpty)
        fixture.capture("OLD SECRET")
        #expect(fixture.state.state.cards.map(\.id) == [id])
        #expect(fixture.disk.stored.count == 2)
        fixture.controller.toggleHistoryVisibility()
        fixture.controller.search("")
        #expect(fixture.state.state.cards.count == 2)
        #expect(fixture.state.state.cards.contains { $0.isPinned })
    }

    @Test func type_hiding_respects_the_cutoff_and_leaves_other_types_and_new_copies_visible() throws {
        let now = FakeClock().now()
        let oldText = anItem(.text("OLD TEXT"), at: now.addingTimeInterval(-10))
        let image = anItem(.image(Data([0])), at: now.addingTimeInterval(-10))
        let atCutoff = anItem(.text("AT CUTOFF"), at: now.addingTimeInterval(-5), pinned: true)
        let newer = anItem(.text("NEWER TEXT"), at: now.addingTimeInterval(-4))
        let fixture = Fixture(items: [newer, atCutoff, image, oldText])
        let rule = HistoryHidingRule(cutoff: now.addingTimeInterval(-5), categories: [.text])
        fixture.state.setHistoryHiding(rule, actions: fixture.actions)
        #expect(!fixture.state.isHistoryHidden && fixture.state.isTypeHistoryHidden)
        #expect(fixture.state.state.cards.map(\.id) == [newer.id, image.id])
        #expect(fixture.state.typeHidingRule == rule)
        fixture.controller.search("OLD TEXT")
        #expect(fixture.state.state.cards.isEmpty)
        fixture.controller.search("")
        fixture.state.panelDidClose()
        fixture.controller.panelWillShow()
        fixture.state.setPanelVisible(true)
        #expect(fixture.state.state.cards.map(\.id) == [newer.id, image.id])
        fixture.capture("NEW CAPTURE")
        #expect(fixture.state.state.cards.count == 3)
        fixture.state.clearTypeHistoryHiding(actions: fixture.actions)
        #expect(!fixture.state.isTypeHistoryHidden && fixture.state.state.cards.count == 5)
        #expect(fixture.disk.saveCount == 1)
        #expect(fixture.disk.stored.contains { $0.id == atCutoff.id && $0.isPinned })
        #expect(fixture.board.written.isEmpty)
    }

    @Test func ordinary_and_type_hiding_have_independent_times_and_can_be_cancelled_individually() {
        let now = FakeClock().now()
        let oldText = anItem(.text("OLD"), at: now.addingTimeInterval(-20))
        let newerText = anItem(.text("RECENT"), at: now.addingTimeInterval(-5))
        let image = anItem(.image(Data([0])), at: now.addingTimeInterval(-10))
        let fixture = Fixture(items: [newerText, image, oldText])
        fixture.state.setHistoryHiding(HistoryHidingRule(cutoff: now.addingTimeInterval(-15)), actions: fixture.actions)
        #expect(fixture.state.state.cards.map(\.id) == [newerText.id, image.id])
        fixture.state.setHistoryHiding(HistoryHidingRule(cutoff: now, categories: [.text]), actions: fixture.actions)
        #expect(fixture.state.state.cards.map(\.id) == [image.id])
        fixture.state.toggleHistoryVisibility(actions: fixture.actions)
        #expect(!fixture.state.isHistoryHidden && fixture.state.isTypeHistoryHidden)
        #expect(fixture.state.state.cards.map(\.id) == [image.id])
        fixture.state.clearTypeHistoryHiding(actions: fixture.actions)
        #expect(fixture.state.state.cards.count == 3 && fixture.disk.saveCount == 0)
        fixture.state.setHistoryHiding(HistoryHidingRule(cutoff: now, categories: []), actions: fixture.actions)
        #expect(!fixture.state.isTypeHistoryHidden)
    }

    @Test func bulk_type_selection_toggles_without_changing_handoff_selection() {
        var draft = HistoryHidingDraft(categories: [.text], includesHandoff: true)
        #expect(!draft.allTypesSelected)
        draft.toggleAllTypes()
        #expect(draft.allTypesSelected)
        #expect(draft.categories == Set(ContentCategory.allCases))
        draft.toggleAllTypes()
        #expect(!draft.allTypesSelected && draft.categories.isEmpty)
        #expect(draft.includesHandoff)
    }

    @Test func hiding_draft_does_not_apply_until_confirmed_and_now_is_the_confirmation_time() throws {
        let fixture = Fixture()
        let now = fixture.clock.now()
        var draft = HistoryHidingDraft(date: now)
        #expect(draft.rule(includingTypes: true, now: now) == nil)
        draft.categories = [.text, .image]
        #expect(fixture.state.state.cards.count == 2 && !fixture.state.isTypeHistoryHidden)
        fixture.clock.advance(by: 5)
        let rule = try #require(draft.rule(includingTypes: true, now: fixture.clock.now()))
        #expect(rule.cutoff == now.addingTimeInterval(5))
        fixture.state.setHistoryHiding(rule, actions: fixture.actions)
        #expect(fixture.state.state.cards.isEmpty)
        draft.usesNow = false
        draft.date = now.addingTimeInterval(-10)
        #expect(draft.rule(includingTypes: false, now: now)?.cutoff == draft.date)
        #expect(draft.rule(includingTypes: false, now: now)?.categories == nil)
        draft.date = now.addingTimeInterval(100)
        #expect(draft.rule(includingTypes: false, now: now)?.cutoff == now)
    }

    @Test func hidden_pin_tag_filters_do_not_trap_new_copies() {
        let fixture = Fixture()
        fixture.controller.toggleCategoryFilter(PinTagColor.red.filterKey)
        #expect(fixture.state.state.cards.count == 1)
        fixture.controller.toggleHistoryVisibility()
        fixture.capture()
        #expect(fixture.state.state.cards.map(\.preview) == [.text("NEW COPY")])
        fixture.controller.toggleHistoryVisibility()
        #expect(fixture.state.state.cards.count == 3)
    }

    @Test func hiding_is_session_only_and_does_not_consume_delete_undo_or_hide_the_pinned_workspace() {
        let fixture = Fixture()
        fixture.controller.delete(fixture.disk.stored[0].id)
        fixture.controller.toggleHistoryVisibility()
        #expect(fixture.controller.undo())
        #expect(fixture.state.state.cards.isEmpty && fixture.disk.stored.count == 2)
        fixture.controller.openPinnedWorkspace(locked: true)
        #expect(fixture.state.state.cards.count == 1 && !fixture.state.isHistoryHidden)
        fixture.controller.panelWillShow()
        #expect(fixture.state.state.cards.isEmpty && fixture.state.isHistoryHidden)
        var relaunched = HistoryViewState.empty
        let controller = ClipboardController(
            pasteboard: ScriptedPasteboard(), store: fixture.disk, clock: fixture.clock,
            present: { relaunched = $0 })
        controller.panelWillShow()
        #expect(relaunched.cards.count == 2 && !relaunched.isHistoryHidden)
    }

    @Test func privacy_always_blocks_clear_but_allows_reversible_visibility_without_exporting_content() {
        let fixture = Fixture()
        #expect(fixture.state.canClearHistory)
        fixture.state.setPrivacy(true)
        #expect(!fixture.state.canClearHistory)
        fixture.state.clearHistory(actions: fixture.actions)
        fixture.actions.clearHistory()
        #expect(fixture.disk.saveCount == 0 && fixture.disk.stored.count == 2)
        fixture.state.toggleHistoryVisibility(actions: fixture.actions)
        #expect(fixture.state.isHistoryHidden && fixture.state.protectedCardIDs.isEmpty)
        fixture.state.toggleHistoryVisibility(actions: fixture.actions)
        #expect(!fixture.state.isHistoryHidden && fixture.state.protectedCardCount == 2)
        fixture.state.setHistoryHiding(
            HistoryHidingRule(cutoff: fixture.clock.now(), categories: [.text]), actions: fixture.actions)
        #expect(fixture.state.isTypeHistoryHidden && fixture.state.protectedCardIDs.isEmpty)
        fixture.state.clearTypeHistoryHiding(actions: fixture.actions)
        #expect(fixture.state.protectedCardCount == 2)
        #expect(fixture.state.state == .empty && fixture.state.previewItems.isEmpty)
        #expect(fixture.board.written.isEmpty && fixture.disk.saveCount == 0)
        fixture.state.panelDidClose()
        fixture.state.toggleHistoryVisibility(actions: fixture.actions)
        #expect(!fixture.state.isHistoryHidden)
    }

    @Test(arguments: [false, true])
    func hiding_shortcuts_use_the_same_rules_as_the_toolbar(inPrivacy: Bool) throws {
        let fixture = Fixture()
        fixture.state.setPrivacy(inPrivacy)
        let sandbox = try IsolatedDefaults()
        let keys = KeyBindingsStore(defaults: sandbox.defaults)
        let router = PanelKeyRouter(
            stateStore: fixture.state, actions: fixture.actions, keyBindings: keys,
            vimBindings: VimBindingsStore(defaults: sandbox.defaults), togglePreview: {}, closePanel: {})

        let hide = keys.binding(for: .toggleHistoryVisibility)
        let hideKey = try #require(aKeyEvent(Int(hide.keyCode), hide.modifiers, typing: "h"))
        #expect(router.handle(hideKey))
        #expect(fixture.state.isHistoryHidden)
        #expect(router.handle(hideKey))
        #expect(!fixture.state.isHistoryHidden)

        let type = keys.binding(for: .toggleTypeHistoryVisibility)
        let originalTypeKey = try #require(aKeyEvent(Int(type.keyCode), type.modifiers, typing: "t"))
        #expect(router.handle(originalTypeKey))
        #expect(fixture.state.historyHidingOptions == .typeOrSource)
        #expect(!fixture.state.isTypeHistoryHidden)
        #expect(!router.handle(hideKey))

        fixture.state.historyHidingOptions = nil
        let rebound = KeyBinding(keyCode: UInt16(kVK_F8), modifiers: [.option])
        keys.set(rebound, for: .toggleTypeHistoryVisibility)
        _ = router.handle(originalTypeKey)
        #expect(!fixture.state.historyHidingOptionsOpen)
        let typeKey = try #require(aKeyEvent(Int(rebound.keyCode), rebound.modifiers))
        #expect(router.handle(typeKey))
        #expect(fixture.state.historyHidingOptions == .typeOrSource)
        fixture.state.historyHidingOptions = nil
        fixture.state.setHistoryHiding(
            HistoryHidingRule(cutoff: fixture.clock.now(), categories: [.text]), actions: fixture.actions)
        #expect(fixture.state.isTypeHistoryHidden)
        #expect(router.handle(typeKey))
        #expect(!fixture.state.isTypeHistoryHidden && !fixture.state.historyHidingOptionsOpen)

        fixture.state.isPinnedWorkspace = true
        _ = router.handle(hideKey)
        _ = router.handle(typeKey)
        #expect(!fixture.state.isHistoryHidden && !fixture.state.historyHidingOptionsOpen)
        #expect(fixture.disk.saveCount == 0 && fixture.board.written.isEmpty)
    }

    @Test(arguments: [false, true])
    func hiding_and_restoring_keep_the_card_rail_and_toolbar_in_place(inPrivacy: Bool) async throws {
        _ = NSApplication.shared
        let fixture = Fixture()
        fixture.state.configureCards(side: 250)
        fixture.state.configureFilterTags(scale: 1.5)
        fixture.state.setPrivacyPermissions(allowSearch: true, showSourceApps: true, allowFiltering: true)
        fixture.state.setPrivacy(inPrivacy)
        let host = NSHostingView(rootView: HistoryPanelView(store: fixture.state, actions: fixture.actions))
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: 0, width: 900, height: 510),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.contentView = nil; window.close() }

        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

        func frames(searchableCount: Int) async throws -> (rail: NSRect, search: NSRect) {
            try await Task.sleep(for: .milliseconds(300))
            host.layoutSubtreeIfNeeded()
            let views = descendants(host)
            let rail = try #require(
                views.compactMap { $0 as? NSScrollView }.max { $0.frame.height < $1.frame.height })
            let search = try #require(views.compactMap { $0 as? NSTextField }.first)
            #expect(
                (search.placeholderAttributedString?.string ?? search.placeholderString)
                    == localized("Search in \(searchableCount) items"))
            return (rail.convert(rail.bounds, to: host), search.convert(search.bounds, to: host))
        }

        let visible = try await frames(searchableCount: 2)
        #expect(visible.rail.height >= fixture.state.cardSide)
        for hideByType in [false, true] {
            if hideByType {
                fixture.state.setHistoryHiding(
                    HistoryHidingRule(cutoff: fixture.clock.now(), categories: [.text]), actions: fixture.actions)
            } else {
                fixture.state.toggleHistoryVisibility(actions: fixture.actions)
            }
            let hidden = try await frames(searchableCount: 0)
            #expect((inPrivacy ? fixture.state.protectedCardCount : fixture.state.state.cards.count) == 0)
            #expect(hidden.rail == visible.rail)
            #expect(abs(hidden.search.midY - visible.search.midY) < 1)
            if !inPrivacy {
                let slab = try #require(
                    descendants(host).compactMap { $0 as? BackdropView }.first {
                        $0.bounds.width > 500 && $0.bounds.height > 100
                    })
                #expect(abs(slab.bounds.height - fixture.state.zoomedCardSide) < 1)
            }

            if hideByType {
                fixture.state.clearTypeHistoryHiding(actions: fixture.actions)
            } else {
                fixture.state.toggleHistoryVisibility(actions: fixture.actions)
            }
            let restored = try await frames(searchableCount: 2)
            #expect((inPrivacy ? fixture.state.protectedCardCount : fixture.state.state.cards.count) == 2)
            #expect(restored.rail == visible.rail)
            #expect(abs(restored.search.midY - visible.search.midY) < 1)
        }
    }

    @Test(arguments: ["en", "it", "fr", "de", "zh-Hans", "zh-Hant", "ja"])
    func localized_search_fits_its_prompt_and_keeps_the_hiding_buttons_outside(language: String) async throws {
        _ = NSApplication.shared
        let previousLanguage = AppLocalization.language
        AppLocalization.language = language
        defer { AppLocalization.language = previousLanguage }
        let fixture = Fixture()
        let host = NSHostingView(
            rootView: HistoryPanelView(store: fixture.state, actions: fixture.actions).transaction {
                $0.disablesAnimations = true
            })
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: 0, width: 820, height: 430),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.contentView = nil; window.close() }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        for protected in [false, true] {
            fixture.state.setPrivacyPermissions(allowSearch: true, showSourceApps: false)
            fixture.state.setPrivacy(protected)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(350))
            host.layoutSubtreeIfNeeded()
            let surfaces = descendants(host).compactMap { $0 as? BackdropView }.map { $0.convert($0.bounds, to: host) }
            let buttons = surfaces.filter { abs($0.height - 36) < 0.5 }.sorted { $0.minX < $1.minX }
            #expect(buttons.count == (protected ? 2 : 3), "privacy=\(protected), surfaces=\(surfaces)")
            let lastButtons = Array(buttons.suffix(2))
            let hide = try #require(lastButtons.first)
            let byType = try #require(lastButtons.last)
            #expect(hide.maxX < byType.minX)
            #expect(fixture.state.canClearHistory == !protected)
            #expect(fixture.state.canToggleHistoryVisibility)
            let field = try #require(descendants(host).compactMap { $0 as? NSTextField }.first)
            let search = field.convert(field.bounds, to: host)
            let prompt = localized("Search in \(2) items")
            let promptWidth = prompt.size(withAttributes: [.font: NSFont.systemFont(ofSize: 14)]).width
            #expect(search.width > promptWidth, "\(language), privacy=\(protected), search=\(search.width)")
            if language == "fr", !protected {
                #expect(abs(search.midY - hide.midY) > 36)
            }
            #expect(byType.maxX <= host.bounds.maxX - PanelLayout.contentMargin)
            #expect(!surfaces.contains { $0.intersects(search) })
            if protected {
                let rail = try #require(
                    descendants(host).compactMap { $0 as? NSScrollView }.first {
                        ($0.documentView?.frame.height ?? 0) >= 200
                    })
                #expect(rail.contentView.bounds.height >= 200)
            }
            if let output = ProcessInfo.processInfo.environment["WHISK_UI_ARTIFACTS"] {
                let directory = URL(fileURLWithPath: output)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let mode = protected ? "privacy" : "normal"
                let file = directory.appendingPathComponent("history-toolbar-\(language)-\(mode).png")
                try bitmap.representation(using: .png, properties: [:])?.write(to: file)
            }
        }
    }
}

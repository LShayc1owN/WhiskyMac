// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation
import Testing

@testable import Whisk

@MainActor
@Suite struct FilterInteractionBehaviour {
    @Test func trigger_defaults_to_click_and_persists_with_invalid_fallback() throws {
        let sandbox = try IsolatedDefaults()
        let settings = GeneralSettingsStore(defaults: sandbox.defaults)
        #expect(settings.appFilterTrigger == .click)
        settings.appFilterTrigger = .hover
        #expect(GeneralSettingsStore(defaults: sandbox.defaults).appFilterTrigger == .hover)
        #expect(AppFilterTrigger.allCases.allSatisfy { !$0.label.isEmpty })
        sandbox.defaults.set("unknown", forKey: "appFilterTrigger")
        #expect(GeneralSettingsStore(defaults: sandbox.defaults).appFilterTrigger == .click)
    }

    @Test func hover_dwell_only_runs_the_latest_uncancelled_callback() throws {
        var pending: [DispatchWorkItem] = []
        var delays: [TimeInterval] = []
        var selections: [String] = []
        let hover = FilterHoverActivation { delay, work in
            delays.append(delay)
            pending.append(work)
        }
        hover.enter { selections.append("first") }
        hover.cancel()
        pending[0].perform()
        #expect(selections.isEmpty)
        hover.enter { selections.append("second") }
        hover.enter { selections.append("third") }
        pending[1].perform()
        pending[2].perform()
        #expect(selections == ["third"])
        #expect(delays == [0.25, 0.25, 0.25])
        var released: FilterHoverActivation? = FilterHoverActivation { _, work in pending.append(work) }
        released?.enter { selections.append("released") }
        released = nil
        pending[3].perform()
        #expect(selections == ["third"])
    }

    @Test func all_clears_every_filter_but_preserves_the_query_and_never_writes() {
        let disk = InMemoryHistoryStore()
        disk.stored = [
            anItem(.text("match one"), from: "One", bundle: "test.one", pinned: true),
            anItem(.text("match two"), from: "Two", bundle: "test.two"),
            anItem(.text("other"), from: "Two", bundle: "test.two"),
        ]
        let board = ScriptedPasteboard()
        let spy = ClipboardControllerBehaviour.StateSpy()
        let controller = ClipboardController(pasteboard: board, store: disk, clock: FakeClock(), present: spy.record)
        #expect(spy.last.filters.all.first?.isActive == true)
        #expect(
            (spy.last.filters.pinned + spy.last.filters.apps + spy.last.filters.kinds + spy.last.filters.tags)
                .allSatisfy { !$0.isActive })
        controller.search("match")
        controller.toggleSourceFilter("test.one")
        controller.toggleCategoryFilter("text")
        controller.toggleCategoryFilter(pinnedChipID)
        #expect(spy.last.cards.count == 1)
        #expect(spy.last.filters.all.first?.isActive == false)
        controller.focusCategoryChip(allFiltersChipID)
        #expect(!controller.activateFocused())
        #expect(spy.last.filters.focusedChipID == allFiltersChipID)
        #expect(spy.last.filters.all.first?.isActive == true)
        #expect(
            (spy.last.filters.pinned + spy.last.filters.apps + spy.last.filters.kinds + spy.last.filters.tags)
                .allSatisfy { !$0.isActive })
        #expect(spy.last.query == "match")
        #expect(spy.last.cards.count == 2)
        #expect(board.written.isEmpty)
        #expect(disk.stored.count == 3)
    }

    @Test func hover_routing_flushes_search_and_is_blocked_by_privacy() {
        let disk = InMemoryHistoryStore()
        disk.stored = [
            anItem(.text("match one"), from: "One", bundle: "test.one"),
            anItem(.text("match two"), from: "Two", bundle: "test.two"),
            anItem(.image(Data([0])), from: "Two", bundle: "test.two"),
        ]
        let spy = ClipboardControllerBehaviour.StateSpy()
        let controller = ClipboardController(
            pasteboard: ScriptedPasteboard(), store: disk, clock: FakeClock(), present: spy.record)
        let clock = HandCrankedScheduler()
        var protected = false
        let actions = PanelWiring.actions(
            for: controller, searchDebounce: Debouncer(delay: 0.18, scheduler: clock.schedule),
            hidePanel: {}, paste: {}, dragBegan: {},
            system: .init(
                openLink: { _ in }, revealFiles: { _ in }, saveToDisk: { _ in },
                excludeSource: { _, _ in }, beginEditing: { _ in }, openPasteboardSettings: {})
        ).guarded(by: { protected })
        actions.search("match")
        actions.selectSourceFilter("test.two")
        #expect(spy.last.query == "match")
        #expect(spy.last.cards.map(\.sourceLabel) == ["Two"])
        protected = true
        actions.selectSourceFilter("test.one")
        #expect(spy.last.cards.map(\.sourceLabel) == ["Two"])
        actions.selectCategoryFilter("image")
        #expect(spy.last.cards.map(\.sourceLabel) == ["Two"])
        protected = false
        actions.search("")
        actions.selectCategoryFilter("image")
        #expect(spy.last.query.isEmpty)
        #expect(spy.last.cards.count == 1)
        #expect(spy.last.cards.first?.id == disk.stored[2].id)
    }

    @Test func hover_selects_one_source_and_repeated_hover_never_toggles_it_off() {
        let disk = InMemoryHistoryStore()
        disk.stored = [
            anItem(.text("one"), from: "One", bundle: "test.one"),
            anItem(.text("two"), from: "Two", bundle: "test.two"),
        ]
        let spy = ClipboardControllerBehaviour.StateSpy()
        let controller = ClipboardController(
            pasteboard: ScriptedPasteboard(), store: disk, clock: FakeClock(), present: spy.record)
        controller.toggleSourceFilter("test.one")
        controller.selectSourceFilter("test.two")
        #expect(spy.last.cards.map(\.sourceLabel) == ["Two"])
        #expect(spy.last.filters.apps.filter(\.isActive).map(\.id) == ["test.two"])
        let count = spy.states.count
        controller.selectSourceFilter("test.two")
        controller.selectSourceFilter("stale.or.hidden")
        #expect(spy.states.count == count)
        controller.toggleSourceFilter("test.two")
        #expect(spy.last.cards.count == 2)
    }

    @Test func category_hover_selects_without_toggling_and_click_still_combines_filters() {
        let disk = InMemoryHistoryStore()
        disk.stored = [
            anItem(.text("Text"), from: "App", bundle: "test.app", pinned: true),
            anItem(.image(Data([0])), from: "App", bundle: "test.app"),
        ]
        let board = ScriptedPasteboard()
        let spy = ClipboardControllerBehaviour.StateSpy()
        let controller = ClipboardController(
            pasteboard: board, store: disk, clock: FakeClock(), present: spy.record)
        controller.selectCategoryFilter("image")
        #expect(spy.last.cards.count == 1)
        #expect(spy.last.filters.kinds.filter(\.isActive).map(\.id) == ["image"])
        let count = spy.states.count
        controller.selectCategoryFilter("image")
        controller.selectCategoryFilter("stale.or.hidden")
        controller.selectCategoryFilter("test.app")
        #expect(spy.states.count == count)
        controller.toggleCategoryFilter("text")
        #expect(spy.last.cards.count == 2)
        controller.selectCategoryFilter("text")
        #expect(spy.last.cards.count == 1)
        #expect(spy.last.filters.kinds.filter(\.isActive).map(\.id) == ["text"])
        controller.selectCategoryFilter(pinnedChipID)
        controller.selectCategoryFilter(pinnedChipID)
        #expect(spy.last.filters.pinned.first?.isActive == true)
        controller.selectCategoryFilter(allFiltersChipID)
        #expect(spy.last.cards.count == 2 && spy.last.filters.all.first?.isActive == true)
        #expect(board.written.isEmpty && disk.saveCount == 0)
    }
}

// WhiskyMac: modified or added 2026-11-19 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Testing

@testable import Whisk

@MainActor
@Suite(.serialized) struct HandoffFilters {
    private final class Fixture {
        let board = ScriptedPasteboard()
        let disk = InMemoryHistoryStore()
        let clock = FakeClock()
        let state = HistoryViewStateStore()
        let remoteText: ClipboardItem
        let remoteImage: ClipboardItem
        let local: ClipboardItem
        let controller: ClipboardController<ScriptedPasteboard, FakeClock, InMemoryHistoryStore, RecordingLogger>

        init() throws {
            let source = try #require(SourceApp(name: nil, origin: .handoffMarker))
            remoteText = ClipboardItem(
                id: UUID(), payload: .text("REMOTE TEXT"), source: source,
                copiedAt: clock.now().addingTimeInterval(-2), isPinned: false)
            remoteImage = ClipboardItem(
                id: UUID(), payload: .image(Data([0])), source: source,
                copiedAt: clock.now().addingTimeInterval(-1), isPinned: true,
                pinnedMetadata: PinnedMetadata(tags: [.red]))
            local = anItem(.text("LOCAL TEXT"), from: "Editor", bundle: "test.editor", at: clock.now())
            disk.stored = [remoteImage, remoteText, local]
            let state = state
            controller = ClipboardController(pasteboard: board, store: disk, clock: clock) { state.update($0) }
            state.setPanelVisible(true)
            state.protectedFilter = { [weak controller] action in
                switch action {
                case .toggleApp(let key): controller?.toggleSourceFilter(key)
                case .selectApp(let key): controller?.selectSourceFilter(key)
                case .toggleKind(let key): controller?.toggleCategoryFilter(key)
                case .selectKind(let key): controller?.selectCategoryFilter(key)
                case .reset: controller?.toggleCategoryFilter(allFiltersChipID)
                }
            }
        }

        var ids: Set<UUID> { Set(state.state.cards.map(\.id)) }
    }

    @Test func independent_origin_precedes_apps_and_uses_the_requested_symbol() throws {
        let f = try Fixture()
        let source = try #require(f.local.source)
        let row = ChipEntry.row(hasPinned: true, sources: [source], categories: [.text], hasHandoff: true)
        #expect(row == [.all, .pinned, .handoff, .app(source), .category(.text)])
        #expect(ChipEntry.handoff.group == .origins)
        #expect(f.state.state.filters.apps.map(\.id) == [source.filterKey])
        let chip = try #require(f.state.state.filters.origins.first)
        #expect(chip.id == handoffChipID && chip.icon == .symbol("macbook.and.iphone"))
        #expect(chip.label == localized("Handoff"))
        #expect(NSImage(systemSymbolName: "macbook.and.iphone", accessibilityDescription: nil) != nil)
        let normalized = ChipEntry.row(hasPinned: false, sources: [try #require(f.remoteText.source)], categories: [])
        #expect(normalized == [.all, .handoff])
    }

    @Test func click_hover_and_all_switch_between_local_apps_and_handoff_without_writes() throws {
        let f = try Fixture()
        f.controller.toggleSourceFilter("test.editor")
        #expect(f.ids == [f.local.id])
        f.controller.toggleCategoryFilter(handoffChipID)
        #expect(f.ids == [f.remoteText.id, f.remoteImage.id])
        #expect(f.state.state.filters.apps.allSatisfy { !$0.isActive })
        #expect(f.state.state.filters.all.first?.isActive == false)
        f.controller.selectCategoryFilter(handoffChipID)
        #expect(f.ids == [f.remoteText.id, f.remoteImage.id])
        f.controller.selectSourceFilter("test.editor")
        #expect(f.ids == [f.local.id])
        #expect(f.state.state.filters.origins.first?.isActive == false)
        f.controller.toggleSourceFilter(handoffChipID)  // An old app callback cannot select this origin.
        #expect(f.ids == [f.local.id])
        f.controller.selectCategoryFilter(handoffChipID)
        f.controller.toggleCategoryFilter(allFiltersChipID)
        #expect(f.ids == [f.local.id, f.remoteText.id, f.remoteImage.id])
        #expect(f.state.state.filters.all.first?.isActive == true)
        #expect(f.disk.saveCount == 0 && f.board.written.isEmpty)
    }

    @Test func handoff_combines_with_type_pin_and_tags_and_resets_on_panel_reopen() throws {
        let f = try Fixture()
        f.controller.selectCategoryFilter(handoffChipID)
        f.controller.toggleCategoryFilter("text")
        #expect(f.ids == [f.remoteText.id])
        f.controller.toggleCategoryFilter("text")
        f.controller.toggleCategoryFilter(PinTagColor.red.filterKey)
        #expect(f.ids == [f.remoteImage.id])
        f.controller.toggleCategoryFilter(PinTagColor.red.filterKey)
        f.controller.toggleCategoryFilter(pinnedChipID)
        #expect(f.ids == [f.remoteImage.id])
        f.controller.panelWillShow()
        #expect(f.ids == [f.local.id, f.remoteText.id, f.remoteImage.id])
        #expect(f.state.state.filters.origins.first?.isActive == false)
        let query = FilterHistory()(
            History(items: f.disk.stored),
            filter: HistoryFilter(query: "REMOTE", categories: [.text], handoffOnly: true))
        #expect(query == [f.remoteText])
    }

    @Test func keyboard_focus_has_an_independent_origin_group() throws {
        let f = try Fixture()
        f.controller.focusCategoryChip(handoffChipID)
        #expect(f.state.state.filters.focusedChipID == handoffChipID)
        #expect(!f.controller.activateFocused())
        #expect(f.ids == [f.remoteText.id, f.remoteImage.id])
        f.controller.switchChipGroup()
        #expect(f.state.state.filters.apps.contains { $0.isFocused })
        #expect(f.board.written.isEmpty)
    }

    @Test func origin_only_hiding_respects_cutoff_and_can_be_reversed_without_deleting_or_saving() throws {
        let f = try Fixture()
        let saved = f.disk.stored
        var draft = HistoryHidingDraft()
        draft.includesHandoff = true
        let rule = try #require(draft.rule(includingTypes: true, now: f.clock.now()))
        #expect(rule.categories == [] && rule.includesHandoff)
        var actions = PanelActionSpy().actions
        actions.setHistoryHiding = { f.controller.setHistoryHiding($0) }
        actions.clearTypeHistoryHiding = { f.controller.clearTypeHistoryHiding() }
        f.controller.selectCategoryFilter(handoffChipID)
        f.state.setHistoryHiding(rule, actions: actions)
        #expect(f.ids == [f.local.id] && f.state.state.filters.origins.isEmpty)
        #expect(f.state.isTypeHistoryHidden)
        f.controller.toggleCategoryFilter(handoffChipID)
        #expect(f.ids == [f.local.id])
        let newer = f.remoteText.copied(at: f.clock.now().addingTimeInterval(1))
        #expect(!rule.hides(newer))
        #expect(rule.hides(f.remoteText) && !rule.hides(f.local))
        f.state.clearTypeHistoryHiding(actions: actions)
        #expect(f.ids == [f.local.id, f.remoteText.id, f.remoteImage.id])
        #expect(f.disk.stored == saved && f.disk.saveCount == 0 && f.board.written.isEmpty)
        let union = HistoryHidingRule(cutoff: f.clock.now(), categories: [.text], includesHandoff: true)
        #expect(saved.allSatisfy(union.hides))
    }

    @Test func privacy_origin_permission_is_independent_and_revokes_stale_click_and_hover_actions() throws {
        let f = try Fixture()
        f.state.setPrivacy(true)
        #expect(f.state.protectedFilters.origins.isEmpty)
        f.state.setPrivacyPermissions(allowSearch: false, showSourceApps: false, allowHandoffFiltering: true)
        #expect(f.state.protectedFilters.origins.count == 1)
        #expect(f.state.protectedFilters.apps.isEmpty && f.state.protectedFilters.kinds.isEmpty)
        f.state.filterWhileProtected(.selectKind(handoffChipID))
        #expect(Set(f.state.protectedCardIDs) == [f.remoteText.id, f.remoteImage.id])
        #expect(f.state.state == .empty && f.state.previewItems.isEmpty)
        f.state.setPrivacyPermissions(allowSearch: false, showSourceApps: false, allowAppFiltering: true)
        #expect(f.state.protectedFilters.origins.isEmpty && f.state.protectedCardIDs.count == 3)
        f.state.filterWhileProtected(.toggleKind(handoffChipID))
        f.state.filterWhileProtected(.selectKind(handoffChipID))
        #expect(f.state.protectedCardIDs.count == 3)
        #expect(f.disk.saveCount == 0 && f.board.written.isEmpty)
    }

    @Test func privacy_handoff_choice_persists_separately_from_apps() throws {
        let defaults = try IsolatedDefaults()
        let privacy = PrivacyController(defaults: defaults.defaults)
        #expect(privacy.allowHandoffFilteringWhileProtected)
        privacy.allowAppFilteringWhileProtected = false
        #expect(PrivacyController(defaults: defaults.defaults).allowHandoffFilteringWhileProtected)
        privacy.allowHandoffFilteringWhileProtected = true
        let reopened = PrivacyController(defaults: defaults.defaults)
        #expect(!reopened.allowAppFilteringWhileProtected && reopened.allowHandoffFilteringWhileProtected)
        reopened.allowHandoffFilteringWhileProtected = false
        #expect(!PrivacyController(defaults: defaults.defaults).allowHandoffFilteringWhileProtected)
        let previouslyDisabled = try IsolatedDefaults()
        previouslyDisabled.defaults.set(false, forKey: "privacyAllowAppFiltering")
        #expect(!PrivacyController(defaults: previouslyDisabled.defaults).allowHandoffFilteringWhileProtected)
    }
}

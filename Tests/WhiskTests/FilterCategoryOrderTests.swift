// WhiskyMac: added 2026-11-25 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import CoreTransferable
import SwiftUI
import Testing

@testable import Whisk

@MainActor
@Suite struct FilterCategoryOrderTests {
    @Test func preferences_recover_missing_categories_and_persist_reorder_and_reset() throws {
        let fixture = try IsolatedDefaults()
        let defaults = fixture.defaults
        #expect(GeneralSettingsStore(defaults: defaults).filterCategoryOrder.categories == ContentCategory.allCases)

        defaults.set(["image", "unknown", "text", "image"], forKey: "filterCategoryOrder")
        let settings = GeneralSettingsStore(defaults: defaults)
        #expect(Array(settings.filterCategoryOrder.categories.prefix(2)) == [.image, .text])
        #expect(Set(settings.filterCategoryOrder.categories) == Set(ContentCategory.allCases))
        #expect(settings.filterCategoryOrder.categories.count == ContentCategory.allCases.count)

        let moved = settings.filterCategoryOrder.moving(.image, to: .files).moving(.code, to: .text)
        #expect(moved.categories.last == .image)
        #expect(Array(moved.categories.prefix(2)) == [.code, .text])
        #expect(moved.moving(.code, to: .code) == moved)
        settings.setFilterCategoryOrder(moved)
        #expect(GeneralSettingsStore(defaults: defaults).filterCategoryOrder == moved)
        settings.setFilterCategoryOrder(.standard)
        #expect(GeneralSettingsStore(defaults: defaults).filterCategoryOrder == .standard)
    }

    @Test func live_order_keeps_non_category_groups_and_tracks_the_keyboard_by_identity() {
        let disk = InMemoryHistoryStore()
        let clock = FakeClock()
        let source = SourceApp(name: nil, origin: .handoffMarker)
        disk.stored = [
            anItem(.text("let count = 2"), from: "Editor", bundle: "fixture.editor"),
            anItem(.text("note"), from: "Notes", bundle: "fixture.notes", pinned: true)
                .withPinnedMetadata(PinnedMetadata(tags: [.red])),
            ClipboardItem(
                id: UUID(), payload: .image(Data([1])), source: source, copiedAt: clock.now(), isPinned: false),
        ]
        let state = HistoryViewStateStore()
        let initialOrder = FilterCategoryOrder(savedIDs: ["files", "image", "code"])
        let controller = ClipboardController(
            pasteboard: ScriptedPasteboard(), store: disk, clock: clock,
            filterCategoryOrder: initialOrder, logger: RecordingLogger(), present: state.update)

        let original = state.state.filters
        #expect(original.kinds.map(\.id) == ["image", "code", "text"])
        #expect(original.origins.map(\.id) == [handoffChipID])
        #expect(original.apps.map(\.id) == ["fixture.editor", "fixture.notes"])
        controller.focusCategoryChip("text")
        controller.setFilterCategoryOrder(FilterCategoryOrder(savedIDs: ["code", "text", "image"]))
        let updated = state.state.filters
        #expect(updated.kinds.map(\.id) == ["code", "text", "image"])
        #expect(updated.focusedChipID == "text")
        #expect(updated.all == original.all && updated.pinned == original.pinned)
        #expect(updated.origins == original.origins && updated.apps == original.apps && updated.tags == original.tags)

        controller.navigate(.right)
        #expect(state.state.filters.focusedChipID == "image")
        controller.toggleCategoryFilter("text")
        controller.setFilterCategoryOrder(initialOrder)
        #expect(state.state.filters.activeChipIDs == ["text"])
        #expect(state.state.cards.count == 2)
        #expect(disk.saveCount == 0)

        state.setPrivacyPermissions(allowSearch: false, showSourceApps: false, allowFiltering: true)
        state.setPrivacy(true)
        #expect(state.protectedFilters.kinds.map(\.id) == ["image", "code", "text"])
    }

    @Test func the_order_editor_can_render_empty_history_and_is_discoverable_in_settings_search() throws {
        _ = NSApplication.shared
        let fixture = try IsolatedDefaults()
        let settings = GeneralSettingsStore(defaults: fixture.defaults)
        let host = NSHostingView(
            rootView: MacOS15FilterCategoryOrderEditor(settings: settings, previewScheme: .dark)
                .environment(\.colorScheme, .light))
        host.frame.size = CGSize(width: 480, height: 380)
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.height > 0)
        settings.setFilterCategoryOrder(FilterCategoryOrder(savedIDs: ["files", "path"]))
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.height > 0)

        let entry = try #require(
            SettingsSearchIndex.entries(context: SettingsSearchContext()).first { $0.id == "filterCategoryOrder" })
        #expect(entry.section == .filterTags)
    }

    @Test func same_process_drag_round_trips_the_category() async throws {
        guard #available(macOS 15.2, *) else { return }
        let types = FilterCategoryDrag.exportedContentTypes(visibility: .ownProcess)
        let type = try #require(types.first)
        let data = try await FilterCategoryDrag(.path).exported(as: type)
        let dropped = try await FilterCategoryDrag(importing: data, contentType: type)
        #expect(dropped.category == .path)
    }
}

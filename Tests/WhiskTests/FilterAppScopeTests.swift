// WhiskyMac: modified or added 2026-11-17 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Combine
import Foundation
import Testing

@testable import Whisk

@Suite struct FilterAppScopeTests {
    @MainActor
    @Test func privacy_scope_follows_app_filter_permission_independently_of_card_source_labels() {
        let state = HistoryViewStateStore()
        let item = anItem(.text("Hidden body"), from: "App", bundle: "synthetic.app")
        state.update(HistoryPresenter().present(items: [item], query: "", now: item.copiedAt))
        state.setPrivacy(true)
        state.setPrivacyPermissions(allowSearch: false, showSourceApps: false, allowAppFiltering: true)
        #expect(state.protectedSourceKeys(in: 0..<10) == ["synthetic.app"])
        #expect(state.protectedSourceLabel(for: item.id) == nil)
        state.setPrivacyPermissions(allowSearch: false, showSourceApps: true, allowAppFiltering: false)
        #expect(state.protectedSourceKeys(in: 0..<10).isEmpty)
        #expect(state.protectedSourceLabel(for: item.id) == "App")
        state.setPrivacy(false)
        #expect(state.protectedSourceKeys(in: 0..<10).isEmpty)
    }

    private func chip(_ id: String, active: Bool = false, focused: Bool = false) -> FilterChip {
        FilterChip(
            id: id, label: id, sourceBundleID: nil, accessibilityLabel: id,
            isActive: active, isFocused: focused)
    }

    @Test func collapsed_apps_include_visible_sources_active_filters_and_keyboard_focus_in_original_order() {
        let apps = [chip("offscreen"), chip("visible"), chip("active", active: true), chip("focus", focused: true)]
        #expect(
            FilterAppScope.apps(apps, visibleKeys: ["visible"], expanded: false).map(\.id)
                == ["visible", "active", "focus"])
        #expect(FilterAppScope.apps(apps, visibleKeys: [], expanded: false).map(\.id) == ["active", "focus"])
        #expect(FilterAppScope.apps(apps, visibleKeys: ["visible"], expanded: true) == apps)
        #expect(FilterAppScope.apps(apps, visibleKeys: nil, expanded: false) == apps)
    }

    @Test func viewport_includes_partial_cards_but_never_the_preload_buffer_or_gaps() {
        func range(_ start: CGFloat, _ width: CGFloat) -> Range<Int> {
            FilterAppScope.visibleRange(count: 100, side: 210, stride: 224, start: start, width: width)
        }
        #expect(range(-16, 464) == 0..<2)
        #expect(range(209, 16) == 0..<2)
        #expect(range(210, 14).isEmpty)
        #expect(range(225, 448) == 1..<4)
        #expect(range(10_000_000, 400).isEmpty)
        #expect(range(-1000, 50).isEmpty)
        #expect(range(.nan, 600).isEmpty)
        #expect(range(0, 0).isEmpty)
    }

    @Test func same_sources_publish_only_once_even_when_the_card_viewport_keeps_moving() {
        let scope = FilterAppScope(visibleSourceKeys: [])
        var updates = 0
        let observation = scope.$visibleSourceKeys.dropFirst().sink { _ in updates += 1 }
        scope.update(["app-a", "app-b"])
        scope.update(["app-b", "app-a"])
        scope.update(["app-a", "app-b"])
        #expect(updates == 1)
        scope.update(["app-b"])
        #expect(updates == 2)
        withExtendedLifetime(observation) {}
    }
}

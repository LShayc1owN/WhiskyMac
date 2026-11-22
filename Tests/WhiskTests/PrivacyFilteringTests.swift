// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Carbon.HIToolbox
import SwiftUI
import Testing

@testable import Whisk

@MainActor
@Suite struct PrivacyFiltering {
    @Test func filtering_is_independently_opt_in_and_persists() throws {
        let sandbox = try IsolatedDefaults()
        let privacy = PrivacyController(defaults: sandbox.defaults)
        #expect(!privacy.allowFilteringWhileProtected)
        var callbacks = 0
        privacy.displayPermissionsChanged = { callbacks += 1 }
        privacy.allowFilteringWhileProtected = true
        let restored = PrivacyController(defaults: sandbox.defaults)
        #expect(restored.allowFilteringWhileProtected)
        #expect(!restored.allowSearchWhileProtected && !restored.showSourceAppsWhileProtected)
        privacy.allowFilteringWhileProtected = false
        #expect(!PrivacyController(defaults: sandbox.defaults).allowFilteringWhileProtected)
        #expect(callbacks == 2)
    }

    @Test func app_filtering_defaults_on_and_persists_independently_of_other_permissions() throws {
        let sandbox = try IsolatedDefaults()
        let privacy = PrivacyController(defaults: sandbox.defaults)
        #expect(privacy.allowAppFilteringWhileProtected)
        #expect(!privacy.allowFilteringWhileProtected && !privacy.showSourceAppsWhileProtected)
        var callbacks = 0
        privacy.displayPermissionsChanged = { callbacks += 1 }
        privacy.allowAppFilteringWhileProtected = false
        #expect(!PrivacyController(defaults: sandbox.defaults).allowAppFilteringWhileProtected)
        privacy.allowAppFilteringWhileProtected = true
        let restored = PrivacyController(defaults: sandbox.defaults)
        #expect(restored.allowAppFilteringWhileProtected)
        #expect(!restored.allowFilteringWhileProtected && !restored.showSourceAppsWhileProtected)
        #expect(!restored.allowSearchWhileProtected)
        #expect(callbacks == 2)
    }

    @Test func filtering_masks_content_hides_apps_unless_allowed_and_revokes_stale_actions() {
        let state = HistoryViewStateStore()
        let disk = InMemoryHistoryStore()
        let board = ScriptedPasteboard()
        let one = anItem(.text("BODY CANARY"), from: "SOURCE ONE", bundle: "test.one", pinned: true)
        let two = anItem(.image(Data([0])), from: "SOURCE TWO", bundle: "test.two")
        disk.stored = [one, two]
        let controller = ClipboardController(
            pasteboard: board, store: disk, clock: FakeClock(), present: { state.update($0) })
        state.protectedFilter = { action in
            switch action {
            case .toggleApp(let key): controller.toggleSourceFilter(key)
            case .selectApp(let key): controller.selectSourceFilter(key)
            case .selectKind(let key): controller.selectCategoryFilter(key)
            case .toggleKind(let key): controller.toggleCategoryFilter(key)
            case .reset: controller.toggleCategoryFilter(allFiltersChipID)
            }
        }
        state.setPrivacy(true)
        state.setPanelVisible(true)
        #expect(state.protectedFilters.isEmpty)
        state.filterWhileProtected(.toggleKind("image"))
        #expect(state.protectedCardIDs.count == 2)
        state.filterWhileProtected(.selectKind("image"))
        #expect(state.protectedCardIDs.count == 2)
        state.setPrivacyPermissions(allowSearch: false, showSourceApps: false, allowFiltering: true)
        #expect(state.protectedFilters.apps.isEmpty && !state.protectedFilters.kinds.isEmpty)
        state.filterWhileProtected(.selectApp("test.two"))
        #expect(state.protectedCardIDs.count == 2)
        state.filterWhileProtected(.selectKind("image"))
        #expect(state.protectedCardIDs == [two.id])
        state.filterWhileProtected(.selectKind("image"))
        #expect(state.protectedCardIDs == [two.id])
        state.filterWhileProtected(.toggleKind(allFiltersChipID))
        state.filterWhileProtected(.toggleKind(pinnedChipID))
        #expect(state.protectedCardIDs == [one.id])
        state.filterWhileProtected(.toggleKind(allFiltersChipID))
        state.setPrivacyPermissions(
            allowSearch: false, showSourceApps: true, allowFiltering: true, allowAppFiltering: true)
        #expect(state.protectedFilters.apps.count == 2)
        state.filterWhileProtected(.selectApp("test.two"))
        #expect(state.protectedCardIDs == [two.id])
        state.setPrivacyPermissions(allowSearch: false, showSourceApps: false, allowFiltering: true)
        #expect(state.protectedCardIDs.count == 2 && state.protectedFilters.apps.isEmpty)
        state.filterWhileProtected(.toggleApp("test.two"))
        #expect(state.protectedCardIDs.count == 2)
        state.filterWhileProtected(.toggleKind("image"))
        state.setPrivacyPermissions(allowSearch: false, showSourceApps: false)
        state.filterWhileProtected(.toggleKind("image"))
        state.filterWhileProtected(.selectKind("image"))
        #expect(state.protectedFilters.isEmpty && state.protectedCardIDs.count == 2)
        state.setPrivacyPermissions(
            allowSearch: false, showSourceApps: true, allowFiltering: true, allowAppFiltering: true)
        state.filterWhileProtected(.toggleApp("test.two"))
        state.panelDidClose()
        #expect(state.protectedCardIDs.count == 2)
        state.filterWhileProtected(.toggleApp("test.two"))
        #expect(state.protectedCardIDs.count == 2)
        state.setPanelVisible(true)
        state.setSpotlightAllowed(false)
        state.privacyInteractions.hover = .preview
        state.detailSource = { _ in
            Issue.record("Unexpected detail read"); return one
        }
        #expect(state.spotlightPayload(for: one.id) == nil)
        #expect(state.state == .empty && state.previewItems.isEmpty)
        #expect(board.written.isEmpty && disk.saveCount == 0)
    }

    @Test func app_only_filtering_works_without_card_source_labels_and_revocation_rejects_stale_actions() throws {
        for automatic in [false, true] {
            let sandbox = try IsolatedDefaults()
            let privacy = PrivacyController(defaults: sandbox.defaults, schedulesTimer: false)
            if automatic {
                privacy.setAutomaticEnabled(true)
                privacy.receive([SharingReport(state: .active, reason: .toolbarPresent)])
            } else {
                privacy.setProtected(true)
            }
            let state = HistoryViewStateStore()
            let disk = InMemoryHistoryStore()
            let board = ScriptedPasteboard()
            let one = anItem(.text("SECRET TEXT"), from: "SOURCE ONE", bundle: "test.one")
            let two = anItem(.image(Data([0])), from: "SOURCE TWO", bundle: "test.two")
            disk.stored = [one, two]
            let controller = ClipboardController(
                pasteboard: board, store: disk, clock: FakeClock(), present: { state.update($0) })
            state.protectedFilter = { action in
                switch action {
                case .toggleApp(let id): controller.toggleSourceFilter(id)
                case .selectApp(let id): controller.selectSourceFilter(id)
                case .selectKind(let id): controller.selectCategoryFilter(id)
                case .toggleKind(let id): controller.toggleCategoryFilter(id)
                case .reset: controller.toggleCategoryFilter(allFiltersChipID)
                }
            }
            state.setPrivacyPermissions(
                allowSearch: false, showSourceApps: false, allowAppFiltering: privacy.allowAppFilteringWhileProtected)
            state.setPrivacy(privacy.isProtected)
            state.setSpotlightAllowed(privacy.allowsSpotlight)
            state.setPanelVisible(true)
            #expect(state.protectedFilters.apps.count == 2)
            #expect(state.protectedFilters.kinds.isEmpty && state.protectedFilters.tags.isEmpty)
            #expect(state.protectedFilters.pinned.isEmpty && !state.protectedFilters.all.isEmpty)
            #expect(state.protectedSourceLabel(for: one.id) == nil)
            let spy = PanelActionSpy()
            let router = PanelKeyRouter(
                stateStore: state, actions: spy.actions,
                keyBindings: KeyBindingsStore(defaults: sandbox.defaults),
                vimBindings: VimBindingsStore(defaults: sandbox.defaults),
                togglePreview: { Issue.record("Unexpected preview") }, closePanel: {})
            #expect(!router.handle(try #require(aKeyEvent(kVK_Tab))))
            #expect(!router.handle(try #require(aKeyEvent(kVK_Space))))
            #expect(router.handle(try #require(aKeyEvent(kVK_ANSI_C, [.command], typing: "c"))))
            #expect(spy.calls.isEmpty)
            state.filterWhileProtected(.toggleKind("image"))
            state.filterWhileProtected(.selectKind("image"))
            state.filterWhileProtected(.selectApp("unknown.app"))
            #expect(state.protectedCardIDs.count == 2)
            state.filterWhileProtected(.selectApp("test.two"))
            #expect(state.protectedCardIDs == [two.id])
            state.filterWhileProtected(.toggleKind(allFiltersChipID))
            #expect(state.protectedCardIDs.count == 2)
            state.filterWhileProtected(.toggleApp("test.one"))
            #expect(state.protectedCardIDs == [one.id])
            // Card-source visibility is independent and must not reset a permitted app filter.
            state.setPrivacyPermissions(allowSearch: false, showSourceApps: true, allowAppFiltering: true)
            state.setPrivacyPermissions(allowSearch: false, showSourceApps: false, allowAppFiltering: true)
            #expect(state.protectedCardIDs == [one.id])
            state.setPrivacyPermissions(allowSearch: false, showSourceApps: true)
            #expect(state.protectedFilters.isEmpty && state.protectedCardIDs.count == 2)
            state.filterWhileProtected(.toggleApp("test.one"))
            #expect(state.protectedCardIDs.count == 2)
            state.setPrivacyPermissions(allowSearch: false, showSourceApps: false, allowAppFiltering: true)
            state.setPanelVisible(false)
            state.filterWhileProtected(.selectApp("test.two"))
            #expect(state.protectedCardIDs.count == 2)
            #expect(state.state == .empty && state.previewItems.isEmpty)
            #expect(board.written.isEmpty && disk.saveCount == 0)
            if automatic { #expect(!state.allowsSpotlight && state.spotlightPayload(for: one.id) == nil) }
        }
    }

    @Test func filtered_search_preserves_the_query_and_automatic_protection_remains_masked() throws {
        let clock = HandCrankedScheduler()
        let debounce = Debouncer(delay: 0.18, scheduler: clock.schedule)
        let state = HistoryViewStateStore(protectedSearchDebounce: debounce)
        let disk = InMemoryHistoryStore()
        let item = anItem(.text("target"), pinned: true)
        disk.stored = [item, anItem(.text("different"))]
        let controller = ClipboardController(
            pasteboard: ScriptedPasteboard(), store: disk, clock: FakeClock(), present: { state.update($0) })
        state.protectedSearch = { controller.search($0) }
        state.protectedFilter = { action in
            if case .toggleKind(let key) = action { controller.toggleCategoryFilter(key) }
            if case .reset = action { controller.toggleCategoryFilter(allFiltersChipID) }
        }
        let sandbox = try IsolatedDefaults()
        let privacy = PrivacyController(defaults: sandbox.defaults, schedulesTimer: false)
        privacy.setAutomaticEnabled(true)
        privacy.receive([SharingReport(state: .active, reason: .toolbarPresent)])
        state.setPrivacy(privacy.isProtected)
        state.setSpotlightAllowed(privacy.allowsSpotlight)
        state.setPrivacyPermissions(allowSearch: true, showSourceApps: false, allowFiltering: true)
        state.setPanelVisible(true)
        state.searchWhileProtected("target")
        state.filterWhileProtected(.toggleKind(pinnedChipID))
        #expect(state.protectedCardIDs == [item.id])
        #expect(state.protectedQuery == "target")
        state.filterWhileProtected(.toggleKind(allFiltersChipID))
        #expect(state.protectedCardIDs == [item.id] && state.protectedQuery == "target")
        state.setPrivacyPermissions(allowSearch: true, showSourceApps: false, allowFiltering: false)
        #expect(state.protectedQuery == "target" && state.protectedFilters.isEmpty)
        #expect(state.state == .empty && !state.allowsSpotlight)
        #expect(state.spotlightPayload(for: item.id) == nil)
    }

    @Test func filter_only_privacy_renders_without_exporting_or_exposing_content() throws {
        _ = NSApplication.shared
        let state = HistoryViewStateStore()
        let item = anItem(.text("SECRET BODY"), from: "SECRET APP", bundle: "test.secret")
        let source = try #require(item.source)
        state.update(
            HistoryPresenter().present(
                items: [item], query: "", now: Date(),
                filters: FilterContext(chips: ChipEntry.row(hasPinned: false, sources: [source], categories: [.text]))))
        state.setPrivacy(true)
        state.setPanelVisible(true)
        state.setPrivacyPermissions(allowSearch: false, showSourceApps: false, allowFiltering: true)
        let spy = PanelActionSpy()
        let host = HistoryPanelHosting.make(store: state, actions: spy.actions)
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 430)
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 900, height: 430),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        func labels(_ object: AnyObject, depth: Int = 0) -> String {
            guard depth < 20, let node = object as? NSAccessibilityProtocol else { return "" }
            return (node.accessibilityLabel() ?? "")
                + (node.accessibilityChildren() ?? []).map { labels($0 as AnyObject, depth: depth + 1) }.joined()
        }
        #expect(!labels(host).contains("SECRET"))
        let renderer = ImageRenderer(content: host.rootView)
        renderer.proposedSize = ProposedViewSize(width: 900, height: 430)
        #expect(renderer.nsImage != nil)
        #expect(state.protectedFilters.apps.isEmpty)
        let sandbox = try IsolatedDefaults()
        let router = PanelKeyRouter(
            stateStore: state, actions: spy.actions,
            keyBindings: KeyBindingsStore(defaults: sandbox.defaults),
            vimBindings: VimBindingsStore(defaults: sandbox.defaults),
            togglePreview: { Issue.record("Unexpected preview") }, closePanel: {})
        #expect(router.handle(try #require(aKeyEvent(kVK_ANSI_C, [.command], typing: "c"))))
        #expect(!router.handle(try #require(aKeyEvent(kVK_Return))))
        #expect(spy.calls.isEmpty)
        #expect(state.state.cards.isEmpty)
    }
}

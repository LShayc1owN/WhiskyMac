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
@Suite struct PrivacyDisplayOptions {
    @Test func display_options_are_independent_opt_in_and_persist() throws {
        let sandbox = try IsolatedDefaults()
        let privacy = PrivacyController(defaults: sandbox.defaults)
        #expect(!privacy.allowSearchWhileProtected && !privacy.showSourceAppsWhileProtected)
        var callbacks = 0
        privacy.displayPermissionsChanged = { callbacks += 1 }
        privacy.allowSearchWhileProtected = true
        let first = PrivacyController(defaults: sandbox.defaults)
        #expect(first.allowSearchWhileProtected && !first.showSourceAppsWhileProtected)
        privacy.showSourceAppsWhileProtected = true
        privacy.allowSearchWhileProtected = false
        let restored = PrivacyController(defaults: sandbox.defaults)
        #expect(!restored.allowSearchWhileProtected && restored.showSourceAppsWhileProtected)
        #expect(!restored.isProtected)
        #expect(callbacks == 3)
    }

    @Test func protected_search_only_filters_ids_and_source_labels_require_their_own_permission() throws {
        let debounce = Debouncer(delay: 0.18, scheduler: { _, _ in })
        let state = HistoryViewStateStore(protectedSearchDebounce: debounce)
        let storage = InMemoryHistoryStore()
        let alpha = anItem(.text("BODY-ALPHA-CANARY"), from: "SOURCE-ALPHA", bundle: "synthetic.alpha")
        let beta = anItem(.text("BODY-BETA-CANARY"), from: "SOURCE-BETA", bundle: "synthetic.beta")
        storage.stored = [alpha, beta]
        let controller = ClipboardController(
            pasteboard: ScriptedPasteboard(), store: storage,
            clock: FakeClock(), logger: RecordingLogger()
        ) { state.update($0) }
        state.protectedSearch = { controller.search($0) }
        controller.search("BETA")
        state.setPrivacy(true)
        state.setPanelVisible(true)
        #expect(state.protectedCardIDs.count == 2)  // Never inherit a hidden pre-protection query.
        state.searchWhileProtected("ALPHA")
        debounce.flush()
        #expect(state.protectedQuery.isEmpty)
        state.setPrivacyPermissions(allowSearch: true, showSourceApps: false)
        state.searchWhileProtected("ALPHA")
        debounce.flush()
        #expect(state.protectedCardIDs == [alpha.id])
        #expect(state.protectedSourceLabel(for: alpha.id) == nil)
        #expect(state.state.cards.isEmpty && state.previewItems.isEmpty)
        state.preparePreview()
        #expect(state.previewItems.isEmpty)
        state.setPrivacyPermissions(allowSearch: true, showSourceApps: true)
        #expect(state.protectedSourceLabel(for: alpha.id) == "SOURCE-ALPHA")
        #expect(state.protectedSourceLabel(for: beta.id) == nil)
        #expect(state.spotlightPayload(for: alpha.id) == nil)
        state.setPrivacyPermissions(allowSearch: false, showSourceApps: true)
        #expect(state.protectedQuery.isEmpty)
        #expect(Set(state.protectedCardIDs) == [alpha.id, beta.id])
        #expect(storage.saveCount == 0)
        state.setPrivacy(false)
        #expect(state.protectedSourceLabel(for: alpha.id) == nil)
    }

    @Test func disabling_closing_and_leaving_cancel_pending_queries() {
        var work: [DispatchWorkItem] = []
        let debounce = Debouncer(delay: 0.18, scheduler: { _, item in work.append(item) })
        let state = HistoryViewStateStore(protectedSearchDebounce: debounce)
        var queries: [String] = []
        state.protectedSearch = { queries.append($0) }
        state.setPrivacy(true)
        state.setPrivacyPermissions(allowSearch: true, showSourceApps: false)
        state.setPanelVisible(true)
        state.searchWhileProtected("old")
        state.searchWhileProtected("new")
        debounce.flush()
        #expect(queries == ["", "new"])
        state.searchWhileProtected("disabled")
        state.setPrivacyPermissions(allowSearch: false, showSourceApps: false)
        work.forEach { $0.perform() }
        #expect(queries == ["", "new", ""])
        state.setPrivacyPermissions(allowSearch: true, showSourceApps: false)
        state.searchWhileProtected("closed")
        state.panelDidClose()
        work.forEach { $0.perform() }
        #expect(!queries.contains("closed"))
        state.setPanelVisible(true)
        state.searchWhileProtected("leaving")
        state.setPrivacy(false)
        work.forEach { $0.perform() }
        #expect(!queries.contains("leaving"))
        #expect(state.protectedQuery.isEmpty)
    }

    @Test func opted_in_automatic_protection_still_blocks_content_and_card_commands() throws {
        let sandbox = try IsolatedDefaults()
        let privacy = PrivacyController(defaults: sandbox.defaults)
        privacy.allowSearchWhileProtected = true
        privacy.showSourceAppsWhileProtected = true
        privacy.setAutomaticEnabled(true)
        privacy.receive([SharingReport(state: .active, reason: .toolbarPresent)])
        let state = HistoryViewStateStore()
        state.setPrivacyPermissions(
            allowSearch: privacy.allowSearchWhileProtected,
            showSourceApps: privacy.showSourceAppsWhileProtected)
        state.setPrivacy(privacy.isProtected)
        state.setSpotlightAllowed(privacy.allowsSpotlight)
        state.setPanelVisible(true)
        let item = anItem(.text("BODY-CANARY"), from: "Allowed App", bundle: "synthetic.app")
        state.update(HistoryPresenter().present(items: [item], query: "", now: Date()))
        #expect(state.protectedSourceLabel(for: item.id) == "Allowed App")
        #expect(state.spotlightPayload(for: item.id) == nil)
        let spy = PanelActionSpy()
        let router = PanelKeyRouter(
            stateStore: state, actions: spy.actions,
            keyBindings: KeyBindingsStore(defaults: sandbox.defaults),
            vimBindings: VimBindingsStore(defaults: sandbox.defaults),
            togglePreview: { Issue.record("Unexpected preview") }, closePanel: {})
        func event(_ code: Int, _ text: String) throws -> NSEvent {
            try #require(
                NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text,
                    isARepeat: false, keyCode: UInt16(code)))
        }
        #expect(!router.handle(try event(kVK_ANSI_A, "a")))
        #expect(router.handle(try event(kVK_Return, "\r")))
        #expect(router.handle(try event(kVK_ANSI_KeypadEnter, "\u{3}")))
        #expect(spy.calls.isEmpty)
        state.setPrivacyPermissions(allowSearch: false, showSourceApps: true)
        #expect(router.handle(try event(kVK_ANSI_A, "a")))
    }

    @Test func all_permission_combinations_render_with_no_body_dtos() throws {
        _ = NSApplication.shared
        let item = anItem(.text("BODY-CANARY"), from: "ALLOWED-APP", bundle: "synthetic.app")
        for search in [false, true] {
            for source in [false, true] {
                let state = HistoryViewStateStore()
                state.update(HistoryPresenter().present(items: [item], query: "", now: Date()))
                state.setPrivacy(true)
                state.setPanelVisible(true)
                state.setPrivacyPermissions(allowSearch: search, showSourceApps: source)
                let host = HistoryPanelHosting.make(store: state, actions: PanelActionSpy().actions)
                host.frame = NSRect(x: 0, y: 0, width: 900, height: 430)
                host.layoutSubtreeIfNeeded()
                if !search && !source { #expect(host.accessibilityChildren()?.isEmpty == true) }
                #expect(state.state.cards.isEmpty)
                let renderer = ImageRenderer(content: HistoryPanelView(store: state, actions: PanelActionSpy().actions))
                renderer.proposedSize = ProposedViewSize(width: 900, height: 430)
                #expect(renderer.nsImage != nil)
            }
        }
    }
}

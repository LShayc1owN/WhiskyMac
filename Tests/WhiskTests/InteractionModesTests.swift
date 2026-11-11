// WhiskyMac: modified or added 2026-11-04 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Testing

@testable import Whisk

@MainActor
@Suite struct InteractionModes {
    @Test func legacy_settings_migrate_once_and_modes_remain_independent() throws {
        let sandbox = try IsolatedDefaults()
        let old = InteractionBindings(
            singleClick: .copy, doubleClick: .edit, rightClick: .paste,
            hover: .preview, hoverDelay: 1.5)
        sandbox.defaults.set(try JSONEncoder().encode(old), forKey: "cardInteractions")
        let settings = GeneralSettingsStore(defaults: sandbox.defaults)
        #expect(settings.interactions == old)
        #expect(settings.privacyInteractions.singleClick == .none)
        #expect(settings.privacyInteractions.doubleClick == .none)
        #expect(settings.privacyInteractions.rightClick == .menu)
        #expect(settings.privacyInteractions.hover == .preview && settings.privacyInteractions.hoverDelay == 1.5)
        settings.interactions.hover = .none
        settings.interactions.hoverDelay = 0.2
        let reloaded = GeneralSettingsStore(defaults: sandbox.defaults)
        #expect(reloaded.privacyInteractions.hover == .preview && reloaded.privacyInteractions.hoverDelay == 1.5)
        settings.privacyInteractions.singleClick = .copy
        settings.privacyInteractions.doubleClick = .paste
        settings.privacyInteractions.hoverDelay = 2
        let restored = GeneralSettingsStore(defaults: sandbox.defaults)
        #expect(restored.privacyInteractions.singleClick == .copy && restored.privacyInteractions.doubleClick == .paste)
        #expect(restored.interactions.hover == .none && restored.interactions.hoverDelay == 0.2)
        settings.privacyInteractions.singleClick = .edit
        #expect(settings.privacyInteractions.singleClick == .none)
        let unsafe = InteractionBindings(singleClick: .edit, doubleClick: .edit, rightClick: .edit)
        sandbox.defaults.set(try JSONEncoder().encode(unsafe), forKey: "privacyCardInteractions")
        let safe = GeneralSettingsStore(defaults: sandbox.defaults).privacyInteractions
        #expect(safe.singleClick == .none && safe.doubleClick == .none && safe.rightClick == .none)
    }

    @Test func explicit_exports_require_a_visible_protected_record_and_exact_version_membership() {
        let first = ClipboardItem(
            id: UUID(), payload: .text("SECRET"), source: nil, copiedAt: Date(timeIntervalSince1970: 2000),
            isPinned: false, rtf: Data([1]))
        let second = ClipboardItem(
            id: UUID(), payload: .text("SECRET"), source: nil, copiedAt: Date(timeIntervalSince1970: 1000),
            isPinned: false, rtf: Data([2]))
        let state = HistoryViewStateStore()
        state.update(HistoryPresenter().present(items: [first, second], query: "", now: Date()))
        state.setPrivacy(true)
        state.setPanelVisible(true)
        var exports: [(UUID, CardAction)] = []
        state.protectedExport = { exports.append(($0, $1)) }
        #expect(state.protectedVersions(for: first.id) == [first.id, second.id])
        state.exportWhileProtected(cardID: first.id, versionID: second.id, action: .copy)
        state.exportWhileProtected(cardID: first.id, versionID: first.id, action: .paste)
        #expect(exports.count == 2 && exports[0].0 == second.id && exports[1].1 == .paste)
        for action in [CardAction.none, .menu, .preview, .edit] {
            state.exportWhileProtected(cardID: first.id, versionID: first.id, action: action)
        }
        state.exportWhileProtected(cardID: first.id, versionID: UUID(), action: .copy)
        state.exportWhileProtected(cardID: UUID(), versionID: first.id, action: .copy)
        state.panelDidClose()
        state.exportWhileProtected(cardID: first.id, versionID: first.id, action: .copy)
        state.setPanelVisible(true)
        state.setPrivacy(false)
        state.exportWhileProtected(cardID: first.id, versionID: first.id, action: .copy)
        #expect(exports.count == 2)
        #expect(state.previewItems.isEmpty && state.editing == nil)
    }

    @Test func explicit_local_reveal_is_manual_only_and_never_opens_full_preview() {
        let state = HistoryViewStateStore()
        let item = anItem(.text("SECRET"))
        state.update(HistoryPresenter().present(items: [item], query: "", now: Date()))
        state.detailSource = { _ in item }
        state.setPrivacy(true)
        state.setPanelVisible(true)
        state.setSpotlightAllowed(true)
        state.privacyInteractions.hover = .none
        state.interactions.hover = .preview
        #expect(state.spotlightPayload(for: item.id) == nil)
        #expect(state.protectedRevealPayload(for: item.id) == item.payload)
        state.privacyInteractions.hover = .preview
        state.interactions.hover = .none
        #expect(state.spotlightPayload(for: item.id) == item.payload)
        state.setSpotlightAllowed(false)
        #expect(state.spotlightPayload(for: item.id) == nil && state.protectedRevealPayload(for: item.id) == nil)
        #expect(state.state == .empty && state.previewItems.isEmpty)
    }
}

@MainActor
@Suite struct SplitInteractionAction {
    @Test func split_can_be_bound_to_each_normal_click_and_persists() throws {
        let sandbox = try IsolatedDefaults()
        let settings = GeneralSettingsStore(defaults: sandbox.defaults)
        settings.interactions = InteractionBindings(singleClick: .split, doubleClick: .split, rightClick: .split)
        let restored = GeneralSettingsStore(defaults: sandbox.defaults)
        for trigger in [CardTrigger.singleClick, .doubleClick, .rightClick] {
            #expect(restored.interactions.action(for: trigger) == .split)
        }
        #expect(!CardAction.split.label.isEmpty)
        settings.interactions.hover = .split
        #expect(settings.interactions.hover == .none)
        let encoded = try JSONEncoder().encode(InteractionBindings(singleClick: .split, hover: .split))
        #expect(try JSONDecoder().decode(InteractionBindings.self, from: encoded).hover == .none)
    }

    @Test func privacy_profile_rejects_split_on_assignment_and_reload() throws {
        let sandbox = try IsolatedDefaults()
        let settings = GeneralSettingsStore(defaults: sandbox.defaults)
        let split = InteractionBindings(singleClick: .split, doubleClick: .split, rightClick: .split)
        settings.privacyInteractions = split
        #expect(settings.privacyInteractions.singleClick == .none)
        #expect(settings.privacyInteractions.doubleClick == .none)
        #expect(settings.privacyInteractions.rightClick == .none)
        sandbox.defaults.set(try JSONEncoder().encode(split), forKey: "privacyCardInteractions")
        let restored = GeneralSettingsStore(defaults: sandbox.defaults)
        #expect(restored.privacyInteractions.singleClick == .none)
        #expect(restored.privacyInteractions.doubleClick == .none)
        #expect(restored.privacyInteractions.rightClick == .none)
    }

    @Test func configured_split_uses_the_split_entry_and_rejects_protected_hidden_and_grouped_content() throws {
        let ordinary = anItem(.text("one\ntwo"))
        let presenter = HistoryPresenter()
        let state = HistoryViewStateStore()
        state.detailSource = { _ in ordinary }
        state.update(presenter.present(items: [ordinary], query: "", now: ordinary.copiedAt, selectedID: ordinary.id))
        let card = try #require(state.state.selectedCard)
        var requested: [UUID] = []
        var previews = 0
        state.showPreview = { previews += 1 }
        var actions = PanelActionSpy().actions
        actions.split = { requested.append($0) }
        state.interact(card, action: .split, actions: actions)
        #expect(requested == [ordinary.id] && previews == 0)
        state.setPrivacy(true)
        state.interact(card, action: .split, actions: actions)
        state.setPrivacy(false)
        let hidden = ordinary.withPinnedMetadata(PinnedMetadata(hidesContent: true))
        state.update(presenter.present(items: [hidden], query: "", now: ordinary.copiedAt, selectedID: ordinary.id))
        state.interact(card, action: .split, actions: actions)  // An old rendered card must not bypass hiding.
        let parts = try SplitContentCodec.analyze(ordinary, options: SplitOptions()).map(\.part)
        let group = ordinary.withSplitGroup(SplitGroup(parts: parts, plainText: false))
        state.update(presenter.present(items: [group], query: "", now: ordinary.copiedAt, selectedID: ordinary.id))
        state.interact(card, action: .split, actions: actions)
        #expect(requested == [ordinary.id] && previews == 0)
        let guarded = actions.guarded { true }
        guarded.split(ordinary.id)
        #expect(requested == [ordinary.id])
    }
}

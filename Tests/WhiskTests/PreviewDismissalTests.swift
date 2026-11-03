// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Testing

@testable import Whisk

@MainActor
@Suite struct PreviewDismissal {
    private final class Fixture {
        var scheduled: [(TimeInterval, DispatchWorkItem)] = []
        var opens = 0
        var closes = 0
        let spy = PanelActionSpy()
        let items = [anItem(.text("FIRST")), anItem(.text("SECOND"))]
        lazy var store = HistoryViewStateStore(previewCloseScheduler: { [weak self] delay, work in
            self?.scheduled.append((delay, work))
        })

        init() {
            store.interactions.hover = .preview
            store.setPanelVisible(true)
            store.update(HistoryPresenter().present(items: items, query: "", now: Date(), selectedID: items[0].id))
            store.detailSource = { [weak self] id in self?.items.first { $0.id == id } }
            store.showPreview = { [weak self] in
                self?.opens += 1
                self?.store.preparePreview()
            }
            store.hidePreview = { [weak self] in
                self?.closes += 1
                self?.store.closePreview()
            }
        }

        func card(_ index: Int = 0) -> CardViewState { store.state.cards[index] }
        func hover(_ index: Int = 0) {
            let id = items[index].id
            store.cardHoverChanged(id, inside: true)
            store.update(HistoryPresenter().present(items: items, query: "", now: Date(), selectedID: id))
            store.hoverPreview(card(index), actions: spy.actions)
        }
    }

    @Test func leaving_hover_card_waits_exactly_point_four_seconds_then_closes() throws {
        let f = Fixture()
        f.hover()
        #expect(f.opens == 1 && f.closes == 0)
        #expect(f.store.previewItems.map(\.id) == [f.items[0].id])
        f.store.cardHoverChanged(f.items[0].id, inside: false)
        let (delay, work) = try #require(f.scheduled.last)
        #expect(delay == 0.4)
        #expect(f.closes == 0)
        work.perform()
        #expect(f.closes == 1)
        #expect(f.store.previewItems.isEmpty && f.store.previewOrigin == nil)
    }

    @Test func reentering_cancels_the_close_and_a_later_exit_gets_a_new_delay() throws {
        let f = Fixture()
        f.hover()
        f.store.cardHoverChanged(f.items[0].id, inside: false)
        let old = try #require(f.scheduled.last?.1)
        f.store.cardHoverChanged(f.items[0].id, inside: true)
        #expect(old.isCancelled)
        old.perform()
        #expect(f.closes == 0)
        #expect(f.store.previewOrigin == .hover(f.items[0].id))
        f.store.cardHoverChanged(f.items[0].id, inside: false)
        try #require(f.scheduled.last?.1).perform()
        #expect(f.closes == 1)
    }

    @Test func an_old_card_exit_cannot_close_a_new_card_preview() throws {
        let f = Fixture()
        f.hover()
        f.store.cardHoverChanged(f.items[0].id, inside: false)
        let old = try #require(f.scheduled.last?.1)
        f.hover(1)
        old.perform()
        #expect(f.store.previewOrigin == .hover(f.items[1].id))
        #expect(f.store.previewItems.map(\.id) == [f.items[1].id])
        #expect(f.closes == 0)
        f.store.cardHoverChanged(f.items[0].id, inside: false)
        #expect(f.scheduled.count == 1)
    }

    @Test func hover_preview_stays_with_its_owner_until_the_next_dwell_finishes() {
        let f = Fixture()
        f.hover()
        f.store.cardHoverChanged(f.items[0].id, inside: false)
        f.store.cardHoverChanged(f.items[1].id, inside: true)
        f.store.update(HistoryPresenter().present(items: f.items, query: "", now: Date(), selectedID: f.items[1].id))
        #expect(f.store.state.selectedCard?.id == f.items[1].id)
        #expect(f.store.previewCard?.id == f.items[0].id)
        #expect(f.store.previewItems.map(\.id) == [f.items[0].id])
        f.store.hoverPreview(f.card(1), actions: f.spy.actions)
        #expect(f.store.previewCard?.id == f.items[1].id)
        #expect(f.store.previewItems.map(\.id) == [f.items[1].id])
    }

    @Test func explicit_preview_stays_after_hover_exit_and_toggles_closed_on_second_action() {
        let f = Fixture()
        f.store.interact(f.card(), action: .preview, actions: f.spy.actions)
        #expect(f.store.previewOrigin == .explicit)
        f.store.cardHoverChanged(f.items[0].id, inside: true)
        f.store.cardHoverChanged(f.items[0].id, inside: false)
        #expect(f.scheduled.isEmpty)
        #expect(f.closes == 0)
        f.store.interact(f.card(), action: .preview, actions: f.spy.actions)
        #expect(f.closes == 1 && f.store.previewOrigin == nil)
        #expect(f.store.previewItems.isEmpty)
        f.store.toggleExplicitPreview()  // Keyboard route shares the same lifecycle.
        #expect(f.store.previewOrigin == .explicit)
        f.store.toggleExplicitPreview()
        #expect(f.closes == 2)
    }

    @Test func explicit_action_promotes_hover_preview_and_invalidates_old_exit() throws {
        let f = Fixture()
        f.hover()
        f.store.cardHoverChanged(f.items[0].id, inside: false)
        let old = try #require(f.scheduled.last?.1)
        f.store.interact(f.card(), action: .preview, actions: f.spy.actions)
        old.perform()
        #expect(f.store.previewOrigin == .explicit)
        #expect(f.closes == 0)
        f.store.cardHoverChanged(f.items[1].id, inside: true)
        f.store.hoverPreview(f.card(1), actions: f.spy.actions)
        #expect(f.store.previewOrigin == .explicit && f.opens == 2)
        f.store.interact(f.card(), action: .preview, actions: f.spy.actions)
        #expect(f.closes == 1)
    }

    @Test func closing_protection_and_settings_changes_cancel_hover_work() throws {
        for reason in ["panel", "privacy", "settings"] {
            let f = Fixture()
            f.hover()
            f.store.cardHoverChanged(f.items[0].id, inside: false)
            let old = try #require(f.scheduled.last?.1)
            switch reason {
            case "panel": f.store.panelDidClose()
            case "privacy": f.store.setPrivacy(true)
            default: f.store.interactions.hover = .none
            }
            let closes = f.closes
            old.perform()
            #expect(old.isCancelled)
            #expect(f.store.previewOrigin == nil && f.store.previewItems.isEmpty)
            #expect(f.closes == closes)
        }
        let f = Fixture()
        f.store.interact(f.card(), action: .preview, actions: f.spy.actions)
        f.store.panelDidClose()
        #expect(f.store.previewOrigin == nil)
        #expect(f.closes == 1)
    }

    @Test func a_hover_callback_after_exit_or_during_protection_cannot_open_preview() {
        let f = Fixture()
        f.store.hoverPreview(f.card(), actions: f.spy.actions)
        #expect(f.opens == 0)
        f.store.cardHoverChanged(f.items[0].id, inside: true)
        f.store.cardHoverChanged(f.items[0].id, inside: false)
        f.store.hoverPreview(f.card(), actions: f.spy.actions)
        #expect(f.opens == 0)
        f.store.panelDidClose()
        f.store.cardHoverChanged(f.items[0].id, inside: true)
        f.store.hoverPreview(f.card(), actions: f.spy.actions)
        #expect(f.opens == 0)
        let card = f.card()
        f.store.setPrivacy(true)
        f.store.cardHoverChanged(card.id, inside: true)
        f.store.hoverPreview(card, actions: f.spy.actions)
        f.store.toggleExplicitPreview()
        #expect(f.opens == 0)
    }

    @Test func format_choice_is_explicit_and_not_subject_to_hover_timeout() throws {
        let f = Fixture()
        let a = ClipboardItem(
            id: UUID(), payload: .text("same"), source: nil, copiedAt: Date(),
            isPinned: false, rtf: Data([1]))
        let b = ClipboardItem(
            id: UUID(), payload: .text("same"), source: nil, copiedAt: Date(),
            isPinned: false, rtf: Data([2]))
        f.store.update(HistoryPresenter().present(items: [a, b], query: "", now: Date(), selectedID: a.id))
        let card = try #require(f.store.state.cards.first)
        f.store.interact(card, action: .copy, actions: f.spy.actions)
        #expect(f.store.previewOrigin == .explicit)
        #expect(f.store.pendingAction == .copy)
        f.store.cardHoverChanged(card.id, inside: false)
        #expect(f.scheduled.isEmpty)
    }
}

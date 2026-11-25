// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI
import Testing

@testable import Whisk

@MainActor
@Suite(.serialized)
struct MacOS26HistoryCardsTests {
    @Test(.enabled(if: ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26))
    func production_history_host_uses_new_cards_and_keeps_the_protection_boundary() throws {
        guard #available(macOS 26, *) else { return }
        _ = NSApplication.shared
        let store = HistoryViewStateStore()
        let item = anItem(.text("PRIVATE_CARD_CONTENT"), from: "Example")
        store.update(HistoryPresenter().present(items: [item], query: "", now: item.copiedAt, selectedID: item.id))
        let actions = PanelActionSpy().actions
        let factory = AppUISelector.make()
        #expect(factory is MacOS26UIFactory)
        let view = HistoryPanelHosting.make(uiFactory: factory, store: store, actions: actions)
        let host = try #require(view as? TestHostingSurface)
        #expect(try #require(store.state.selectedCard).id == item.id)
        #expect(host.sizingOptions.isEmpty)

        store.setPrivacy(true)
        let protected = HistoryPanelHosting.make(uiFactory: factory, store: store, actions: actions)
        #expect(store.state.cards.isEmpty)
        #expect(protected.accessibilityLabel() == localized("Content hidden by Privacy Mode"))
        #expect(!labels(in: protected).contains("PRIVATE_CARD_CONTENT"))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26))
    func both_selection_states_and_every_payload_fit_the_same_square_slot() {
        guard #available(macOS 26, *) else { return }
        let items = ViewFixtures.items()
        let actions = PanelActionSpy().actions
        for selectedID in [items.first?.id, nil] {
            let state = HistoryPresenter().present(items: items, query: "", now: Date(), selectedID: selectedID)
            for card in state.cards {
                let side: CGFloat = 160
                let content = MacOS26HistoryCard(
                    card: card, actions: actions, keyBindings: nil, side: side, showsSelection: true,
                    isVisible: false, hoverEnabled: false, pinnedWorkspace: false,
                    interactions: InteractionBindings(), canExport: { false }, interact: { _ in },
                    hoverPreview: {}, hoverChanged: { _ in })
                let renderer = ImageRenderer(content: content)
                let extent = side * HistoryViewStateStore.selectionZoom
                renderer.proposedSize = ProposedViewSize(width: extent, height: extent)
                #expect(renderer.nsImage?.size == CGSize(width: extent, height: extent))
            }
        }
    }

    private func labels(in node: Any, depth: Int = 0) -> String {
        guard depth < 20, let element = node as? NSAccessibilityProtocol else { return "" }
        let label = element.accessibilityLabel() ?? ""
        return label + (element.accessibilityChildren() ?? []).map { labels(in: $0, depth: depth + 1) }.joined()
    }
}

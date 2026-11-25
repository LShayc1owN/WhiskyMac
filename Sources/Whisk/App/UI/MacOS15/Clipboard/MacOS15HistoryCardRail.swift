// WhiskyMac: modified or added 2026-11-17 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

/// Preserve the full document extent with a bounded set of actual slots.
struct MacOS15HistoryCardRail: View {
    @ObservedObject var store: HistoryViewStateStore
    let actions: PanelActions
    let keyBindings: KeyBindingsStore?
    let returnToLatestRevision: Int
    var appScope: FilterAppScope? = nil
    @State private var window = CardRailWindow()
    @State private var scrolling = CardRailScrollState()
    @State private var position = ScrollPosition()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: false) {
            HStack(spacing: HistoryViewStateStore.cardGap) {
                ForEach(
                    CardRailLayout.entries(
                        cards: store.state.cards, window: window,
                        selectedIndex: store.state.selectedCardIndex)
                ) { entry in
                    switch entry {
                    case .card(let index, _):
                        card(store.state.cards[index])
                            .transition(.opacity)
                    case .gap(let range):
                        gap(range)
                    }
                }
            }
            .padding(.bottom, MacOS15PanelLayout.railVerticalPadding)
            .animation(
                reduceMotion || !store.panelVisible ? nil : .easeInOut(duration: 0.18),
                value: RailFilter(store.state))
        }
        .frame(
            minHeight: 0, idealHeight: store.zoomedCardSide + MacOS15PanelLayout.railVerticalPadding,
            maxHeight: store.zoomedCardSide + MacOS15PanelLayout.railVerticalPadding
        )
        .contentMargins(.horizontal, MacOS15PanelLayout.contentMargin, for: .scrollContent)
        .scrollPosition($position)
        .onScrollGeometryChange(for: CardRailViewport.self) {
            CardRailViewport(
                $0, count: store.state.cards.count, side: store.zoomedCardSide, stride: store.cardStride,
                rtl: layoutDirection == .rightToLeft)
        } action: { previous, next in
            let initial = scrolling.viewport == nil
            scrolling.update(next, position: $position, reduceMotion: reduceMotion)
            if window != next.window { window = next.window }
            if initial || previous.visible != next.visible { updateAppScope(cards: store.state.cards) }
        }
        .onChange(of: store.panelVisible) { _, visible in
            if !visible { scrolling.cancelReturn() }
        }
        .onScrollPhaseChange { _, phase in
            if phase == .tracking || phase == .interacting { scrolling.cancelReturn() }
        }
        .onReceive(store.$state) { state in updateAppScope(cards: state.cards) }
        .onDisappear {
            scrolling.cancelReturn()
            appScope?.update([])
        }
        .onChange(of: store.state.selectedID) {
            scrolling.cancelReturn()
            guard let index = store.state.selectedCardIndex,
                let target = scrolling.viewport?.revealOffset(
                    index: index, side: store.zoomedCardSide, stride: store.cardStride)
            else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                position.scrollTo(x: target)
            }
        }
        .onChange(of: store.closeRevision) {
            scrolling.returnToLatest(position: $position, reduceMotion: true)
        }
        .onChange(of: returnToLatestRevision) {
            scrolling.returnToLatest(position: $position, reduceMotion: reduceMotion)
        }
    }

    private func updateAppScope(cards: [CardViewState]) {
        guard let appScope, let visible = scrolling.viewport?.visible else { return }
        appScope.update(Set(cards[visible.clamped(to: cards.indices)].compactMap(\.sourceKey)))
    }

    private func gap(_ range: Range<Int>) -> some View {
        Color.clear
            .frame(
                width: CGFloat(range.count) * store.cardStride - HistoryViewStateStore.cardGap,
                height: store.zoomedCardSide
            )
            .accessibilityHidden(true)
    }

    @ViewBuilder private func card(_ card: CardViewState) -> some View {
        let canExport = { !store.isProtected && store.state.cards.contains { $0.id == card.id } }
        MacOS15ItemCardView(
            card: card, actions: actions, keyBindings: keyBindings,
            showsSelection: !store.cursorOnSearch, side: store.cardSide, interactions: store.interactions,
            isPanelVisible: store.panelVisible, hoverEnabled: !store.cardMenuOpen && !store.pinMetadataEditing,
            canExport: canExport,
            onInteraction: { action in store.interact(card, action: action, actions: actions) },
            onHoverPreview: { store.hoverPreview(card, actions: actions) },
            onHoverChanged: { inside in store.cardHoverChanged(card.id, inside: inside) }
        )
        .equatable()

    }
}

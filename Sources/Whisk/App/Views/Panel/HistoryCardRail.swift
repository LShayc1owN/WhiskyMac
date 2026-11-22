// WhiskyMac: modified or added 2026-11-17 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

/// Preserve the full document extent with a bounded set of actual slots.
struct CardRailLayout {
    static func revealOffset(
        index: Int, side: CGFloat, stride: CGFloat, geometry: ScrollGeometry, rightToLeft: Bool
    ) -> CGFloat? {
        let insets = geometry.contentInsets
        // ScrollGeometry reports RTL's leading inset with the opposite
        // sign. Point-based ScrollPosition uses the same logical x in
        // either direction, with zero at the padded document start.
        let visibleStart = geometry.contentOffset.x - (rightToLeft ? insets.leading + insets.trailing : 0)
        let start = CGFloat(index) * stride
        let end = start + side
        if start < visibleStart + insets.leading { return start }
        if end > visibleStart + geometry.visibleRect.width - insets.trailing {
            return end - geometry.containerSize.width
        }
        return nil
    }

    enum Entry: Identifiable, Equatable {
        enum ID: Hashable { case card(UUID), gap(Int) }
        case card(Int, UUID)
        case gap(Range<Int>)

        var id: ID {
            switch self {
            case .card(_, let id): .card(id)
            case .gap(let range): .gap(range.lowerBound)
            }
        }

        func width(side: CGFloat, gap: CGFloat) -> CGFloat {
            switch self {
            case .card: side
            case .gap(let range): CGFloat(range.count) * (side + gap) - gap
            }
        }
    }

    static func entries(cards: [CardViewState], window: CardRailWindow, selectedIndex: Int?) -> [Entry] {
        guard !cards.isEmpty else { return [] }
        let leading = min(max(0, window.leading), cards.count - 1)
        let lower = max(0, leading - CardRailWindow.buffer)
        let upper = min(cards.count, leading + max(1, window.capacity) + CardRailWindow.buffer + 1)
        var ranges = [lower..<upper]
        if let selectedIndex, cards.indices.contains(selectedIndex) {
            if selectedIndex < lower {
                ranges.insert(selectedIndex..<(selectedIndex + 1), at: 0)
            } else if selectedIndex >= upper {
                ranges.append(selectedIndex..<(selectedIndex + 1))
            }
        }
        var result: [Entry] = []
        var previousEnd = 0
        for range in ranges {
            if previousEnd < range.lowerBound { result.append(.gap(previousEnd..<range.lowerBound)) }
            result += range.map { .card($0, cards[$0].id) }
            previousEnd = range.upperBound
        }
        if previousEnd < cards.count { result.append(.gap(previousEnd..<cards.count)) }
        return result
    }
}

/// Scroll geometry invalidates this row, not the toolbar and filter row.
struct HistoryCardRail: View {
    /// Fine scroll offsets do not publish view state. Only a change to
    /// the quantized card window below asks SwiftUI to rebuild the row.
    private final class Viewport {
        var geometry: ScrollGeometry?
        var sourceRange: Range<Int>?
    }
    @ObservedObject var store: HistoryViewStateStore
    let actions: PanelActions
    let keyBindings: KeyBindingsStore?
    let returnToLatestRevision: Int
    var appScope: FilterAppScope? = nil
    @State private var window = CardRailWindow()
    @State private var viewport = Viewport()
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
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    case .gap(let range):
                        gap(range)
                    }
                }
            }
            .padding(.bottom, PanelLayout.railVerticalPadding)
            .animation(
                reduceMotion || !store.panelVisible ? nil : .easeInOut(duration: 0.18),
                value: RailFilter(store.state))
        }
        .frame(
            minHeight: 0, idealHeight: store.zoomedCardSide + PanelLayout.railVerticalPadding,
            maxHeight: store.zoomedCardSide + PanelLayout.railVerticalPadding
        )
        .contentMargins(.horizontal, PanelLayout.contentMargin, for: .scrollContent)
        .scrollPosition($position)
        .onScrollGeometryChange(for: ScrollGeometry.self) {
            $0
        } action: { _, geometry in
            viewport.geometry = geometry
            let value = CardRailWindow(
                leading: max(0, Int(geometry.contentOffset.x / store.cardStride)),
                capacity: Int(geometry.containerSize.width / store.cardStride) + 1)
            if window != value { window = value }
            updateAppScope()
        }
        .onReceive(store.$state) { state in updateAppScope(cards: state.cards) }
        .onChange(of: store.cardSide) { _, _ in updateAppScope() }
        .onChange(of: store.panelVisible) { _, visible in
            if visible { updateAppScope() }
        }
        .onDisappear {
            viewport.sourceRange = nil
            appScope?.update([])
        }
        .onChange(of: store.state.selectedID) {
            guard let index = store.state.selectedCardIndex,
                let geometry = viewport.geometry,
                let target = CardRailLayout.revealOffset(
                    index: index, side: store.zoomedCardSide, stride: store.cardStride, geometry: geometry,
                    rightToLeft: layoutDirection == .rightToLeft)
            else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                position.scrollTo(x: target)
            }
        }
        .onChange(of: store.closeRevision) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                position.scrollTo(edge: .leading)
            }
        }
        .onChange(of: returnToLatestRevision) {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) {
                position.scrollTo(edge: .leading)
            }
        }
    }

    private func updateAppScope(cards: [CardViewState]? = nil) {
        guard let appScope, let geometry = viewport.geometry else { return }
        let current = cards ?? store.state.cards
        let start =
            geometry.contentOffset.x
            - (layoutDirection == .rightToLeft ? geometry.contentInsets.leading + geometry.contentInsets.trailing : 0)
        let range = FilterAppScope.visibleRange(
            count: current.count, side: store.zoomedCardSide, stride: store.cardStride,
            start: start, width: geometry.containerSize.width)
        guard cards != nil || viewport.sourceRange != range else { return }
        viewport.sourceRange = range
        appScope.update(Set(current[range].compactMap(\.sourceKey)))
    }

    private func gap(_ range: Range<Int>) -> some View {
        Color.clear
            .frame(
                width: CGFloat(range.count) * store.cardStride - HistoryViewStateStore.cardGap,
                height: store.zoomedCardSide
            )
            .accessibilityHidden(true)
    }

    private func card(_ card: CardViewState) -> some View {
        ItemCardView(
            card: card, actions: actions, keyBindings: keyBindings,
            showsSelection: !store.cursorOnSearch, side: store.cardSide, interactions: store.interactions,
            isPanelVisible: store.panelVisible, hoverEnabled: !store.cardMenuOpen && !store.pinMetadataEditing,
            canExport: { !store.isProtected },
            onInteraction: { action in store.interact(card, action: action, actions: actions) },
            onHoverPreview: { store.hoverPreview(card, actions: actions) },
            onHoverChanged: { inside in store.cardHoverChanged(card.id, inside: inside) }
        )
        .equatable()
    }
}

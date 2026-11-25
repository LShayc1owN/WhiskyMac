// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

struct CardRailWindow: Equatable {
    var leading = 0
    var capacity = 8

    static let buffer = 2

    func contains(_ index: Int, selectedIndex: Int?) -> Bool {
        if index == selectedIndex { return true }
        let lower = max(0, leading - Self.buffer)
        let upper = leading + capacity + Self.buffer
        return (lower...upper).contains(index)
    }
}

struct RailFilter: Equatable {
    let query: String
    let searchMatchMode: SearchMatchMode
    let activeChips: [String]

    init(_ state: HistoryViewState) {
        query = state.query
        searchMatchMode = state.searchMatchMode
        activeChips = state.filters.activeChipIDs
    }
}

/// A geometry observation changes only at boundaries relevant to layout, filtering or navigation.
struct CardRailViewport: Equatable {
    let window: CardRailWindow
    let visible: Range<Int>
    let width: CGFloat
    let nearLatest: Bool
    private let firstFullyVisible: Int
    private let lastFullyVisible: Int

    init(_ geometry: ScrollGeometry, count: Int, side: CGFloat, stride: CGFloat, rtl: Bool, leadingPadding: CGFloat = 0)
    {
        width = geometry.containerSize.width
        let insets = geometry.contentInsets
        let start = geometry.contentOffset.x - (rtl ? insets.leading + insets.trailing : 0)
        // Advance in pairs within the existing two-card preload margin.
        let leading = max(0, Int(geometry.contentOffset.x / stride))
        window = CardRailWindow(leading: leading - leading % 2, capacity: Int(width / stride) + 1)
        visible = FilterAppScope.visibleRange(
            count: count, side: side, stride: stride, start: start - leadingPadding, width: width)
        firstFullyVisible = Int(ceil((start + insets.leading) / stride))
        lastFullyVisible = Int(floor((start + geometry.visibleRect.width - insets.trailing - side) / stride))
        nearLatest = start <= width * 1.5
    }

    func revealOffset(index: Int, side: CGFloat, stride: CGFloat) -> CGFloat? {
        if index < firstFullyVisible { return CGFloat(index) * stride }
        if index > lastFullyVisible { return CGFloat(index) * stride + side - width }
        return nil
    }
}

/// Keep exact scroll offsets in the native scroll view. For long returns, land
/// near the first card before animating the last part of the journey.
@MainActor
final class CardRailScrollState {
    private(set) var viewport: CardRailViewport?
    private var awaitingLanding = false

    func update(_ next: CardRailViewport, position: Binding<ScrollPosition>, reduceMotion: Bool) {
        viewport = next
        if awaitingLanding, next.nearLatest {
            returnToLatest(position: position, reduceMotion: reduceMotion)
        }
    }

    func cancelReturn() { awaitingLanding = false }

    func returnToLatest(position: Binding<ScrollPosition>, reduceMotion: Bool) {
        awaitingLanding = false
        if !reduceMotion, let viewport, viewport.nearLatest, viewport.width > 0 {
            withAnimation(.easeOut(duration: 0.20)) { position.wrappedValue.scrollTo(edge: .leading) }
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if !reduceMotion, let viewport, viewport.width > 0 {
                awaitingLanding = true
                position.wrappedValue.scrollTo(x: viewport.width * 0.65)
            } else {
                position.wrappedValue.scrollTo(edge: .leading)
            }
        }
    }
}

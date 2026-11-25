// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

struct CardRailLayout {
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

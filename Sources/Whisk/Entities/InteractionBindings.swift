// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

enum CardTrigger: String, CaseIterable, Codable {
    case singleClick, doubleClick, rightClick, hover
}

enum CardAction: String, CaseIterable, Codable {
    case paste, copy, preview, edit, split, menu, none
}

struct InteractionBindings: Codable, Equatable {
    var singleClick: CardAction = .preview
    var doubleClick: CardAction = .paste
    var rightClick: CardAction = .menu
    var hover: CardAction = .none {
        didSet { if hover != .none && hover != .preview { hover = .none } }
    }
    var hoverDelay: Double = 0.7 {
        didSet { hoverDelay = Self.validDelay(hoverDelay) }
    }

    static func validDelay(_ value: Double) -> Double {
        value.isFinite ? min(5, max(0.1, value)) : 0.7
    }

    init(
        singleClick: CardAction = .preview, doubleClick: CardAction = .paste,
        rightClick: CardAction = .menu, hover: CardAction = .none, hoverDelay: Double = 0.7
    ) {
        self.singleClick = singleClick
        self.doubleClick = doubleClick
        self.rightClick = rightClick
        self.hover = hover == .preview ? .preview : .none
        self.hoverDelay = Self.validDelay(hoverDelay)
    }

    private enum CodingKeys: String, CodingKey {
        case singleClick, doubleClick, rightClick, hover, hoverDelay
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        singleClick = try values.decodeIfPresent(CardAction.self, forKey: .singleClick) ?? .preview
        doubleClick = try values.decodeIfPresent(CardAction.self, forKey: .doubleClick) ?? .paste
        rightClick = try values.decodeIfPresent(CardAction.self, forKey: .rightClick) ?? .menu
        let savedHover = try values.decodeIfPresent(CardAction.self, forKey: .hover) ?? .none
        hover = savedHover == .preview ? .preview : .none
        hoverDelay = Self.validDelay(try values.decodeIfPresent(Double.self, forKey: .hoverDelay) ?? 0.7)
    }

    func action(for trigger: CardTrigger) -> CardAction {
        switch trigger {
        case .singleClick: singleClick
        case .doubleClick: doubleClick
        case .rightClick: rightClick
        case .hover: hover
        }
    }
}

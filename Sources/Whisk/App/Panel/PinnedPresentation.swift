// WhiskyMac: modified or added 2026-11-08 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

enum PinnedPresentation: String, Codable, CaseIterable, Identifiable {
    case aggregated, separate
    var id: String { rawValue }
    var label: String {
        switch self {
        case .aggregated: localized("In the clipboard panel")
        case .separate: localized("Separate window")
        }
    }
}

enum PinnedWindowStyle: String, Codable, CaseIterable, Identifiable {
    case mouseList, bottomCards
    var id: String { rawValue }
    var label: String {
        switch self {
        case .mouseList: localized("Vertical list at the pointer")
        case .bottomCards: localized("Cards from the bottom")
        }
    }
}

enum PinnedWindowLayout {
    static func frame(pointer: CGPoint, visibleFrame: CGRect) -> CGRect {
        let width = min(400, visibleFrame.width)
        let height = min(560, visibleFrame.height)
        return CGRect(
            x: min(max(pointer.x, visibleFrame.minX), visibleFrame.maxX - width),
            y: min(max(pointer.y - height, visibleFrame.minY), visibleFrame.maxY - height),
            width: width, height: height)
    }
}

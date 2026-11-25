// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

extension SplitRule {
    var label: String {
        switch self {
        case .lines: localized("By line")
        case .paragraphs: localized("By paragraph")
        case .delimiters: localized("By separator")
        case .links: localized("Extract links")
        }
    }
}
extension SplitSaveMode {
    var label: String {
        switch self {
        case .keepOriginal: localized("Keep original and add cards")
        case .replace: localized("Replace original card")
        case .group: localized("Save as a card group")
        }
    }
}
extension SplitDelimiter {
    var label: String {
        switch self {
        case .comma: localized("Comma (, / ，)")
        case .semicolon: localized("Semicolon (; / ；)")
        case .enumeration: localized("Enumeration comma (、)")
        case .tab: localized("Tab")
        }
    }
}

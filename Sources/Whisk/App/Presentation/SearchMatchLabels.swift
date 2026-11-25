// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

extension SearchMatchMode {
    var title: String {
        switch self {
        case .fuzzy: localized("Fuzzy Match")
        case .containing: localized("Containing")
        case .matchingWord: localized("Matching Word")
        case .startingWith: localized("Starting With")
        case .endingWith: localized("Ending With")
        }
    }
}

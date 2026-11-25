// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

extension AttributedString {
    /// The ranges use indices from the plain string used to create this text.
    mutating func mergeAttributes(_ attributes: AttributeContainer, in ranges: [Range<String.Index>]) {
        for range in ranges {
            guard let lower = Index(range.lowerBound, within: self),
                let upper = Index(range.upperBound, within: self)
            else { continue }
            self[lower..<upper].mergeAttributes(attributes)
        }
    }
}

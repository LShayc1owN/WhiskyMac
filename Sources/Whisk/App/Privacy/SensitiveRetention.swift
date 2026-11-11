// WhiskyMac: modified or added 2026-11-07 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

/// Maximum retention for sensitive copies; never a disk-history policy.
enum SensitiveRetention {
    static let defaultMinutes = 2
    static let minutesRange = 1...1440

    static func bounded(_ minutes: Int) -> Int {
        min(minutesRange.upperBound, max(minutesRange.lowerBound, minutes))
    }

    static func minutes(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(trimmed) else {
            return nil
        }
        return bounded(value)
    }
}

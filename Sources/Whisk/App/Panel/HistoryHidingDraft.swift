// WhiskyMac: modified or added 2026-11-19 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

/// The selection is applied only on confirmation. "Now" is evaluated then.
struct HistoryHidingDraft {
    var usesNow = true
    var date = Date()
    var categories: Set<ContentCategory> = []
    var includesHandoff = false

    func rule(includingTypes: Bool, now: Date) -> HistoryHidingRule? {
        guard !includingTypes || !categories.isEmpty || includesHandoff, date.timeIntervalSince1970.isFinite else {
            return nil
        }
        return HistoryHidingRule(
            cutoff: usesNow ? now : min(date, now), categories: includingTypes ? categories : nil,
            includesHandoff: includingTypes && includesHandoff)
    }
}

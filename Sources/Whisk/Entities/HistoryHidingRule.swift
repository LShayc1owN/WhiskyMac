// WhiskyMac: modified or added 2026-11-19 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

/// A temporary display rule. Nil categories means all records; otherwise selected
/// types and the optional Handoff source form a union, bounded by the cutoff.
struct HistoryHidingRule: Equatable {
    let cutoff: Date
    var categories: Set<ContentCategory>?
    var includesHandoff = false

    func hides(_ item: ClipboardItem, recognition: SecretRecognition = .init()) -> Bool {
        item.copiedAt <= cutoff
            && (categories.map {
                recognition.category(of: item).isIncluded(in: $0)
                    || (includesHandoff && item.source?.origin == .handoffMarker)
            }
                ?? true)
    }
}

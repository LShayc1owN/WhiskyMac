// WhiskyMac: modified or added 2026-11-08 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

enum PinTagColor: String, Codable, CaseIterable, Hashable, Identifiable {
    case red, orange, yellow, green, blue, purple, gray
    var id: String { rawValue }
    var filterKey: String { "pin-tag:" + rawValue }
}

struct PinnedMetadata: Codable, Equatable, Hashable {
    var note = ""
    var hidesContent = false
    var tags: Set<PinTagColor> = []

    var normalized: PinnedMetadata {
        var result = self
        result.note = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        return result
    }
}

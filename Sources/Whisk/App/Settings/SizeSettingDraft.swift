// WhiskyMac: modified or added 2026-11-18 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

/// An unsaved slider value. Inline and screen previews never write preferences.
struct SizeSettingDraft {
    var proposedValue: Double?

    func value(saved: Double) -> Double { proposedValue ?? saved }
    func hasChanges(saved: Double) -> Bool { value(saved: saved) != saved }

    mutating func revert() { proposedValue = nil }

    mutating func save(using write: (Double) -> Void) {
        guard let proposedValue else { return }
        write(proposedValue)
        revert()
    }
}

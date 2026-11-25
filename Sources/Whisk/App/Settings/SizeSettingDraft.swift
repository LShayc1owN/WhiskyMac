// WhiskyMac: modified or added 2026-11-18 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

/// An unsaved size. Inline and screen previews never write preferences.
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

struct CardSizeInput {
    var locale = AppLocalization.interfaceLocale

    func format(_ value: Double) -> String {
        value.formatted(.number.locale(locale).grouping(.never).precision(.fractionLength(0...3)))
    }

    func parse(_ input: String) -> Double? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = text.replacingOccurrences(of: locale.decimalSeparator ?? ".", with: ".")
        guard let value = Double(normalized), value.isFinite else { return nil }
        return GeneralSettingsStore.boundedCardSide(value)
    }
}

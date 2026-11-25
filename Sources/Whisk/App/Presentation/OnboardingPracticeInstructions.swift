// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permissions: LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

enum OnboardingPracticeInstructions {
    static func openHistory(using bindings: KeyBindingsStore) -> String {
        if bindings.isGlobalEnabled(.togglePanel),
            !bindings.registrationFailures.contains(.togglePanel),
            !bindings.duplicatedActions.contains(.togglePanel)
        {
            return String(
                format: localized("With the text field active, press %@ to open your clipboard history."),
                bindings.label(for: .togglePanel))
        }
        return String(
            format: localized("Click the WhiskyMac menu bar icon. If a menu opens, choose “%@”."),
            localized("Show History"))
    }

    static func useSelection(using bindings: KeyBindingsStore, canPasteDirectly: Bool) -> String {
        if canPasteDirectly {
            return String(
                format: localized("Select the card you just copied. Press %@ to copy it or %@ to paste it."),
                bindings.label(for: .copySelection), bindings.label(for: .pasteSelection))
        }
        return String(
            format: localized("Select the card you just copied. Press %@, then return to the text field and press ⌘V."),
            bindings.label(for: .copySelection))
    }
}

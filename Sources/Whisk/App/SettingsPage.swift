// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, appearance, history, interactions, privacy, shortcuts
    var id: String { rawValue }
    var label: String {
        switch self {
        case .general: localized("General")
        case .appearance: localized("Appearance")
        case .history: localized("History")
        case .interactions: localized("Interactions")
        case .privacy: localized("Privacy")
        case .shortcuts: localized("Shortcuts")
        }
    }
    var summary: String {
        switch self {
        case .general: localized("Choose how WhiskyMac starts and where you open it.")
        case .appearance: localized("Make the settings and clipboard cards feel at home.")
        case .history: localized("Choose how much clipboard history to keep and for how long.")
        case .interactions: localized("Choose what clicking or hovering over a clipboard card does.")
        case .privacy: localized("Control what is recorded, displayed and fetched online.")
        case .shortcuts: localized("Set up shortcuts for quick access and keyboard navigation.")
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .history: "clock"
        case .interactions: "cursorarrow.click"
        case .privacy: "hand.raised"
        case .shortcuts: "keyboard"
        }
    }
}

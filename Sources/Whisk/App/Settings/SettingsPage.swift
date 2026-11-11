// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, appearance, history, interactions, privacy, shortcuts, about
    var id: String { rawValue }
    var label: String {
        switch self {
        case .general: localized("General")
        case .appearance: localized("Appearance")
        case .history: localized("History")
        case .interactions: localized("Interactions")
        case .privacy: localized("Privacy")
        case .shortcuts: localized("Shortcuts")
        case .about: localized("About")
        }
    }
    var title: String { label }
    var summary: String {
        switch self {
        case .general: localized("Choose how WhiskyMac starts and where you open it.")
        case .appearance: localized("Make the settings and clipboard cards feel at home.")
        case .history: localized("Choose how much clipboard history to keep and for how long.")
        case .interactions: localized("Choose what clicking or hovering over a clipboard card does.")
        case .privacy: localized("Control what is recorded, displayed and fetched online.")
        case .shortcuts: localized("Set up shortcuts for quick access and keyboard navigation.")
        case .about:
            localized(
                "Thanks for opening this page >< I hope you enjoy my work! Wishing you happiness and success every day!"
            )
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .history: "clock"
        case .interactions: "cursorarrow.click"
        case .privacy: "hand.raised.fill"
        case .shortcuts: "keyboard"
        case .about: "info.circle"
        }
    }
}

enum SettingsSectionID: String, CaseIterable, Identifiable {
    case startup, menuAndDock, language, sounds
    case statusIcons, navigation, colors, cards
    case retention, clearHistory
    case filters, normalInteractions, privacyInteractions, pinnedItems
    case screenPrivacy, privacyVisibility, sensitiveAccess, network
    case globalShortcuts, panelShortcuts, vim, resetShortcuts
    case aboutApp, aboutDeveloper, licenses

    var id: String { rawValue }

    var page: SettingsPage {
        switch self {
        case .startup, .menuAndDock, .language, .sounds: .general
        case .statusIcons, .navigation, .colors, .cards: .appearance
        case .retention, .clearHistory: .history
        case .filters, .normalInteractions, .privacyInteractions, .pinnedItems: .interactions
        case .screenPrivacy, .privacyVisibility, .sensitiveAccess, .network: .privacy
        case .globalShortcuts, .panelShortcuts, .vim, .resetShortcuts: .shortcuts
        case .aboutApp, .aboutDeveloper, .licenses: .about
        }
    }

    var title: SettingsSearchText {
        switch self {
        case .startup: settingsSearchText("Startup")
        case .menuAndDock: settingsSearchText("Menu bar and Dock")
        case .language: settingsSearchText("Language")
        case .sounds: settingsSearchText("Sounds and effects")
        case .statusIcons: settingsSearchText("Menu bar icons")
        case .navigation: settingsSearchText("Settings navigation")
        case .colors: settingsSearchText("Colors")
        case .cards: settingsSearchText("Clipboard cards")
        case .retention: settingsSearchText("Recording settings")
        case .clearHistory: settingsSearchText("Storage management")
        case .pinnedItems: settingsSearchText("Pinned items")
        case .filters: settingsSearchText("Filters")
        case .normalInteractions: settingsSearchText("Normal mode")
        case .privacyInteractions: settingsSearchText("Privacy mode")
        case .screenPrivacy: settingsSearchText("Screen privacy")
        case .privacyVisibility: settingsSearchText("Visible during protection")
        case .sensitiveAccess: settingsSearchText("Sensitive access")
        case .network: settingsSearchText("Online content")
        case .globalShortcuts: settingsSearchText("Global shortcuts")
        case .panelShortcuts: settingsSearchText("Inside the clipboard panel")
        case .vim: settingsSearchText("Vim Keybindings")
        case .resetShortcuts: settingsSearchText("Reset")
        case .aboutApp: settingsSearchText("About this App")
        case .aboutDeveloper: settingsSearchText("About the developer")
        case .licenses: settingsSearchText("Licenses and notices")
        }
    }
}

extension SettingsPage {
    func sections(isProtected: Bool) -> [SettingsSectionID] {
        SettingsSectionID.allCases.filter { $0.page == self && (!isProtected || $0 != .sensitiveAccess) }
    }
}

struct SettingsDestination: Equatable {
    let page: SettingsPage
    let sectionIndex: Int
    let section: SettingsSectionID?
    let anchor: String?

    init(page: SettingsPage, sectionIndex: Int) {
        self.page = page
        self.sectionIndex = sectionIndex
        section = nil
        anchor = nil
    }

    init(section: SettingsSectionID, anchor: String? = nil) {
        page = section.page
        sectionIndex = 0
        self.section = section
        self.anchor = anchor
    }

    func resolvedSection(isProtected: Bool) -> SettingsSectionID? {
        let available = page.sections(isProtected: isProtected)
        if let section { return available.contains(section) ? section : nil }
        return available.indices.contains(sectionIndex) ? available[sectionIndex] : available.first
    }
}

extension Notification.Name {
    static let settingsPageRequested = Notification.Name("WhiskyMac.settingsPageRequested")
}

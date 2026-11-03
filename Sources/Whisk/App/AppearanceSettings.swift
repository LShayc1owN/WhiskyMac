// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Combine
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english = "en", french = "fr", german = "de", simplifiedChinese = "zh-Hans"
    var id: String { rawValue }
    var code: String? { self == .system ? nil : rawValue }
    var label: String {
        switch self {
        case .system: localized("Follow System")
        case .english: "English"
        case .french: "Français"
        case .german: "Deutsch"
        case .simplifiedChinese: "简体中文"
        }
    }
}

enum SettingsNavigation: String, CaseIterable, Identifiable {
    case top, sidebar
    var id: String { rawValue }
    var label: String { self == .top ? localized("Top tabs") : localized("Sidebar tabs") }
}

enum StatusClickAction: String, CaseIterable, Identifiable {
    case history, menu
    var id: String { rawValue }
    var label: String { self == .history ? localized("Show clipboard cards") : localized("Show menu") }
    func opensMenu(rightClick: Bool) -> Bool { rightClick || self == .menu }
}

enum DockIconMode: String, CaseIterable, Identifiable {
    case followWindows, never, always
    var id: String { rawValue }
    var label: String {
        switch self {
        case .followWindows: localized("Follow windows")
        case .never: localized("Never show")
        case .always: localized("Always show")
        }
    }
    func isVisible(ordinaryWindowCount: Int) -> Bool {
        self == .always || (self == .followWindows && ordinaryWindowCount > 0)
    }
}

enum AccentMode: String, CaseIterable, Identifiable {
    case system, custom
    var id: String { rawValue }
    var label: String { self == .system ? localized("Follow System") : localized("Custom color") }
}

struct AccentRGB: Codable, Equatable {
    let red: Double
    let green: Double
    let blue: Double
    static let initial = AccentRGB(red: 0.31, green: 0.28, blue: 0.90)
    var nsColor: NSColor {
        NSColor(
            srgbRed: min(1, max(0, red)), green: min(1, max(0, green)),
            blue: min(1, max(0, blue)), alpha: 1)
    }
    init(red: Double, green: Double, blue: Double) {
        self.red = red.isFinite ? min(1, max(0, red)) : 0
        self.green = green.isFinite ? min(1, max(0, green)) : 0
        self.blue = blue.isFinite ? min(1, max(0, blue)) : 0
    }
    init(_ color: NSColor) {
        let rgb = color.usingColorSpace(.sRGB) ?? .controlAccentColor
        self.init(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
    }
}

/// Independent preferences. The composition root applies changes; constructing
/// a store for a test never changes global localization or application policy.
final class AppearanceSettingsStore: ObservableObject {
    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: "appLanguage"); changed?() }
    }
    @Published var navigation: SettingsNavigation {
        didSet { defaults.set(navigation.rawValue, forKey: "settingsNavigation"); changed?() }
    }
    @Published var statusClick: StatusClickAction {
        didSet { defaults.set(statusClick.rawValue, forKey: "statusClick"); changed?() }
    }
    @Published var dockIcon: DockIconMode { didSet { defaults.set(dockIcon.rawValue, forKey: "dockIcon"); changed?() } }
    @Published var accentMode: AccentMode {
        didSet { defaults.set(accentMode.rawValue, forKey: "accentMode"); changed?() }
    }
    @Published var customAccent: AccentRGB {
        didSet {
            if let value = try? JSONEncoder().encode(customAccent) { defaults.set(value, forKey: "customAccent") }
            changed?()
        }
    }
    private let defaults: UserDefaults
    var changed: (() -> Void)?
    var nsAccent: NSColor { accentMode == .system ? .controlAccentColor : customAccent.nsColor }
    var accent: Color { Color(nsColor: nsAccent) }

    init(defaults: UserDefaults = AppIdentity.defaults) {
        self.defaults = defaults
        language = AppLanguage(rawValue: defaults.string(forKey: "appLanguage") ?? "") ?? .system
        navigation = SettingsNavigation(rawValue: defaults.string(forKey: "settingsNavigation") ?? "") ?? .top
        statusClick = StatusClickAction(rawValue: defaults.string(forKey: "statusClick") ?? "") ?? .history
        dockIcon = DockIconMode(rawValue: defaults.string(forKey: "dockIcon") ?? "") ?? .followWindows
        accentMode = AccentMode(rawValue: defaults.string(forKey: "accentMode") ?? "") ?? .system
        customAccent =
            defaults.data(forKey: "customAccent").flatMap { try? JSONDecoder().decode(AccentRGB.self, from: $0) }
            ?? .initial
    }
}

/// Views in the existing upstream theme read this value. Kept out of settings
/// storage so synthetic stores cannot recolor another live application session.
enum AppAccent {
    static var color = NSColor.controlAccentColor
}

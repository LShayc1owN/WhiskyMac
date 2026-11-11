// WhiskyMac: modified or added 2026-11-07 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Combine
import Foundation

/// Keeps the English search text and the localized display text together.
struct SettingsSearchText {
    let key: String
    var localized: String { Whisk.localized(String.LocalizationValue(key)) }
}

func settingsSearchText(_ key: String) -> SettingsSearchText { SettingsSearchText(key: key) }

struct SettingsSearchContext: Equatable {
    var isProtected = false
    var checksForUpdates = Distribution.current.checksForUpdates
    var customAccent = false
    var normalHover = false
    var privacyHover = false
    var automaticProtection = false
    var vimEnabled = false
}

struct SettingsSearchEntry: Identifiable {
    let id: String
    let section: SettingsSectionID
    let title: SettingsSearchText
    var keywords: SettingsSearchText?
    var anchor: String?

    var symbol: String {
        switch section {
        case .startup: "power"
        case .menuAndDock: "dock.rectangle"
        case .language: "globe"
        case .sounds: "speaker.wave.2"
        case .statusIcons: "menubar.rectangle"
        case .navigation: "sidebar.left"
        case .colors: "paintpalette"
        case .cards: "rectangle.3.group"
        case .retention: "clock"
        case .clearHistory: "internaldrive"
        case .filters: "line.3.horizontal.decrease.circle"
        case .screenPrivacy, .privacyVisibility, .sensitiveAccess: "hand.raised.fill"
        case .network: "network"
        case .globalShortcuts, .panelShortcuts, .vim: "keyboard"
        case .resetShortcuts: "arrow.counterclockwise"
        case .licenses: "doc.text"
        case .aboutDeveloper: "person.crop.circle"
        default: section.page.symbol
        }
    }

    var path: String { "\(section.page.label) › \(section.title.localized)" }
    var destination: SettingsDestination { SettingsDestination(section: section, anchor: anchor ?? id) }
}

enum SettingsSearchIndex {
    static func matchingRanges(in text: String, query: String) -> [Range<String.Index>] {
        query.split(whereSeparator: \.isWhitespace).flatMap { word in
            var ranges: [Range<String.Index>] = []
            var start = text.startIndex
            while start < text.endIndex,
                let range = text.range(
                    of: String(word), options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                    range: start..<text.endIndex, locale: Locale(identifier: "en_US_POSIX"))
            {
                guard !range.isEmpty else { break }
                ranges.append(range)
                start = range.upperBound
            }
            return ranges
        }
    }

    static func entries(context: SettingsSearchContext) -> [SettingsSearchEntry] {
        var entries: [SettingsSearchEntry] = []
        func add(
            _ id: String, _ section: SettingsSectionID, _ title: SettingsSearchText,
            keywords: SettingsSearchText? = nil, anchor: String? = nil
        ) {
            guard !context.isProtected || section != .sensitiveAccess else { return }
            entries.append(
                SettingsSearchEntry(id: id, section: section, title: title, keywords: keywords, anchor: anchor))
        }
        add("pinnedPresentation", .pinnedItems, settingsSearchText("Pinned items presentation"))
        add("pinnedWindowStyle", .pinnedItems, settingsSearchText("Pinned window layout"))
        add("launch", .startup, settingsSearchText("Launch WhiskyMac at login"))
        if context.checksForUpdates {
            add("startupUpdates", .startup, settingsSearchText("Check for updates at launch"))
            add("checkUpdates", .aboutApp, settingsSearchText("Check for updates"))
        }
        add("statusClick", .menuAndDock, settingsSearchText("Menu bar icon click"))
        add("dockIcon", .menuAndDock, settingsSearchText("Dock icon"))
        add("language", .language, settingsSearchText("Language"))
        add("captureSound", .sounds, settingsSearchText("Play a sound when a new copy is recorded"))
        add("historySound", .sounds, settingsSearchText("Play a sound when copying from history"))
        add("copySound", .sounds, settingsSearchText("Copy sound"))
        add("volume", .sounds, settingsSearchText("Sound volume"), keywords: settingsSearchText("volume audio mute"))
        add("defaultIcon", .statusIcons, settingsSearchText("Default mode icon"))
        add("privacyIcon", .statusIcons, settingsSearchText("Privacy mode icon"))
        add(
            "navigation", .navigation, settingsSearchText("Settings layout"),
            keywords: settingsSearchText("sidebar tabs navigation"))
        add("accent", .colors, settingsSearchText("Accent color"))
        add("customAccent", .colors, settingsSearchText("Custom color"), anchor: context.customAccent ? nil : "accent")
        add(
            "cardSize", .cards, settingsSearchText("Card size"),
            keywords: settingsSearchText("size width preview restore default"))
        add("retention", .retention, settingsSearchText("Keep history for"))
        add("capacity", .clearHistory, settingsSearchText("History capacity"))
        add(
            "clearHistory", .clearHistory, settingsSearchText("Clear Unpinned Items"),
            keywords: settingsSearchText("clear history delete history empty history"))
        add("filterTrigger", .filters, settingsSearchText("Application filter trigger"))
        for (section, prefix, enabled) in [
            (SettingsSectionID.normalInteractions, "normal", context.normalHover),
            (.privacyInteractions, "private", context.privacyHover),
        ] {
            add("\(prefix).single", section, settingsSearchText("Single click"))
            add("\(prefix).double", section, settingsSearchText("Double click"))
            add("\(prefix).right", section, settingsSearchText("Right click"))
            add("\(prefix).hover", section, settingsSearchText("Hover after a short delay"))
            add(
                "\(prefix).delay", section, settingsSearchText("Hover delay (seconds)"),
                anchor: enabled ? nil : "\(prefix).hover")
        }
        add("manualPrivacy", .screenPrivacy, settingsSearchText("Manual Privacy Mode"))
        add("automaticPrivacy", .screenPrivacy, settingsSearchText("Automatic protection (limited detection)"))
        add("detection", .screenPrivacy, settingsSearchText("Detection coverage"))
        add(
            "accessibility", .screenPrivacy, settingsSearchText("Allow Accessibility for toolbar detection…"),
            anchor: context.automaticProtection ? nil : "automaticPrivacy")
        add("privacySearch", .privacyVisibility, settingsSearchText("Allow search in Privacy Mode"))
        add("privacyFilters", .privacyVisibility, settingsSearchText("Allow filtering in Privacy Mode"))
        add("privacySources", .privacyVisibility, settingsSearchText("Show source apps in Privacy Mode"))
        add(
            "diameter", .privacyInteractions, settingsSearchText("Diameter"),
            keywords: settingsSearchText("Hover reveal area"))
        add(
            "blur", .privacyInteractions, settingsSearchText("Edge blur radius"),
            keywords: settingsSearchText("Hover reveal area"))
        add("resetSpotlight", .privacyInteractions, settingsSearchText("Restore default values"))
        add("sensitiveApps", .sensitiveAccess, settingsSearchText("Sensitive apps"))
        add("sensitiveRetention", .sensitiveAccess, settingsSearchText("Keep sensitive copies for"))
        add("excludedApps", .sensitiveAccess, settingsSearchText("Excluded apps"))
        add("linkPreviews", .network, settingsSearchText("Fetch link previews"))
        for action in KeyAction.allCases {
            add("shortcut.\(action.rawValue)", action.isGlobal ? .globalShortcuts : .panelShortcuts, action.searchTitle)
        }
        add("vim", .vim, settingsSearchText("Vim navigation in the panel"))
        for action in VimAction.allCases {
            add("vim.\(action.rawValue)", .vim, action.searchTitle, anchor: context.vimEnabled ? nil : "vim")
        }
        add("resetCategory", .resetShortcuts, settingsSearchText("Reset category"))
        add("resetShortcuts", .resetShortcuts, settingsSearchText("Reset keyboard shortcuts"))
        add("version", .aboutApp, settingsSearchText("Version and introduction"))
        add(
            "repositories", .aboutApp, settingsSearchText("Source repositories"),
            keywords: settingsSearchText("GitHub repository source code"))
        add("dependencies", .aboutApp, settingsSearchText("Dependencies and credits"))
        add("translations", .aboutApp, settingsSearchText("Translation contributors"))
        add("feedback", .aboutApp, settingsSearchText("Report a bug on GitHub"))
        add(
            "developer", .aboutDeveloper, settingsSearchText("About the developer"),
            keywords: settingsSearchText("Lin Shay contact"))
        add("licenses", .licenses, settingsSearchText("Licenses and notices"))
        return entries
    }

    static func matches(_ query: String, context: SettingsSearchContext) -> [SettingsSearchEntry] {
        let query = normalized(query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return entries(context: context).enumerated().compactMap {
            position, entry -> (Int, Int, SettingsSearchEntry)? in
            let titles = [entry.title.localized, entry.title.key].map(normalized)
            let paths = [entry.path, "\(entry.section.page.rawValue) \(entry.section.title.key)"].map(normalized)
            let keywords = [entry.keywords?.localized ?? "", entry.keywords?.key ?? ""].map(normalized)
            let score: Int
            if titles.contains(query) {
                score = 0
            } else if titles.contains(where: { $0.hasPrefix(query) }) {
                score = 1
            } else if titles.contains(where: { text in words.allSatisfy { text.contains($0) } }) {
                score = 2
            } else if paths.contains(where: { text in words.allSatisfy { text.contains($0) } }) {
                score = 3
            } else if words.allSatisfy({ word in (titles + paths + keywords).contains { $0.contains(word) } }) {
                score = 4
            } else {
                return nil
            }
            return (score, position, entry)
        }.sorted { ($0.0, $0.1) < ($1.0, $1.1) }.map(\.2)
    }

    private static func normalized(_ text: String) -> String {
        text.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX"))
    }
}

final class SettingsSearchModel: ObservableObject {
    @Published var query = "" { didSet { if query != oldValue { updateResults() } } }
    @Published private(set) var results: [SettingsSearchEntry] = []
    @Published private(set) var selectedIndex = 0
    @Published private(set) var keyboardSelectionRevision = 0
    @Published var isPresented = false
    @Published private(set) var focusRevision = 0
    @Published private(set) var navigationRevision = 0
    @Published private(set) var destination: SettingsDestination?
    @Published private(set) var highlightedAnchor: String?
    @Published private(set) var localizationRevision = 0
    private(set) var context = SettingsSearchContext()
    private var highlightTask: Task<Void, Never>?

    func refresh(context: SettingsSearchContext) {
        let wasPresented = isPresented
        self.context = context
        localizationRevision += 1
        updateResults()
        isPresented = wasPresented && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if destination?.resolvedSection(isProtected: context.isProtected) == nil {
            highlightedAnchor = nil
        }
    }

    func focus() {
        focusRevision += 1
        isPresented = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        isPresented = true
        selectedIndex = min(max(0, selectedIndex + delta), results.count - 1)
        keyboardSelectionRevision += 1
    }

    func hover(at index: Int) {
        guard isPresented, results.indices.contains(index), selectedIndex != index else { return }
        selectedIndex = index
    }

    func activateSelection() {
        guard isPresented, results.indices.contains(selectedIndex) else { return }
        activate(results[selectedIndex].id)
    }

    func activate(_ id: String) {
        // Re-resolve prerequisites and availability at the moment of activation.
        guard let entry = SettingsSearchIndex.entries(context: context).first(where: { $0.id == id }) else { return }
        navigate(to: entry.destination)
    }

    func navigate(to requested: SettingsDestination) {
        guard let section = requested.resolvedSection(isProtected: context.isProtected) else { return }
        highlightTask?.cancel()
        query = ""
        isPresented = false
        destination = SettingsDestination(section: section, anchor: requested.anchor)
        highlightedAnchor = requested.anchor
        navigationRevision += 1
        guard highlightedAnchor != nil else { return }
        highlightTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.highlightedAnchor = nil
        }
    }

    func dismiss() { isPresented = false }

    func reset() {
        highlightTask?.cancel()
        highlightTask = nil
        query = ""
        isPresented = false
        highlightedAnchor = nil
        destination = nil
    }

    private func updateResults() {
        results = SettingsSearchIndex.matches(query, context: context)
        selectedIndex = 0
        isPresented = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

/// The vim layer's editable keymap. A binding is what the keys type — one
/// or two characters; a two-character binding (gg, dd) runs on the double
/// tap. Matching by typed character keeps every layout native. Esc, Tab,
/// the / alias and the 1–9 direct pastes are fixed.
enum VimAction: String, CaseIterable, Identifiable {
    case previousCard
    case nextCard
    case rowUp
    case rowDown
    case firstCard
    case lastCard
    case paste
    case pastePlain
    case preview
    case stackToggle
    case pinToggle
    case deleteSelection
    case search
    case clearSearch
    case closePanel
    case copy
    case open
    case reveal
    case save
    case excludeSource
    case deleteFromSource
    case edit
    case undo

    var id: String { rawValue }

    var displayName: String { searchTitle.localized }

    var searchTitle: SettingsSearchText {
        switch self {
        case .previousCard: settingsSearchText("Previous card or chip")
        case .nextCard: settingsSearchText("Next card or chip")
        case .rowUp: settingsSearchText("Focus the row above")
        case .rowDown: settingsSearchText("Focus the row below")
        case .firstCard: settingsSearchText("First card")
        case .lastCard: settingsSearchText("Last card")
        case .paste: settingsSearchText("Paste the selection")
        case .pastePlain: settingsSearchText("Paste as plain text")
        case .preview: settingsSearchText("Preview the selection")
        case .stackToggle: settingsSearchText("Toggle the selection in the paste stack")
        case .pinToggle: settingsSearchText("Pin / unpin the selection")
        case .deleteSelection: settingsSearchText("Delete the selection")
        case .search: settingsSearchText("Start a search")
        case .clearSearch: settingsSearchText("Clear the search")
        case .closePanel: settingsSearchText("Close the panel")
        case .copy: settingsSearchText("Copy the selection without pasting")
        case .open: settingsSearchText("Open the selected link")
        case .reveal: settingsSearchText("Reveal the selected files in Finder")
        case .save: settingsSearchText("Save the selection as a file")
        case .excludeSource: settingsSearchText("Exclude the selection's application")
        case .deleteFromSource: settingsSearchText("Delete everything from the selection's application")
        case .edit: settingsSearchText("Edit the selection")
        case .undo: settingsSearchText("Undo the last deletion or edit")
        }
    }

    var defaultKey: String {
        switch self {
        case .previousCard: "h"
        case .nextCard: "l"
        case .rowUp: "k"
        case .rowDown: "j"
        case .firstCard: "gg"
        case .lastCard: "G"
        case .paste: "p"
        case .pastePlain: "P"
        case .preview: "v"
        case .stackToggle: "m"
        case .pinToggle: "f"
        case .deleteSelection: "dd"
        case .search: "s"
        case .clearSearch: "c"
        case .closePanel: "q"
        case .copy: "y"
        case .open: "o"
        case .reveal: "r"
        case .save: "w"
        case .excludeSource: "X"
        case .deleteFromSource: "D"
        case .edit: "e"
        case .undo: "u"
        }
    }
}

/// Persists only the customized bindings; everything else follows the
/// defaults, so new actions pick their key up automatically.
final class VimBindingsStore: ObservableObject {
    @Published private(set) var keys: [VimAction: String]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppIdentity.defaults) {
        self.defaults = defaults
        let stored = defaults.dictionary(forKey: "vimBindings") as? [String: String] ?? [:]
        var map: [VimAction: String] = [:]
        for action in VimAction.allCases {
            map[action] = stored[action.rawValue] ?? action.defaultKey
        }
        keys = map
    }

    func key(for action: VimAction) -> String {
        keys[action] ?? action.defaultKey
    }

    /// One or two printable characters; anything else falls back to the
    /// action's default.
    func set(_ key: String, for action: VimAction) {
        let trimmed = String(key.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2))
        keys[action] = trimmed.isEmpty ? action.defaultKey : trimmed
        persist()
    }

    func reset(_ action: VimAction) {
        keys[action] = action.defaultKey
        persist()
    }

    func resetAll() {
        var map: [VimAction: String] = [:]
        for action in VimAction.allCases {
            map[action] = action.defaultKey
        }
        keys = map
        persist()
    }

    func restoreBindings(_ saved: [VimAction: String]) {
        keys = saved
        persist()
    }

    func isCustomized(_ action: VimAction) -> Bool {
        key(for: action) != action.defaultKey
    }

    var duplicatedActions: Set<VimAction> {
        var seen: [String: VimAction] = [:]
        var duplicates: Set<VimAction> = []
        for action in VimAction.allCases {
            let key = key(for: action)
            if let other = seen[key] {
                duplicates.insert(other)
                duplicates.insert(action)
            } else {
                seen[key] = action
            }
        }
        return duplicates
    }

    /// True when some binding starts with this character but needs more.
    func isSequencePrefix(_ character: String) -> Bool {
        keys.values.contains { $0.count == 2 && $0.hasPrefix(character) && $0 != character }
    }

    func action(for key: String) -> VimAction? {
        VimAction.allCases.first { self.key(for: $0) == key }
    }

    private func persist() {
        var stored: [String: String] = [:]
        for (action, key) in keys where key != action.defaultKey {
            stored[action.rawValue] = key
        }
        defaults.set(stored, forKey: "vimBindings")
    }
}

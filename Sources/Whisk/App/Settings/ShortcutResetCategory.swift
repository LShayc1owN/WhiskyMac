// WhiskyMac: modified or added 2026-11-11 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

enum ShortcutResetCategory: String, CaseIterable, Identifiable {
    case global, panel, vim
    var id: String { rawValue }
    var label: String {
        switch self {
        case .global: localized("Global shortcuts")
        case .panel: localized("Inside the clipboard panel")
        case .vim: localized("Vim Keybindings")
        }
    }
    var explanation: String {
        switch self {
        case .global:
            localized("Restores global shortcuts and turns them off.")
        case .panel: localized("Restores panel shortcuts.")
        case .vim:
            localized("Restores Vim bindings without changing Vim navigation.")
        }
    }
    func reset(keys: KeyBindingsStore, vim: VimBindingsStore) {
        switch self {
        case .global: keys.resetCategory(global: true)
        case .panel: keys.resetCategory(global: false)
        case .vim: vim.resetAll()
        }
    }
    static func reset(_ categories: Set<ShortcutResetCategory>, keys: KeyBindingsStore, vim: VimBindingsStore) {
        if categories == Set(allCases) { keys.resetAll(); vim.resetAll(); return }
        for category in allCases where categories.contains(category) { category.reset(keys: keys, vim: vim) }
    }

}

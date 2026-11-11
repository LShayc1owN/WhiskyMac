// WhiskyMac: modified or added 2026-11-11 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Testing

@testable import Whisk

@MainActor
@Suite struct ShortcutResetCategories {
    @Test func each_reset_only_changes_the_selected_category_and_persists() throws {
        // All eight subsets, including empty selection and two-category combinations.
        for mask in 0..<8 {
            let categories = Set(
                ShortcutResetCategory.allCases.enumerated().compactMap { index, category in
                    mask & (1 << index) == 0 ? nil : category
                })
            let sandbox = try IsolatedDefaults()
            let keys = KeyBindingsStore(defaults: sandbox.defaults)
            let vim = VimBindingsStore(defaults: sandbox.defaults)
            let defaults = KeyBindingsStore(defaults: try IsolatedDefaults().defaults)
            let globals = KeyAction.allCases.filter(\.isGlobal)
            let panels = KeyAction.allCases.filter { !$0.isGlobal }
            let custom = KeyBinding(keyCode: 3, modifiers: [.control, .shift])
            for action in KeyAction.allCases { keys.set(custom, for: action) }
            for action in VimAction.allCases { vim.set("zz", for: action) }
            keys.registrationFailures = Set(KeyAction.allCases)
            let general = GeneralSettingsStore(defaults: sandbox.defaults)
            general.vimNavigation = true
            ShortcutResetCategory.reset(categories, keys: keys, vim: vim)
            let restored = KeyBindingsStore(defaults: sandbox.defaults)
            for action in globals {
                let changed = categories.contains(.global)
                #expect(restored.binding(for: action) == (changed ? defaults.binding(for: action) : custom))
                #expect(restored.isGlobalEnabled(action) == !changed)
            }
            for action in panels {
                let changed = categories.contains(.panel)
                #expect(restored.binding(for: action) == (changed ? defaults.binding(for: action) : custom))
            }
            let restoredVim = VimBindingsStore(defaults: sandbox.defaults)
            for action in VimAction.allCases {
                #expect(
                    restoredVim.key(for: action) == (categories.contains(.vim) ? action.defaultKey : "zz"))
            }
            #expect(GeneralSettingsStore(defaults: sandbox.defaults).vimNavigation)
            let cleared = Set(
                KeyAction.allCases.filter { $0.isGlobal ? categories.contains(.global) : categories.contains(.panel) })
            #expect(keys.registrationFailures == Set(KeyAction.allCases).subtracting(cleared))
            for category in ShortcutResetCategory.allCases {
                #expect(category.id == category.rawValue && !category.label.isEmpty && !category.explanation.isEmpty)
            }

        }
    }

    @Test func category_reset_cancels_only_its_active_recorder_and_all_reset_cancels_any_recorder() throws {
        let sandbox = try IsolatedDefaults()
        let keys = KeyBindingsStore(defaults: sandbox.defaults)
        keys.beginRecording(.togglePinned)
        keys.resetCategory(global: false)
        #expect(keys.recordingAction == .togglePinned)
        keys.resetCategory(global: true)
        #expect(keys.recordingAction == nil)
        keys.beginRecording(.copySelection)
        keys.resetCategory(global: false)
        #expect(keys.recordingAction == nil)
        keys.beginRecording(.togglePanel)
        keys.resetAll()
        #expect(keys.recordingAction == nil)
    }
}

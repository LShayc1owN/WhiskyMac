// WhiskyMac: modified or added 2026-11-11 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI
import Testing

@testable import Whisk

@MainActor
@Suite struct ShortcutResetUndoTests {
    @MainActor
    private final class Fixture {
        let defaults: IsolatedDefaults
        let keys: KeyBindingsStore
        let vim: VimBindingsStore
        var time: TimeInterval = 10
        var scheduled: [(TimeInterval, DispatchWorkItem)] = []
        lazy var undo = ShortcutResetUndo(
            now: { [unowned self] in time },
            schedule: { [unowned self] delay, work in scheduled.append((delay, work)) })

        init() throws {
            defaults = try IsolatedDefaults()
            keys = KeyBindingsStore(defaults: defaults.defaults)
            vim = VimBindingsStore(defaults: defaults.defaults)
            keys.set(KeyBinding(keyCode: 3, modifiers: [.control, .shift]), for: .togglePanel)
            keys.setGlobalEnabled(false, for: .togglePanel)
            keys.set(KeyBinding(keyCode: 5, modifiers: [.command]), for: .togglePrivacy)
            keys.set(KeyBinding(keyCode: 8, modifiers: [.option]), for: .copySelection)
            vim.set("zz", for: .copy)
        }

        func reset(_ categories: Set<ShortcutResetCategory>) {
            undo.reset(categories, keys: keys, vim: vim)
        }
    }

    @Test func undo_restores_exact_overrides_and_enabled_flags_for_every_selection_and_persists() throws {
        for mask in 0..<8 {
            let f = try Fixture()
            let categories = Set(
                ShortcutResetCategory.allCases.enumerated().compactMap { index, category in
                    mask & (1 << index) == 0 ? nil : category
                })
            let overrides = f.keys.overrides
            let enabled = f.keys.enabledGlobalActions
            let vim = f.vim.keys
            f.reset(categories)
            #expect(f.undo.isPresented == !categories.isEmpty)
            #expect(f.undo.undo(keys: f.keys, vim: f.vim) == !categories.isEmpty)
            #expect(f.keys.overrides == overrides)
            #expect(f.keys.enabledGlobalActions == enabled)
            #expect(f.vim.keys == vim)
            #expect(!f.undo.isPresented)
            #expect(!f.undo.undo(keys: f.keys, vim: f.vim))
            let reopened = KeyBindingsStore(defaults: f.defaults.defaults)
            #expect(reopened.overrides == overrides)
            #expect(reopened.enabledGlobalActions == enabled)
            #expect(VimBindingsStore(defaults: f.defaults.defaults).keys == vim)
            #expect(f.scheduled.allSatisfy { $0.1.isCancelled })
        }
    }

    @Test func deadline_is_exact_even_if_main_queue_has_not_delivered_expiration() throws {
        let f = try Fixture()
        #expect(f.undo.remainingFraction == 0)
        f.reset([.global])
        #expect(f.scheduled.first?.0 == 5)
        #expect(f.undo.remainingFraction == 1)
        f.time += 2.5
        #expect(f.undo.remainingFraction == 0.5)
        f.time = 14.999
        #expect(f.undo.undo(keys: f.keys, vim: f.vim))
        f.reset([.global])
        f.time += 5
        #expect(f.undo.remainingFraction == 0)
        #expect(!f.undo.undo(keys: f.keys, vim: f.vim))
        #expect(!f.undo.isPresented)
        #expect(f.keys.enabledGlobalActions.isEmpty)
    }

    @Test func automatic_expiry_and_dismissal_release_undo_and_old_timer_cannot_dismiss_new_reset() throws {
        let f = try Fixture()
        f.reset([.global])
        let old = try #require(f.scheduled.last?.1)
        f.reset([.vim])
        #expect(old.isCancelled)
        old.perform()
        #expect(f.undo.isPresented)
        try #require(f.scheduled.last?.1).perform()
        #expect(!f.undo.isPresented)
        #expect(!f.undo.undo(keys: f.keys, vim: f.vim))
        f.reset([.panel])
        f.undo.dismiss()
        #expect(!f.undo.isPresented)
        #expect(f.scheduled.last?.1.isCancelled == true)
    }

    @Test func only_most_recent_reset_can_be_undone_and_unrelated_changes_are_preserved() throws {
        let f = try Fixture()
        let vim = f.vim.keys
        f.reset([.global])
        f.reset([.vim])
        let binding = KeyBinding(keyCode: 6, modifiers: [.command, .option])
        f.keys.set(binding, for: .copySelection)
        f.undo.invalidateIfChanged(keys: f.keys, vim: f.vim)
        #expect(f.undo.isPresented)
        #expect(f.undo.undo(keys: f.keys, vim: f.vim))
        #expect(f.vim.keys == vim)
        #expect(f.keys.binding(for: .copySelection) == binding)
        #expect(f.keys.enabledGlobalActions.isEmpty)
    }

    @Test func new_changes_in_selected_categories_invalidate_undo_without_overwriting_them() throws {
        for category in ShortcutResetCategory.allCases {
            let f = try Fixture()
            f.reset([category])
            switch category {
            case .global: f.keys.setGlobalEnabled(true, for: .togglePanel)
            case .panel: f.keys.set(KeyBinding(keyCode: 1, modifiers: [.control]), for: .copySelection)
            case .vim: f.vim.set("ab", for: .copy)
            }
            #expect(!f.undo.undo(keys: f.keys, vim: f.vim))
            #expect(!f.undo.isPresented)
        }
    }

    @Test func undo_does_not_restore_stale_registration_errors_or_resume_a_recorder() throws {
        let f = try Fixture()
        f.keys.registrationFailures = [.togglePanel, .copySelection]
        f.reset([.global])
        f.keys.beginRecording(.togglePanel)
        #expect(f.undo.undo(keys: f.keys, vim: f.vim))
        #expect(f.keys.recordingAction == nil)
        #expect(f.keys.registrationFailures == [.copySelection])
    }

    @Test func toast_keeps_the_same_size_as_its_border_counts_down() throws {
        _ = NSApplication.shared
        let f = try Fixture()
        f.reset([.global])
        var size: NSSize?
        for elapsed in [0.0, 2.5, 4.9] {
            f.time = 10 + elapsed
            let content = ShortcutResetToast(undo: f.undo, accent: .mint) {}
                .padding(10)
            let host = NSHostingView(rootView: content)
            let window = NSWindow(
                contentRect: NSRect(x: -10000, y: -10000, width: 460, height: 80),
                styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = host
            host.frame = window.contentLayoutRect
            defer { window.close() }
            host.layoutSubtreeIfNeeded()
            if let size { #expect(host.fittingSize == size) } else { size = host.fittingSize }
            #expect(host.fittingSize.width <= 460)
            if let output = ProcessInfo.processInfo.environment["WHISK_UI_ARTIFACTS"] {
                let directory = URL(fileURLWithPath: output)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(
                    to: directory.appendingPathComponent("reset-toast-\(elapsed).png"))
            }
        }
    }
}

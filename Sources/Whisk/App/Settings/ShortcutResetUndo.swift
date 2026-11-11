// WhiskyMac: modified or added 2026-11-11 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

/// A single, memory-only undo opportunity for five seconds after a category reset.
@MainActor
final class ShortcutResetUndo: ObservableObject {
    static let duration: TimeInterval = 5
    @Published private(set) var isPresented = false

    var remainingFraction: Double {
        guard let pending else { return 0 }
        return min(1, max(0, (pending.deadline - now()) / Self.duration))
    }

    private struct Snapshot: Equatable {
        var overrides: [String: KeyBinding]
        var enabledGlobals: Set<KeyAction>?
        var vim: [VimAction: String]?

        init(categories: Set<ShortcutResetCategory>, keys: KeyBindingsStore, vim: VimBindingsStore) {
            overrides = keys.overrides.filter { name, _ in
                guard let action = KeyAction(rawValue: name) else { return false }
                return categories.contains(action.isGlobal ? .global : .panel)
            }
            enabledGlobals = categories.contains(.global) ? keys.enabledGlobalActions : nil
            self.vim = categories.contains(.vim) ? vim.keys : nil
        }
    }

    private struct Pending {
        let id: UUID
        let categories: Set<ShortcutResetCategory>
        let before: Snapshot
        let after: Snapshot
        let deadline: TimeInterval
    }

    private let now: () -> TimeInterval
    private let schedule: (TimeInterval, DispatchWorkItem) -> Void
    private var pending: Pending?
    private var expiration: DispatchWorkItem?

    init(
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        schedule: @escaping (TimeInterval, DispatchWorkItem) -> Void = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    ) {
        self.now = now
        self.schedule = schedule
    }

    func reset(_ categories: Set<ShortcutResetCategory>, keys: KeyBindingsStore, vim: VimBindingsStore) {
        guard !categories.isEmpty else { return }
        dismiss()
        let before = Snapshot(categories: categories, keys: keys, vim: vim)
        ShortcutResetCategory.reset(categories, keys: keys, vim: vim)
        let id = UUID()
        pending = Pending(
            id: id, categories: categories, before: before,
            after: Snapshot(categories: categories, keys: keys, vim: vim), deadline: now() + Self.duration)
        isPresented = true
        let work = DispatchWorkItem { [weak self] in
            guard self?.pending?.id == id else { return }
            self?.dismiss()
        }
        expiration = work
        schedule(Self.duration, work)
    }

    func invalidateIfChanged(keys: KeyBindingsStore, vim: VimBindingsStore) {
        guard let pending else { return }
        if now() >= pending.deadline
            || Snapshot(categories: pending.categories, keys: keys, vim: vim) != pending.after
        {
            dismiss()
        }
    }

    @discardableResult
    func undo(keys: KeyBindingsStore, vim: VimBindingsStore) -> Bool {
        invalidateIfChanged(keys: keys, vim: vim)
        guard let pending else { return false }
        dismiss()
        let actions = Set(
            KeyAction.allCases.filter { pending.categories.contains($0.isGlobal ? .global : .panel) })
        if !actions.isEmpty {
            keys.restoreBindings(
                pending.before.overrides, for: actions, enabledGlobals: pending.before.enabledGlobals)
        }
        if let saved = pending.before.vim { vim.restoreBindings(saved) }
        return true
    }

    func dismiss() {
        expiration?.cancel()
        expiration = nil
        pending = nil
        isPresented = false
    }

    deinit { expiration?.cancel() }
}

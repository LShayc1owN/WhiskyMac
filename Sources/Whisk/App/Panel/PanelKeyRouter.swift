// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Carbon.HIToolbox

/// Routes the panel's key presses: vim's normal mode first, then the
/// user's bindings, then the fixed keys (⌘digits, keypad Enter). Decides
/// over an NSEvent alone; what a key may do to windows — preview, close —
/// comes in as closures, so the whole table can be driven by synthetic
/// presses.
final class PanelKeyRouter {
    private let stateStore: HistoryViewStateStore
    private let actions: PanelActions
    private let keyBindings: KeyBindingsStore
    private let vimBindings: VimBindingsStore
    private let togglePreview: () -> Void
    private let closePanel: () -> Void
    private let now: () -> Date

    /// A two-key vim sequence in flight (gg, dd) and when it started.
    private var vimPendingKey: (key: String, at: Date)?
    private static let sequenceWindow: TimeInterval = 0.8

    init(
        stateStore: HistoryViewStateStore,
        actions: PanelActions,
        keyBindings: KeyBindingsStore,
        vimBindings: VimBindingsStore,
        togglePreview: @escaping () -> Void,
        closePanel: @escaping () -> Void,
        now: @escaping () -> Date = Date.init
    ) {
        self.stateStore = stateStore
        self.actions = actions
        self.keyBindings = keyBindings
        self.vimBindings = vimBindings
        self.togglePreview = togglePreview
        self.closePanel = closePanel
        self.now = now
    }

    /// Routes panel keys through the user's bindings, intercepted ahead of
    /// the search field's caret. True when the key was consumed.
    func handle(_ event: NSEvent) -> Bool {
        // A metadata popover owns its text input; card shortcuts must not
        // paste/delete a record while someone types a note.
        if stateStore.splitSession != nil || stateStore.splitGroupSession != nil || !stateStore.splitVersions.isEmpty {
            return false
        }
        if (stateStore.pinMetadataEditing || stateStore.cardMenuOpen), !stateStore.isProtected { return false }
        if stateStore.isPinnedList, !stateStore.isProtected,
            event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        {
            if event.keyCode == UInt16(kVK_UpArrow) { actions.navigate(.left); return true }
            if event.keyCode == UInt16(kVK_DownArrow) { actions.navigate(.right); return true }
        }
        if stateStore.isProtected {
            // Native filter buttons may navigate/activate; never run card commands.
            if stateStore.privacyAllowsFiltering,
                event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
                [kVK_Tab, kVK_Space, kVK_Return, kVK_ANSI_KeypadEnter].contains(Int(event.keyCode))
            {
                return false
            }
            if event.keyCode == UInt16(kVK_Escape) { return false }
            if stateStore.privacyAllowsSearch {
                // Let the protected search field edit text, never run card commands.
                return event.specialKey == .carriageReturn || event.specialKey == .enter
            }
            return true
        }
        // While the editor is open the keys are the editor's, but for one:
        // Return saves, Shift-Return breaks the line — before either input
        // mode gets a say. Escape takes the panel's own cancel path.
        if stateStore.editing != nil {
            let isReturn = event.specialKey == .carriageReturn || event.specialKey == .enter
            guard isReturn, !event.modifierFlags.contains(.shift) else { return false }
            let text = stateStore.editingText
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
            stateStore.saveEditing(actions: actions)
            return true
        }
        // Vim's search commits like /: Return keeps the query and filter
        // and returns to normal mode — the paste stays one p away.
        if stateStore.vimEnabled, stateStore.searchActive,
            event.specialKey == .carriageReturn || event.specialKey == .enter
        {
            stateStore.setSearchActive(false)
            return true
        }
        if handleVimNormal(event) {
            return true
        }
        let panelActions: [(KeyAction, () -> Void)] = [
            (.pastePlain, { self.actions.activatePlain() }),
            (.pasteSelection, { self.actions.activate() }),
            (.previousCard, { self.actions.navigate(.left) }),
            (.nextCard, { self.actions.navigate(.right) }),
            (.rowUp, { self.actions.navigate(.up) }),
            (.rowDown, { self.actions.navigate(.down) }),
            (.switchChipGroup, { self.actions.switchChipGroup() }),
            (.pinSelection, { self.actions.togglePinSelected() }),
            (.deleteSelection, { self.actions.deleteSelected() }),
            (.stackSelection, { self.actions.stackSelected() }),
            (.copySelection, { self.actions.copySelected() }),
            (.openSelection, { self.openSelected() }),
            (.revealSelection, { self.revealSelected() }),
            (.saveSelection, { self.saveSelected() }),
            (.excludeSelectionSource, { self.excludeSelectedSource() }),
            (.deleteSelectionSource, { self.deleteFromSelectedSource() }),
            (.editSelection, { self.editSelected() }),
            (.undoLastChange, { self.actions.undo() }),
        ]
        for (action, perform) in panelActions where keyBindings.binding(for: action).matches(event) {
            perform()
            return true
        }
        if let index = commandDigitIndex(of: event) {
            actions.activateCard(index)
            return true
        }
        // If the user rebinds preview to the bare space bar, a space while
        // a query is being typed must stay a space.
        if keyBindings.binding(for: .previewSelection).matches(event) {
            if event.keyCode == UInt16(kVK_Space), !stateStore.state.query.isEmpty {
                return false
            }
            togglePreview()
            return true
        }
        // Keypad Enter always pastes, whatever Return is bound to.
        if event.specialKey == .enter {
            actions.activate()
            return true
        }
        return false
    }

    /// The vim layer: active only in normal mode, only for bare keys —
    /// chords fall through to the user's bindings. Bindings come from the
    /// editable keymap and are matched by what the keys type, so any
    /// layout works; digits ride the same rule (AZERTY reaches them with
    /// Shift, which stays allowed).
    private func handleVimNormal(_ event: NSEvent) -> Bool {
        guard stateStore.vimEnabled, !stateStore.searchActive else { return false }
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
            return false
        }
        guard let typed = event.charactersIgnoringModifiers, !typed.isEmpty else { return false }
        if event.keyCode == UInt16(kVK_Tab) {
            actions.switchChipGroup()
            return true
        }
        let pending = vimPendingKey
        vimPendingKey = nil
        let prefix = pending.flatMap { now().timeIntervalSince($0.at) < Self.sequenceWindow ? $0.key : nil }
        // The sequence first (gd is nothing, gg jumps), then the bare key,
        // then a fresh sequence start.
        if let prefix, let action = vimBindings.action(for: prefix + typed) {
            perform(action)
            return true
        }
        if let action = vimBindings.action(for: typed) {
            perform(action)
            return true
        }
        if vimBindings.isSequencePrefix(typed) {
            vimPendingKey = (typed, now())
            return true
        }
        if typed == "/" {
            stateStore.setSearchActive(true)
            return true
        }
        if typed.count == 1, let digit = typed.first?.wholeNumberValue, (1...9).contains(digit) {
            actions.activateCard(digit - 1)
            return true
        }
        // Unmapped printable keys die silently, vim-style; control and
        // function keys continue to the user's bindings.
        guard let scalar = typed.unicodeScalars.first else { return false }
        return scalar.value >= 0x20 && scalar.value < 0xF700
    }

    private func perform(_ action: VimAction) {
        switch action {
        case .previousCard: actions.navigate(.left)
        case .nextCard: actions.navigate(.right)
        case .rowUp: actions.navigate(.up)
        case .rowDown: actions.navigate(.down)
        case .firstCard: actions.jumpToEdge(.start)
        case .lastCard: actions.jumpToEdge(.end)
        case .paste: actions.activate()
        case .pastePlain: actions.activatePlain()
        case .preview: togglePreview()
        case .stackToggle: actions.stackSelected()
        case .pinToggle: actions.togglePinSelected()
        case .deleteSelection: actions.deleteSelected()
        case .search: stateStore.setSearchActive(true)
        case .clearSearch: actions.search("")
        case .closePanel: closePanel()
        case .copy: actions.copySelected()
        case .open: openSelected()
        case .reveal: revealSelected()
        case .save: saveSelected()
        case .excludeSource: excludeSelectedSource()
        case .deleteFromSource: deleteFromSelectedSource()
        case .edit: editSelected()
        case .undo: actions.undo()
        }
    }

    private func editSelected() {
        guard let card = stateStore.state.selectedCard, card.transformable else { return }
        actions.beginEditing(card)
    }

    // The card under the cursor decides whether a key does anything: a
    // link opens, files reveal, anything but files saves.

    private func openSelected() {
        guard case .link(let url)? = stateStore.state.selectedCard?.dragPayload else { return }
        actions.openLink(url)
    }

    private func revealSelected() {
        guard case .files(let paths)? = stateStore.state.selectedCard?.dragPayload else { return }
        actions.revealFiles(paths)
    }

    private func saveSelected() {
        guard let card = stateStore.state.selectedCard, card.saveable else { return }
        actions.saveToDisk(card.dragPayload)
    }

    private func excludeSelectedSource() {
        guard let card = stateStore.state.selectedCard, let bundleID = card.sourceBundleID else { return }
        actions.excludeSource(bundleID, card.sourceLabel)
    }

    private func deleteFromSelectedSource() {
        guard let key = stateStore.state.selectedCard?.sourceKey else { return }
        actions.deleteAllFromSource(key)
    }

    /// ⌘ + the digit the user actually typed → rail position 0…8. Shift is
    /// allowed and applied, so layouts whose digits live on shift
    /// (Programmer Dvorak, AZERTY) use their real digit keys — never the
    /// physical QWERTY positions.
    private func commandDigitIndex(of event: NSEvent) -> Int? {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard modifiers == .command || modifiers == [.command, .shift] else { return nil }
        let typed =
            modifiers.contains(.shift)
            ? event.characters(byApplyingModifiers: .shift)
            : event.charactersIgnoringModifiers
        guard let character = typed?.first,
            let digit = character.wholeNumberValue,
            (1...9).contains(digit)
        else { return nil }
        return digit - 1
    }
}

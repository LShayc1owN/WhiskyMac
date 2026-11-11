// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Carbon.HIToolbox
import Combine

/// Everything the keyboard can do, each rebindable from Settings.
enum KeyAction: String, CaseIterable, Identifiable {
    case togglePanel
    case togglePinned
    case togglePrivacy
    case pasteSelection
    case pastePlain
    case stackSelection
    case pasteNextFromStack
    case previousCard
    case nextCard
    case rowUp
    case rowDown
    case switchChipGroup
    case previewSelection
    case pinSelection
    case deleteSelection
    case copySelection
    case openSelection
    case revealSelection
    case saveSelection
    case excludeSelectionSource
    case deleteSelectionSource
    case editSelection
    case undoLastChange

    var id: String { rawValue }

    var displayName: String { searchTitle.localized }

    var searchTitle: SettingsSearchText {
        switch self {
        case .togglePrivacy: settingsSearchText("Toggle manual Privacy Mode")
        case .togglePinned: settingsSearchText("Show / hide pinned items")
        case .togglePanel: settingsSearchText("Show / hide the panel")
        case .pasteSelection: settingsSearchText("Paste the selection")
        case .pastePlain: settingsSearchText("Paste as plain text")
        case .stackSelection: settingsSearchText("Toggle the selection in the paste stack")
        case .pasteNextFromStack: settingsSearchText("Paste next from the stack")
        case .previousCard: settingsSearchText("Previous card or chip")
        case .nextCard: settingsSearchText("Next card or chip")
        case .rowUp: settingsSearchText("Focus the row above")
        case .rowDown: settingsSearchText("Focus the row below")
        case .switchChipGroup: settingsSearchText("Switch filter group")
        case .previewSelection: settingsSearchText("Preview the selection")
        case .pinSelection: settingsSearchText("Pin / unpin the selection")
        case .deleteSelection: settingsSearchText("Delete the selection")
        case .copySelection: settingsSearchText("Copy the selection without pasting")
        case .openSelection: settingsSearchText("Open the selected link")
        case .revealSelection: settingsSearchText("Reveal the selected files in Finder")
        case .saveSelection: settingsSearchText("Save the selection as a file")
        case .excludeSelectionSource: settingsSearchText("Exclude the selection's application")
        case .deleteSelectionSource: settingsSearchText("Delete everything from the selection's application")
        case .editSelection: settingsSearchText("Edit the selection")
        case .undoLastChange: settingsSearchText("Undo the last deletion or edit")
        }
    }

    /// Global shortcuts work everywhere; the rest act inside the panel.
    var isGlobal: Bool {
        self == .togglePinned || self == .togglePanel || self == .pasteNextFromStack || self == .togglePrivacy
    }
}

/// One recorded shortcut: a virtual key code plus device-independent
/// modifiers.
struct KeyBinding: Equatable, Codable {
    let keyCode: UInt16
    let rawModifiers: UInt

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: rawModifiers)
    }

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        rawModifiers = modifiers.intersection([.command, .option, .control, .shift]).rawValue
    }

    init(event: NSEvent) {
        self.init(keyCode: event.keyCode, modifiers: event.modifierFlags)
    }

    func matches(_ event: NSEvent) -> Bool {
        event.keyCode == keyCode
            && event.modifierFlags.intersection([.command, .option, .control, .shift]).rawValue == rawModifiers
    }

    var carbonModifiers: UInt32 {
        var carbon: UInt32 = 0
        if modifiers.contains(.command) { carbon |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { carbon |= UInt32(shiftKey) }
        if modifiers.contains(.option) { carbon |= UInt32(optionKey) }
        if modifiers.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }

    /// AppKit draws menu key equivalents in its trailing, secondary-color column.
    var menuKeyEquivalent: String? {
        let special: [UInt16: String] = [
            UInt16(kVK_Return): "\r", UInt16(kVK_ANSI_KeypadEnter): "\u{3}",
            UInt16(kVK_Escape): "\u{1b}", UInt16(kVK_Delete): "\u{8}",
            UInt16(kVK_ForwardDelete): "\u{7f}", UInt16(kVK_Space): " ",
            UInt16(kVK_Tab): "\t", UInt16(kVK_LeftArrow): "\u{F702}",
            UInt16(kVK_RightArrow): "\u{F703}", UInt16(kVK_UpArrow): "\u{F700}",
            UInt16(kVK_DownArrow): "\u{F701}",
        ]
        if let equivalent = special[keyCode] { return equivalent }
        return KeyboardLayout.character(for: keyCode).map { String($0).lowercased() }
    }
}

/// User-configured shortcuts, persisted per action; unset actions fall back
/// to defaults. The panel-toggle default resolves the character V through
/// the live keyboard layout, so it keeps following layout switches until
/// the user records something explicit.
final class KeyBindingsStore: ObservableObject {
    @Published private(set) var overrides: [String: KeyBinding] = [:]
    @Published private(set) var enabledGlobalActions: Set<KeyAction> = []
    @Published var registrationFailures: Set<KeyAction> = []
    @Published private(set) var recordingAction: KeyAction?

    private var recordingMonitor: Any?
    private let defaults: UserDefaults
    private let logger: any Logger
    private static let storageKey = "keyBindings"
    private static let enabledGlobalKey = "enabledGlobalShortcuts"

    init(defaults: UserDefaults = AppIdentity.defaults, logger: any Logger = ConsoleLogger()) {
        self.defaults = defaults
        self.logger = logger
        enabledGlobalActions = Set(
            (defaults.stringArray(forKey: Self.enabledGlobalKey) ?? []).compactMap(KeyAction.init(rawValue:))
                .filter(\.isGlobal))
        if let data = defaults.data(forKey: Self.storageKey) {
            do {
                overrides = try JSONDecoder().decode([String: KeyBinding].self, from: data)
            } catch {
                logger.log("stored key bindings unreadable — \(error); the defaults apply")
            }
        }
    }

    func binding(for action: KeyAction) -> KeyBinding {
        overrides[action.rawValue] ?? Self.defaultBinding(for: action)
    }

    func isCustomized(_ action: KeyAction) -> Bool {
        overrides[action.rawValue] != nil
    }

    func set(_ binding: KeyBinding, for action: KeyAction) {
        overrides[action.rawValue] = binding
        persist()
        if action.isGlobal {
            setGlobalEnabled(true, for: action)
        }
    }

    func isGlobalEnabled(_ action: KeyAction) -> Bool {
        enabledGlobalActions.contains(action)
    }

    func setGlobalEnabled(_ enabled: Bool, for action: KeyAction) {
        guard action.isGlobal else { return }
        if enabled {
            enabledGlobalActions.insert(action)
        } else {
            enabledGlobalActions.remove(action)
        }
        defaults.set(enabledGlobalActions.map(\.rawValue).sorted(), forKey: Self.enabledGlobalKey)
    }

    /// One recorder at most: arming an action disarms any other, so a
    /// stray key monitor can never capture for a stale row.
    func beginRecording(_ action: KeyAction) {
        endRecording()
        recordingAction = action
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.record(event) == true ? nil : event
        }
    }

    /// The recorder's one decision: Escape cancels, any other key becomes
    /// the binding, and either way the recorder disarms. False when nothing
    /// was being recorded, so the event travels on.
    @discardableResult
    func record(_ event: NSEvent) -> Bool {
        guard let target = recordingAction else { return false }
        if event.keyCode != UInt16(kVK_Escape) {
            set(KeyBinding(event: event), for: target)
        }
        endRecording()
        return true
    }

    func endRecording() {
        if let recordingMonitor {
            NSEvent.removeMonitor(recordingMonitor)
        }
        recordingMonitor = nil
        recordingAction = nil
    }

    func reset(_ action: KeyAction) {
        overrides.removeValue(forKey: action.rawValue)
        persist()
    }

    func resetCategory(global: Bool) {
        let actions = Set(KeyAction.allCases.filter { $0.isGlobal == global })
        if let recordingAction, actions.contains(recordingAction) { endRecording() }
        overrides = overrides.filter { key, _ in
            guard let action = KeyAction(rawValue: key) else { return true }
            return !actions.contains(action)
        }
        persist()
        registrationFailures.subtract(actions)
        if global {
            enabledGlobalActions.subtract(actions)
            defaults.set(enabledGlobalActions.map(\.rawValue).sorted(), forKey: Self.enabledGlobalKey)
        }
    }

    func resetAll() {
        endRecording()
        registrationFailures = []
        overrides = [:]
        persist()
        enabledGlobalActions = []
        defaults.set([String](), forKey: Self.enabledGlobalKey)
    }

    /// Restore only the scope of an undoable reset, retaining unrelated edits.
    func restoreBindings(
        _ saved: [String: KeyBinding], for actions: Set<KeyAction>, enabledGlobals: Set<KeyAction>?
    ) {
        if let recordingAction, actions.contains(recordingAction) { endRecording() }
        var restored = overrides
        for action in actions { restored[action.rawValue] = saved[action.rawValue] }
        overrides = restored
        persist()
        registrationFailures.subtract(actions)
        if let enabledGlobals {
            enabledGlobalActions = enabledGlobals.filter(\.isGlobal)
            defaults.set(enabledGlobalActions.map(\.rawValue).sorted(), forKey: Self.enabledGlobalKey)
        }
    }

    /// Actions whose effective bindings collide with another action's.
    var duplicatedActions: [KeyAction] {
        let all = KeyAction.allCases.map { ($0, binding(for: $0)) }
        return all.filter { action, binding in
            all.contains { other, otherBinding in other != action && otherBinding == binding }
        }.map(\.0)
    }

    func label(for action: KeyAction) -> String {
        let binding = binding(for: action)
        var parts = ""
        if binding.modifiers.contains(.control) { parts += "⌃" }
        if binding.modifiers.contains(.option) { parts += "⌥" }
        if binding.modifiers.contains(.shift) { parts += "⇧" }
        if binding.modifiers.contains(.command) { parts += "⌘" }
        return parts + Self.keyLabel(binding.keyCode)
    }

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(overrides), forKey: Self.storageKey)
        } catch {
            logger.log("key bindings not saved — \(error)")
        }
    }

    private static func defaultBinding(for action: KeyAction) -> KeyBinding {
        switch action {
        case .togglePrivacy:
            return KeyBinding(
                keyCode: KeyboardLayout.keyCode(for: "p", orANSI: kVK_ANSI_P), modifiers: [.option, .command])
        case .togglePinned:
            return KeyBinding(
                keyCode: KeyboardLayout.keyCode(for: "v", orANSI: kVK_ANSI_V), modifiers: [.control, .option, .command])
        case .togglePanel:
            return KeyBinding(
                keyCode: KeyboardLayout.keyCode(for: "v", orANSI: kVK_ANSI_V), modifiers: [.command, .shift])
        case .pasteSelection:
            return KeyBinding(keyCode: UInt16(kVK_Return), modifiers: [])
        case .pastePlain:
            return KeyBinding(keyCode: UInt16(kVK_Return), modifiers: [.option])
        case .stackSelection:
            return KeyBinding(keyCode: UInt16(kVK_Return), modifiers: [.shift])
        case .pasteNextFromStack:
            return KeyBinding(
                keyCode: KeyboardLayout.keyCode(for: "v", orANSI: kVK_ANSI_V), modifiers: [.command, .option])
        case .previousCard:
            return KeyBinding(keyCode: UInt16(kVK_LeftArrow), modifiers: [])
        case .nextCard:
            return KeyBinding(keyCode: UInt16(kVK_RightArrow), modifiers: [])
        case .rowUp:
            return KeyBinding(keyCode: UInt16(kVK_UpArrow), modifiers: [])
        case .rowDown:
            return KeyBinding(keyCode: UInt16(kVK_DownArrow), modifiers: [])
        case .switchChipGroup:
            return KeyBinding(keyCode: UInt16(kVK_Tab), modifiers: [.control])
        case .previewSelection:
            // Finder's Quick Look shortcut — the bare space bar would fight
            // with typing in the search field.
            return KeyBinding(keyCode: KeyboardLayout.keyCode(for: "y", orANSI: kVK_ANSI_Y), modifiers: [.command])
        case .pinSelection:
            return KeyBinding(keyCode: KeyboardLayout.keyCode(for: "p", orANSI: kVK_ANSI_P), modifiers: [.command])
        case .deleteSelection:
            return KeyBinding(keyCode: UInt16(kVK_Delete), modifiers: [.command])
        case .copySelection:
            return KeyBinding(keyCode: KeyboardLayout.keyCode(for: "c", orANSI: kVK_ANSI_C), modifiers: [.command])
        case .openSelection:
            return KeyBinding(keyCode: KeyboardLayout.keyCode(for: "o", orANSI: kVK_ANSI_O), modifiers: [.command])
        case .revealSelection:
            return KeyBinding(keyCode: KeyboardLayout.keyCode(for: "r", orANSI: kVK_ANSI_R), modifiers: [.command])
        case .saveSelection:
            return KeyBinding(keyCode: KeyboardLayout.keyCode(for: "s", orANSI: kVK_ANSI_S), modifiers: [.command])
        case .excludeSelectionSource:
            return KeyBinding(
                keyCode: KeyboardLayout.keyCode(for: "x", orANSI: kVK_ANSI_X), modifiers: [.control, .command])
        case .deleteSelectionSource:
            return KeyBinding(keyCode: UInt16(kVK_Delete), modifiers: [.control, .command])
        case .editSelection:
            return KeyBinding(keyCode: KeyboardLayout.keyCode(for: "e", orANSI: kVK_ANSI_E), modifiers: [.command])
        case .undoLastChange:
            return KeyBinding(keyCode: KeyboardLayout.keyCode(for: "z", orANSI: kVK_ANSI_Z), modifiers: [.command])
        }
    }

    private static let specialKeyLabels: [UInt16: String] = [
        UInt16(kVK_Return): "⏎",
        UInt16(kVK_ANSI_KeypadEnter): "⌅",
        UInt16(kVK_Escape): "⎋",
        UInt16(kVK_Delete): "⌫",
        UInt16(kVK_ForwardDelete): "⌦",
        UInt16(kVK_Space): "␣",
        UInt16(kVK_Tab): "⇥",
        UInt16(kVK_LeftArrow): "←",
        UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑",
        UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_Home): "↖",
        UInt16(kVK_End): "↘",
        UInt16(kVK_PageUp): "⇞",
        UInt16(kVK_PageDown): "⇟",
    ]

    private static func keyLabel(_ keyCode: UInt16) -> String {
        if let special = specialKeyLabels[keyCode] {
            return special
        }
        if let character = KeyboardLayout.character(for: keyCode) {
            return String(character).uppercased()
        }
        let code = Int(keyCode)
        return localized("key \(code)")
    }
}

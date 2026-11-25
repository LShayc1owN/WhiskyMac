// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

enum SettingsTextSizeShortcut {
    static func handle(_ event: NSEvent, in window: NSWindow, appearance: AppearanceSettingsStore) -> Bool {
        guard event.type == .keyDown, event.window === window, window.isKeyWindow, window.attachedSheet == nil
        else { return false }

        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let delta: Int
        switch (modifiers, event.charactersIgnoringModifiers) {
        case (.command, "="), (.command, "+"), ([.command, .shift], "+"): delta = 5
        case (.command, "-"): delta = -5
        default: return false
        }
        appearance.setInterfaceFontPercent(appearance.interfaceTypography.percent + delta)
        return true
    }
}

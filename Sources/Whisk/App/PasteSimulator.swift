// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

/// Sends ⌘V to the frontmost application. The first attempt without
/// Accessibility access shows the system prompt once; until access is
/// granted, a selection still lands on the pasteboard for a manual paste.
enum PasteSimulator {
    private static var didPromptForAccess = false

    static func paste(to target: NSRunningApplication? = nil, allowed: @escaping () -> Bool = { true }) {
        guard allowed(), trusted() else { return }
        if let target {
            guard !target.isTerminated else { return }
            target.activate()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard allowed() else { return }
            if let target, NSWorkspace.shared.frontmostApplication?.processIdentifier != target.processIdentifier {
                return
            }
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier != AppIdentity.bundleIdentifier else {
                return
            }
            postCommandV()
        }
    }

    private static func trusted() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }
        guard !didPromptForAccess else { return false }
        didPromptForAccess = true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private static func postCommandV() {
        let keyCode = CGKeyCode(KeyboardLayout.keyCode(for: "v", orANSI: kVK_ANSI_V))
        let source = CGEventSource(stateID: .combinedSessionState)
        // Right after the global pop shortcut the user is still holding
        // ⌥⌘, and those hardware modifiers would merge into the synthetic
        // event — the app would receive ⌥⌘V and paste nothing. Suppressing
        // local keyboard events for the injection interval keeps the chord
        // clean, so the paste fires the instant the shortcut is pressed
        // (the technique Flycut and Maccy ship).
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
}

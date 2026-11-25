// WhiskyMac: modified or added 2026-11-18 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI
import Testing

@testable import Whisk

@MainActor
@Suite struct OnboardingPracticeTests {
    @Test func history_instructions_follow_the_saved_shortcut_and_use_the_menu_as_a_fallback() throws {
        let sandbox = try IsolatedDefaults()
        let bindings = KeyBindingsStore(defaults: sandbox.defaults)
        let menu = localized("Show History")
        #expect(OnboardingPracticeInstructions.openHistory(using: bindings).contains(menu))
        bindings.set(KeyBinding(keyCode: 35, modifiers: [.control, .shift]), for: .togglePanel)
        let restored = KeyBindingsStore(defaults: sandbox.defaults)
        #expect(restored.enabledGlobalActions == [.togglePanel])
        #expect(
            OnboardingPracticeInstructions.openHistory(using: restored).contains(restored.label(for: .togglePanel)))
        restored.registrationFailures.insert(.togglePanel)
        #expect(OnboardingPracticeInstructions.openHistory(using: restored).contains(menu))
        restored.registrationFailures.removeAll()
        restored.set(restored.binding(for: .copySelection), for: .togglePanel)
        #expect(OnboardingPracticeInstructions.openHistory(using: restored).contains(menu))
    }

    @Test func selection_instructions_use_custom_keys_and_offer_manual_paste_without_accessibility() throws {
        let sandbox = try IsolatedDefaults()
        let bindings = KeyBindingsStore(defaults: sandbox.defaults)
        bindings.set(KeyBinding(keyCode: 8, modifiers: [.control, .shift]), for: .copySelection)
        bindings.set(KeyBinding(keyCode: 9, modifiers: [.control, .shift]), for: .pasteSelection)
        let direct = OnboardingPracticeInstructions.useSelection(using: bindings, canPasteDirectly: true)
        #expect(direct.contains(bindings.label(for: .copySelection)))
        #expect(direct.contains(bindings.label(for: .pasteSelection)))
        let manual = OnboardingPracticeInstructions.useSelection(using: bindings, canPasteDirectly: false)
        #expect(manual.contains(bindings.label(for: .copySelection)))
        #expect(manual.contains("⌘V"))
        #expect(!manual.contains(bindings.label(for: .pasteSelection)))
        #expect(bindings.enabledGlobalActions.isEmpty)
    }

    @Test func only_the_host_window_losing_focus_or_closing_stops_recording() throws {
        _ = NSApplication.shared
        let sandbox = try IsolatedDefaults()
        let bindings = KeyBindingsStore(defaults: sandbox.defaults)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: .borderless, backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = NSHostingView(
            rootView: MacOS15OnboardingWindowEvents {
                bindings.endRecording()
            })
        window.contentView?.layoutSubtreeIfNeeded()
        bindings.beginRecording(.copySelection)
        let otherWindow = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        otherWindow.isReleasedWhenClosed = false
        defer { otherWindow.close() }
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: otherWindow)
        #expect(bindings.recordingAction == .copySelection)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        #expect(bindings.recordingAction == nil)
        bindings.beginRecording(.pasteSelection)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        #expect(bindings.recordingAction == nil)
    }
}

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
    @Test func only_pasting_an_example_completes_practice() {
        let session = OnboardingPracticeSession(sample: "Hello\nA good idea")
        session.perform(.paste)
        #expect(!session.isComplete)
        session.addExample()
        for action in [CardAction.none, .copy, .preview, .menu, .edit, .split] {
            session.perform(action)
            #expect(!session.isComplete)
        }
        #expect(session.copiedText == "Hello\nA good idea")
        #expect(session.splitParts.map(\.part.text) == ["Hello", "A good idea"])
        session.perform(.paste)
        #expect(session.pastedText == "Hello\nA good idea")
        #expect(session.isComplete)
    }

    @Test func editing_and_resetting_remain_local_and_preserve_preferences() throws {
        let sandbox = try IsolatedDefaults()
        let settings = GeneralSettingsStore(defaults: sandbox.defaults)
        settings.interactions.singleClick = .copy
        let session = OnboardingPracticeSession(sample: "Hello\nOriginal")
        session.addExample()
        session.perform(.edit)
        session.draft = "   "
        session.saveEdit()
        #expect(session.presentation == .edit)
        #expect(session.text == "Hello\nOriginal")
        session.draft = "Hello\nEdited"
        session.saveEdit()
        session.perform(.split)
        #expect(session.splitParts.map(\.part.text) == ["Hello", "Edited"])
        session.perform(.paste)
        session.query = "Edited"
        session.reset()
        #expect(session.text == "Hello\nOriginal")
        #expect(!session.hasExample && !session.isSelected && !session.isComplete)
        #expect(session.query.isEmpty && session.draft.isEmpty)
        #expect(session.copiedText == nil && session.pastedText == nil)
        #expect(session.presentation == nil && session.splitParts.isEmpty)
        #expect(GeneralSettingsStore(defaults: sandbox.defaults).interactions.singleClick == .copy)
    }

    @Test func search_and_selection_prevent_hidden_example_actions() {
        let session = OnboardingPracticeSession(sample: "Hello")
        session.addExample()
        session.query = "missing"
        session.perform(.copy)
        session.perform(.paste)
        #expect(session.copiedText == nil && !session.isComplete)
        session.query = "hello"
        session.perform(.none)
        #expect(session.isSelected)
        #expect(session.presentation == nil && !session.isComplete)
    }

    @Test func preference_edits_and_shortcut_recording_persist_without_enabling_globals() throws {
        let sandbox = try IsolatedDefaults()
        let settings = GeneralSettingsStore(defaults: sandbox.defaults)
        settings.interactions.doubleClick = .copy
        settings.interactions.rightClick = .edit
        settings.interactions.hover = .preview
        settings.interactions.hoverDelay = 1.2
        let bindings = KeyBindingsStore(defaults: sandbox.defaults)
        bindings.beginRecording(.pasteSelection)
        let key = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0,
                windowNumber: 0, context: nil, characters: "b", charactersIgnoringModifiers: "b",
                isARepeat: false, keyCode: 11))
        #expect(bindings.record(key))
        let restored = GeneralSettingsStore(defaults: sandbox.defaults)
        #expect(restored.interactions == settings.interactions)
        let restoredKeys = KeyBindingsStore(defaults: sandbox.defaults)
        #expect(restoredKeys.binding(for: .pasteSelection).matches(key))
        #expect(restoredKeys.enabledGlobalActions.isEmpty)
        bindings.beginRecording(.copySelection)
        bindings.endRecording()
        #expect(bindings.recordingAction == nil)
    }
    @Test func cancelled_hover_cannot_reopen_a_preview_and_explicit_preview_survives_pointer_exit() async throws {
        let gate = PracticeHoverGate()
        let session = OnboardingPracticeSession(
            sample: "Hello",
            sleep: { delay in
                #expect(delay == 1.2)
                await gate.wait()
            })
        let interactions = InteractionBindings(hover: .preview, hoverDelay: 1.2)
        session.addExample()
        let cancelled = try #require(session.hover(inside: true, interactions: interactions))
        session.hover(inside: false, interactions: interactions)
        await gate.release()
        await cancelled.value
        #expect(session.presentation == nil)
        let allowed = try #require(session.hover(inside: true, interactions: interactions))
        await gate.release()
        await allowed.value
        #expect(session.presentation == .preview)
        #expect(!session.isComplete)
        session.cancelHover()
        #expect(session.presentation == nil)
        session.perform(.preview)
        session.hover(inside: false, interactions: interactions)
        #expect(session.presentation == .preview)
        session.cancelTransient()
        #expect(session.presentation == nil)
    }

    @Test func leaving_practice_cancels_pending_hover_and_keeps_saved_progress() async throws {
        let sandbox = try IsolatedDefaults()
        let state = OnboardingState(defaults: sandbox.defaults, readClipboardAccess: { .denied })
        state.select(.practice)
        state.practice.addExample()
        state.practice.perform(.paste)
        state.practice.perform(.edit)
        state.select(.tools)
        #expect(state.practice.presentation == nil)
        #expect(state.isPracticeComplete)
        #expect(sandbox.defaults.integer(forKey: "onboardingPage") == OnboardingPage.tools.rawValue)
        let gate = PracticeHoverGate()
        let session = OnboardingPracticeSession(sample: "Hello", sleep: { _ in await gate.wait() })
        session.addExample()
        let task = try #require(session.hover(inside: true, interactions: InteractionBindings(hover: .preview)))
        session.cancelTransient()
        await gate.release()
        await task.value
        #expect(session.presentation == nil)
    }

    @Test func practice_keys_respect_focus_recording_and_live_bindings() throws {
        let sandbox = try IsolatedDefaults()
        let bindings = KeyBindingsStore(defaults: sandbox.defaults)
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                isARepeat: false, keyCode: 36))
        #expect(
            OnboardingPracticeShortcutRouter.action(for: event, bindings: bindings, active: true, editingText: false)
                == .paste)
        #expect(
            OnboardingPracticeShortcutRouter.action(for: event, bindings: bindings, active: false, editingText: false)
                == nil)
        #expect(
            OnboardingPracticeShortcutRouter.action(for: event, bindings: bindings, active: true, editingText: true)
                == nil)
        bindings.beginRecording(.copySelection)
        #expect(
            OnboardingPracticeShortcutRouter.action(for: event, bindings: bindings, active: true, editingText: false)
                == nil)
        let original = bindings.binding(for: .copySelection)
        let escape = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: 53))
        #expect(bindings.record(escape))
        #expect(bindings.binding(for: .copySelection) == original)
        bindings.set(KeyBinding(event: event), for: .copySelection)
        bindings.set(original, for: .pasteSelection)
        #expect(
            OnboardingPracticeShortcutRouter.action(for: event, bindings: bindings, active: true, editingText: false)
                == .copy)
    }

    @Test func only_the_host_window_losing_focus_or_closing_stops_recording() throws {
        _ = NSApplication.shared
        let sandbox = try IsolatedDefaults()
        let bindings = KeyBindingsStore(defaults: sandbox.defaults)
        let session = OnboardingPracticeSession(sample: "Hello")
        session.addExample()
        session.perform(.edit)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: .borderless, backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = NSHostingView(
            rootView: OnboardingWindowEvents {
                bindings.endRecording()
                session.cancelTransient()
            })
        window.contentView?.layoutSubtreeIfNeeded()
        bindings.beginRecording(.copySelection)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: NSObject())
        #expect(bindings.recordingAction == .copySelection)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        #expect(bindings.recordingAction == nil && session.presentation == nil)
        bindings.beginRecording(.pasteSelection)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        #expect(bindings.recordingAction == nil)
    }

}

private actor PracticeHoverGate {
    private var permits = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if permits > 0 { permits -= 1; return }
        await withCheckedContinuation { waiting.append($0) }
    }
    func release() {
        if !waiting.isEmpty { waiting.removeFirst().resume() } else { permits += 1 }
    }
}

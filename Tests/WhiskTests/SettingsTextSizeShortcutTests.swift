// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Testing

@testable import Whisk

@MainActor
@Suite(.serialized) struct SettingsTextSizeShortcutTests {
    @Test func shortcuts_change_and_persist_the_size_only_in_the_key_settings_window() throws {
        _ = NSApplication.shared
        let sandbox = try IsolatedDefaults()
        let appearance = AppearanceSettingsStore(defaults: sandbox.defaults)
        appearance.setPlainTextFollowsInterface(false)
        let settings = makeWindow()
        let other = makeWindow()
        defer { settings.close(); other.close() }

        let equals = try key("=", in: settings)
        #expect(!SettingsTextSizeShortcut.handle(equals, in: settings, appearance: appearance))
        settings.hasFocus = true
        #expect(!SettingsTextSizeShortcut.handle(try key("=", in: other), in: settings, appearance: appearance))
        #expect(appearance.interfaceTypography.percent == 100)
        #expect(
            !SettingsTextSizeShortcut.handle(
                try key("=", [.command, .option], in: settings), in: settings,
                appearance: appearance))
        #expect(SettingsTextSizeShortcut.handle(equals, in: settings, appearance: appearance))
        #expect(appearance.interfaceTypography.percent == 105)
        let plus = try key("+", [.command, .shift], in: settings)
        #expect(SettingsTextSizeShortcut.handle(plus, in: settings, appearance: appearance))
        #expect(appearance.interfaceTypography.percent == 110)
        let minus = try key("-", in: settings)
        #expect(SettingsTextSizeShortcut.handle(minus, in: settings, appearance: appearance))
        #expect(appearance.interfaceTypography.percent == 105)

        appearance.setInterfaceFontPercent(298)
        #expect(SettingsTextSizeShortcut.handle(equals, in: settings, appearance: appearance))
        #expect(appearance.interfaceTypography.percent == 300)
        appearance.setInterfaceFontPercent(87)
        #expect(SettingsTextSizeShortcut.handle(minus, in: settings, appearance: appearance))
        #expect(appearance.interfaceTypography.percent == 85)
        #expect(
            AppearanceSettingsStore(defaults: sandbox.defaults).interfaceTypography == appearance.interfaceTypography)
        #expect(!appearance.interfaceTypography.appliesToPlainText)
    }

    private func key(_ character: String, _ modifiers: NSEvent.ModifierFlags = .command, in window: NSWindow)
        throws -> NSEvent
    {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: character,
                charactersIgnoringModifiers: character, isARepeat: false, keyCode: 0))
    }

    private func makeWindow() -> TestWindow {
        let window = TestWindow(
            contentRect: CGRect(x: -10000, y: 0, width: 100, height: 100),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        return window
    }

    private final class TestWindow: NSWindow {
        var hasFocus = false
        override var isKeyWindow: Bool { hasFocus }
    }
}

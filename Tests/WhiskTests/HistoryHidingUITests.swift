// WhiskyMac: modified or added 2026-11-19 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Carbon.HIToolbox
import SwiftUI
import Testing

@testable import Whisk

@MainActor
@Suite(.serialized) struct HistoryHidingUITests {
    @Test func options_own_the_keyboard_in_normal_and_privacy_modes() throws {
        let sandbox = try IsolatedDefaults()
        let state = HistoryViewStateStore()
        let spy = PanelActionSpy()
        let router = PanelKeyRouter(
            stateStore: state, actions: spy.actions, keyBindings: KeyBindingsStore(defaults: sandbox.defaults),
            vimBindings: VimBindingsStore(defaults: sandbox.defaults), togglePreview: {}, closePanel: {})
        for protected in [false, true] {
            state.setPrivacy(protected)
            state.historyHidingOptions = .typeOrSource
            #expect(!router.handle(try #require(aKeyEvent(kVK_Return))))
            #expect(!router.handle(try #require(aKeyEvent(kVK_ANSI_C, [.command], typing: "c"))))
            #expect(!router.handle(try #require(aKeyEvent(kVK_Tab))))
            #expect(spy.calls.isEmpty)
            state.panelDidClose()
            #expect(!state.historyHidingOptionsOpen)
        }
    }

    @Test func hover_explanation_is_mouse_transparent_and_never_takes_keyboard_focus() async throws {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: 0, width: 120, height: 36),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let message = "A bounded explanation that wraps to multiple lines and leaves the search field focused."
        let host = NSHostingView(rootView: HistoryHoverHelpAnchor(title: "Hide", message: message, presented: false))
        window.contentView = host
        window.orderFront(nil)
        defer { window.contentView = nil; window.close() }
        let keyWindow = NSApp.keyWindow
        host.rootView = HistoryHoverHelpAnchor(title: "Hide", message: message, presented: true)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(250))
        let help = try #require(window.childWindows?.first)
        #expect(help.isVisible && help.ignoresMouseEvents)
        #expect(!help.canBecomeKey && !help.canBecomeMain)
        #expect(help.frame.width <= 310 && help.frame.height > 60)
        #expect(NSApp.keyWindow === keyWindow)
        host.rootView = HistoryHoverHelpAnchor(title: "Hide", message: message, presented: false)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        #expect(window.childWindows?.isEmpty != false)
        #expect(!help.isVisible)
    }

    @Test func type_list_time_picker_and_hover_text_fit_in_all_supported_languages() async throws {
        _ = NSApplication.shared
        let previous = AppLocalization.language
        defer { AppLocalization.language = previous }
        let date = Date(timeIntervalSince1970: 1_795_037_400)
        for language in ["zh-Hans", "zh-Hant", "en", "fr", "de", "it"] {
            AppLocalization.language = language
            for types in [false, true] {
                let content = HistoryHidingOptions(
                    includesTypes: types, confirm: { _ in Issue.record("Rendering must not apply a rule") }, cancel: {},
                    draft: HistoryHidingDraft(usesNow: false, date: date, categories: [.text, .image]))
                let host = NSHostingView(rootView: content.environment(\.colorScheme, .dark))
                let size = host.fittingSize
                #expect(size.width == 360 && size.height < 560, "\(language), types=\(types), size=\(size)")
                let window = NSWindow(
                    contentRect: NSRect(origin: NSPoint(x: -10000, y: 0), size: size),
                    styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: .darkAqua)
                window.backgroundColor = .windowBackgroundColor
                window.contentView = host
                window.orderFront(nil)
                defer { window.contentView = nil; window.close() }
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(150))
                host.layoutSubtreeIfNeeded()
                if let output = ProcessInfo.processInfo.environment["WHISK_UI_ARTIFACTS"] {
                    let directory = URL(fileURLWithPath: output)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])?.write(
                        to: directory.appendingPathComponent("hide-options-\(language)-\(types ? "types" : "time").png")
                    )
                }
            }
        }
    }
}

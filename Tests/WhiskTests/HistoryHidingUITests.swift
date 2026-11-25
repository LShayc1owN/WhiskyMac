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
        let host = NSHostingView(
            rootView: MacOS15HistoryHoverHelpAnchor(title: "Hide", message: message, presented: false))
        window.contentView = host
        window.orderFront(nil)
        defer { window.contentView = nil; window.close() }
        let keyWindow = NSApp.keyWindow
        host.rootView = MacOS15HistoryHoverHelpAnchor(title: "Hide", message: message, presented: true)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(250))
        let help = try #require(window.childWindows?.first)
        #expect(help.isVisible && help.ignoresMouseEvents)
        #expect(!help.canBecomeKey && !help.canBecomeMain)
        #expect(help.frame.width <= 310 && help.frame.height > 60)
        #expect(NSApp.keyWindow === keyWindow)
        host.rootView = MacOS15HistoryHoverHelpAnchor(title: "Hide", message: message, presented: false)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        #expect(window.childWindows?.isEmpty != false)
        #expect(!help.isVisible)
    }

    @Test func macos15_type_list_time_picker_and_hover_text_fit_in_all_supported_languages() async throws {
        try await checkHidingOptions(useNativeOptions: false)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26))
    func macos26_type_list_time_picker_and_hover_text_fit_in_all_supported_languages() async throws {
        try await checkHidingOptions(useNativeOptions: true)
    }

    @Test(arguments: [false, true])
    func enlarged_date_and_time_controls_fit_the_visible_popover(includesTypes: Bool) async throws {
        _ = NSApplication.shared
        let savedLanguage = AppLocalization.language
        defer { AppLocalization.language = savedLanguage }
        let environment = ProcessInfo.processInfo.environment
        let sizes =
            environment["WHISK_EXHAUSTIVE_TYPOGRAPHY"] == "1"
            ? Array(InterfaceTypography.percentRange) : [85, 100, 150, 151, 200, 250, 300]
        let directory = environment["WHISK_TIME_TYPOGRAPHY_ARTIFACTS"].map { URL(fileURLWithPath: $0) }
        if let directory { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }

        func dateFields(in view: NSView) -> [NSDatePicker] {
            if let field = view as? NSDatePicker { return [field] }
            return view.subviews.flatMap(dateFields(in:))
        }
        for language in AppLanguage.allCases {
            AppLocalization.language = language.code
            let date = try #require(
                Calendar.current.date(from: DateComponents(year: 2024, month: 11, day: 23, hour: 15, minute: 6)))
            let draft = HistoryHidingDraft(usesNow: false, date: date)
            let root: AnyView
            if #available(macOS 26, *) {
                root = AnyView(
                    MacOS26HistoryHidingOptions(
                        includesTypes: includesTypes, confirm: { _ in }, cancel: {}, draft: draft))
            } else {
                root = AnyView(
                    MacOS15HistoryHidingOptions(
                        includesTypes: includesTypes, confirm: { _ in }, cancel: {}, draft: draft))
            }
            let host = NSHostingView(rootView: root.interfaceType(.standard))
            window.contentView = host
            for percent in sizes {
                let size = InterfaceTypography(percent: percent)
                host.rootView = root.interfaceType(size)
                window.setContentSize(host.fittingSize)
                await Task.yield()
                host.layoutSubtreeIfNeeded()
                let scope = includesTypes ? "types" : "time"
                let comment = Comment(rawValue: "\(language)-\(percent)-\(scope)")
                let fields = dateFields(in: host)
                #expect(!fields.isEmpty, comment)
                for field in fields {
                    let font = try #require(field.font, comment)
                    let drawnPointSize = host.convert(NSSize(width: 0, height: font.pointSize), from: field).height
                    #expect(drawnPointSize >= size.points(12) - 1, comment)
                    if !size.isStandard {
                        #expect(abs(drawnPointSize - size.points(NSFont.systemFontSize)) < 0.1, comment)
                        #expect(field.dateValue == date, comment)
                        let required = try #require(field.cell?.cellSize, comment)
                        #expect(field.bounds.width + 1 >= required.width, comment)
                        #expect(field.bounds.height + 1 >= required.height, comment)
                    }
                    field.scrollToVisible(field.bounds)
                    let frame = host.convert(field.bounds, from: field)
                    #expect(frame.minY >= -1 && frame.maxY <= host.bounds.maxY + 1, comment)
                    #expect(frame.minX >= -1 && frame.maxX <= host.bounds.maxX + 1, comment)
                    #expect(field.bounds.height >= font.ascender - font.descender, comment)
                }
                if let directory, [85, 300].contains(percent) {
                    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    let data = try #require(bitmap.representation(using: .png, properties: [:]))
                    try data.write(to: directory.appendingPathComponent("\(language.rawValue)-\(percent)-\(scope).png"))
                }
            }
        }
    }

    @Test func scaled_date_picker_commits_a_local_edit_and_limits_future_dates() throws {
        _ = NSApplication.shared
        let initial = Date(timeIntervalSince1970: 1_730_000_000)
        var selection = initial
        let binding = Binding(get: { selection }, set: { selection = $0 })
        let control = HistoryHidingDateControl(date: binding)
        let picker = control.picker
        control.update(
            date: binding, locale: AppLocalization.interfaceLocale, typography: InterfaceTypography(percent: 300))
        #expect(picker.locale == AppLocalization.interfaceLocale)
        #expect(picker.dateValue == initial)
        #expect(picker.acceptsFirstResponder)
        let action = try #require(picker.action)
        let changed = initial.addingTimeInterval(3600)
        picker.dateValue = changed
        #expect(picker.sendAction(action, to: picker.target))
        #expect(selection == changed)
        picker.dateValue = .distantFuture
        #expect(picker.sendAction(action, to: picker.target))
        #expect(selection <= Date() && selection == picker.dateValue)
    }

    private func checkHidingOptions(useNativeOptions: Bool) async throws {
        _ = NSApplication.shared
        let previous = AppLocalization.language
        defer { AppLocalization.language = previous }
        let date = Date(timeIntervalSince1970: 1_795_037_400)
        for language in ["zh-Hans", "zh-Hant", "en", "fr", "de", "it", "ja"] {
            AppLocalization.language = language
            for types in [false, true] {
                let draft = HistoryHidingDraft(usesNow: false, date: date, categories: [.text, .image])
                let confirm: (HistoryHidingRule) -> Void = { _ in Issue.record("Rendering must not apply a rule") }
                let content = Group {
                    if #available(macOS 26, *), useNativeOptions {
                        MacOS26HistoryHidingOptions(includesTypes: types, confirm: confirm, cancel: {}, draft: draft)
                    } else {
                        MacOS15HistoryHidingOptions(includesTypes: types, confirm: confirm, cancel: {}, draft: draft)
                    }
                }
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
                    let prefix = useNativeOptions ? "hide-options-macos26" : "hide-options"
                    let file = directory.appendingPathComponent("\(prefix)-\(language)-\(types ? "types" : "time").png")
                    try bitmap.representation(using: .png, properties: [:])?.write(to: file)
                }
            }
        }
    }
}

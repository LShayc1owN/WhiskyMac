// WhiskyMac: modified or added 2026-11-21 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI
import Testing

@testable import Whisk

@MainActor
@Suite(.serialized) struct AppearanceModeTests {
    @Test func titled_settings_and_clipboard_windows_switch_independently_and_release_system_overrides() async throws {
        _ = NSApplication.shared
        let previousLanguage = AppLocalization.language
        AppLocalization.language = "zh-Hans"
        defer { AppLocalization.language = previousLanguage }
        let globalAppearance = NSApp.appearance
        let sandbox = try IsolatedDefaults()
        let appearance = AppearanceSettingsStore(defaults: sandbox.defaults)
        appearance.settingsAppearance = .light
        appearance.clipboardAppearance = .dark
        let state = HistoryViewStateStore()
        let item = anItem(.text("浅色模式阅读示例\n检查正文、来源和底部信息。"), from: "备忘录", bundle: "com.apple.Notes")
        let items = [
            item,
            anItem(.link(try #require(URL(string: "https://example.com"))), from: "Safari", bundle: "com.apple.Safari"),
            anItem(.text("#79D9B5"), from: "文本编辑", bundle: "com.apple.TextEdit", pinned: true),
        ]
        state.detailSource = { id in items.first { $0.id == id } }
        let chips = ChipEntry.row(
            hasPinned: true, sources: items.compactMap(\.source), categories: [.text, .link, .color])
        state.update(
            HistoryPresenter().present(
                items: items, query: "", now: Date(), selectedID: item.id, filters: FilterContext(chips: chips)))
        let controller = PanelController(
            uiFactory: MacOS15UIFactory(), stateStore: state, actions: PanelActionSpy().actions,
            keyBindings: KeyBindingsStore(defaults: sandbox.defaults),
            vimBindings: VimBindingsStore(defaults: sandbox.defaults),
            appearanceMode: appearance.clipboardAppearance, vimMode: { false })
        let search = SettingsSearchModel()
        let hosting = NSHostingController(
            rootView: MacOS15SettingsView(
                store: KeyBindingsStore(defaults: sandbox.defaults),
                general: GeneralSettingsStore(defaults: sandbox.defaults), loginItem: LoginItemManager(),
                vimBindings: VimBindingsStore(defaults: sandbox.defaults), appearance: appearance, search: search
            ).environment(\.settingsAccessibilityOverride, SettingsAccessibilityValues(reduceMotion: true)))
        let window = NSWindow(contentViewController: hosting)
        window.isReleasedWhenClosed = false
        MacOS15SettingsWindowConfiguration.apply(to: window)
        window.appearance = appearance.settingsAppearance.nsAppearance
        let toolbar = MacOS15SettingsSearchToolbar(window: window, search: search, appearance: appearance)
        window.setContentSize(NSSize(width: 840, height: 720))
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderFront(nil)
        // Match the composition root's window-scoped application of stored preferences.
        appearance.changed = { [weak window, weak controller] in
            window?.appearance = appearance.settingsAppearance.nsAppearance
            controller?.appearanceMode = appearance.clipboardAppearance
        }
        defer {
            appearance.changed = nil
            controller.hide()
            window.close()
            withExtendedLifetime(toolbar) {}
        }

        let screen = try #require(NSScreen.main)
        controller.preparePresentation(pins: false, style: nil, on: screen)
        let history = controller.activeWindow
        history.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        history.orderFront(nil)
        state.setPanelVisible(true)
        for navigation in SettingsNavigation.allCases {
            appearance.navigation = navigation
            search.navigate(to: SettingsDestination(section: .colors, anchor: "settingsAppearance"))
            await settle(hosting.view)
            await settle(try #require(history.contentView))
            #expect(match(toolbar.fieldHost.effectiveAppearance) == .aqua)
            let surfaces = descendants(try #require(history.contentView)).compactMap { $0 as? MacOS15BackdropView }
            #expect(!surfaces.isEmpty)
            #expect(surfaces.allSatisfy { match($0.effectiveAppearance) == .darkAqua })
            try capture(window, name: "appearance-\(navigation)-settings-light")
        }
        appearance.settingsAppearance = .dark
        await settle(hosting.view)
        #expect(match(toolbar.fieldHost.effectiveAppearance) == .darkAqua)
        #expect(match(history.effectiveAppearance) == .darkAqua)
        appearance.clipboardAppearance = .light
        await settle(try #require(history.contentView))
        #expect(match(history.effectiveAppearance) == .aqua)
        #expect(match(toolbar.fieldHost.effectiveAppearance) == .darkAqua)
        let surfaces = descendants(try #require(history.contentView)).compactMap { $0 as? MacOS15BackdropView }
        #expect(!surfaces.isEmpty)
        #expect(surfaces.allSatisfy { match($0.effectiveAppearance) == .aqua })
        try capture(window, name: "appearance-settings-dark")
        try capture(history, name: "appearance-clipboard-light")

        let visibleBeforePreview = Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init))
        state.toggleExplicitPreview()
        let opened = NSApp.windows.filter {
            $0 is NSPanel && $0.isVisible && !visibleBeforePreview.contains(ObjectIdentifier($0))
                && $0.contentView is TestHostingSurface
        }
        #expect(opened.count == 1)
        let preview = try #require(opened.first)
        #expect(match(preview.effectiveAppearance) == .aqua)
        await settle(try #require(preview.contentView))
        try capture(preview, name: "appearance-clipboard-preview-light")
        appearance.clipboardAppearance = .dark
        #expect(match(preview.effectiveAppearance) == .darkAqua)
        #expect(match(window.effectiveAppearance) == .darkAqua)
        appearance.clipboardAppearance = .light
        state.toggleExplicitPreview()

        controller.preparePresentation(pins: true, style: .mouseList, on: screen)
        #expect(controller.activeWindow !== history)
        #expect(match(controller.activeWindow.effectiveAppearance) == .aqua)
        appearance.clipboardAppearance = .system
        #expect(controller.activeWindow.appearance == nil && history.appearance == nil)
        #expect(match(controller.activeWindow.effectiveAppearance) == match(NSApp.effectiveAppearance))
        #expect(match(window.effectiveAppearance) == .darkAqua)
        appearance.settingsAppearance = .system
        await settle(hosting.view)
        #expect(window.appearance == nil)
        #expect(match(toolbar.fieldHost.effectiveAppearance) == match(NSApp.effectiveAppearance))
        #expect(NSApp.appearance == globalAppearance)
    }

    @Test func pale_accents_remain_readable_on_light_backgrounds() throws {
        let colors = [
            NSColor(srgbRed: 1, green: 0.86, blue: 0.35, alpha: 1),
            NSColor(srgbRed: 0.71, green: 0.96, blue: 0.84, alpha: 1),
            NSColor(srgbRed: 0.85, green: 0.86, blue: 0.92, alpha: 1),
        ]
        // A light gray reference also leaves room for the tint on selected surfaces.
        let background = NSColor(srgbRed: 0.86, green: 0.86, blue: 0.86, alpha: 1)
        for color in colors {
            let ink = try #require(color.macOS15ReadableAccent(in: .light).usingColorSpace(.sRGB))
            #expect((luminance(background) + 0.05) / (luminance(ink) + 0.05) >= 4.5)
            #expect(abs(ink.hueComponent - color.hueComponent) < 0.06)
            #expect(color.macOS15ReadableAccent(in: .dark) == color)
        }
    }

    private func luminance(_ color: NSColor) -> CGFloat {
        zip([color.redComponent, color.greenComponent, color.blueComponent], [0.2126, 0.7152, 0.0722])
            .reduce(0) { result, channel in
                let (value, weight) = channel
                let linear = value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
                return result + linear * weight
            }
    }

    @Test func native_material_preview_can_differ_from_its_settings_window() async throws {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: MacOS15CardSizePreview(side: 220).environment(\.colorScheme, .dark))
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 240, height: 240),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = AppearanceMode.light.nsAppearance
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        await settle(host)
        let material = try #require(descendants(host).compactMap { $0 as? MacOS15BackdropView }.first)
        #expect(match(window.effectiveAppearance) == .aqua)
        #expect(match(material.effectiveAppearance) == .darkAqua)
        host.rootView = MacOS15CardSizePreview(side: 220).environment(\.colorScheme, .light)
        await settle(host)
        #expect(match(material.effectiveAppearance) == .aqua)
    }

    private func match(_ appearance: NSAppearance) -> NSAppearance.Name? {
        appearance.bestMatch(from: [.aqua, .darkAqua])
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    private func settle(_ view: NSView) async {
        view.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(350))
        view.layoutSubtreeIfNeeded()
    }

    private func capture(_ window: NSWindow, name: String) throws {
        guard let output = ProcessInfo.processInfo.environment["WHISK_UI_ARTIFACTS"] else { return }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let view = try #require(window.contentView?.superview)
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: view.bounds, to: bitmap)
        }
        try bitmap.representation(using: .png, properties: [:])?.write(
            to: directory.appendingPathComponent("\(name).png"))
    }
}

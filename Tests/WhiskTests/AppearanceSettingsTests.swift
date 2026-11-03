// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI
import Testing

@testable import Whisk

@MainActor
@Suite struct AppearancePreferences {
    @Test func preferences_persist_without_changing_another_domain_or_global_theme() throws {
        let sandbox = try IsolatedDefaults()
        let other = try IsolatedDefaults()
        let appearance = AppearanceSettingsStore(defaults: sandbox.defaults)
        #expect(appearance.language == .system)
        #expect(appearance.navigation == .top)
        #expect(appearance.statusClick == .history)
        #expect(appearance.dockIcon == .followWindows)
        #expect(appearance.accentMode == .system)
        let theme = AppAccent.color
        let language = AppLocalization.language
        var changes = 0
        appearance.changed = { changes += 1 }
        appearance.language = .simplifiedChinese
        appearance.navigation = .sidebar
        appearance.statusClick = .menu
        appearance.dockIcon = .always
        appearance.accentMode = .custom
        appearance.customAccent = AccentRGB(red: 0.1, green: 0.2, blue: 0.3)
        #expect(changes == 6)
        let restored = AppearanceSettingsStore(defaults: sandbox.defaults)
        #expect(restored.language == .simplifiedChinese)
        #expect(restored.navigation == .sidebar)
        #expect(restored.statusClick == .menu)
        #expect(restored.dockIcon == .always)
        #expect(restored.accentMode == .custom)
        #expect(restored.customAccent == appearance.customAccent)
        #expect(restored.nsAccent == appearance.customAccent.nsColor)
        #expect(restored.accent == Color(nsColor: restored.nsAccent))
        #expect(AppearanceSettingsStore(defaults: other.defaults).language == .system)
        #expect(AppAccent.color == theme)
        #expect(AppLocalization.language == language)
    }

    @Test func corrupt_preferences_fall_back_and_rgb_values_are_opaque_srgb() throws {
        let sandbox = try IsolatedDefaults()
        for key in ["appLanguage", "settingsNavigation", "statusClick", "dockIcon", "accentMode"] {
            sandbox.defaults.set("invalid", forKey: key)
        }
        sandbox.defaults.set(Data([0]), forKey: "customAccent")
        let settings = AppearanceSettingsStore(defaults: sandbox.defaults)
        #expect(settings.language == .system)
        #expect(settings.navigation == .top)
        #expect(settings.statusClick == .history)
        #expect(settings.dockIcon == .followWindows)
        #expect(settings.accentMode == .system)
        #expect(settings.customAccent == .initial)
        #expect(settings.nsAccent == .controlAccentColor)
        let clipped = AccentRGB(red: -1, green: 5, blue: .nan)
        #expect(clipped == AccentRGB(red: 0, green: 1, blue: 0))
        #expect(clipped.nsColor.alphaComponent == 1)
        let color = AccentRGB(NSColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 0.3))
        let reloaded = try JSONDecoder().decode(AccentRGB.self, from: JSONEncoder().encode(color))
        #expect(reloaded == color)
        #expect(reloaded.nsColor.alphaComponent == 1)
    }

    @Test func menu_mapping_keeps_right_click_reachable() {
        #expect(!StatusClickAction.history.opensMenu(rightClick: false))
        #expect(StatusClickAction.history.opensMenu(rightClick: true))
        #expect(StatusClickAction.menu.opensMenu(rightClick: false))
        #expect(StatusClickAction.menu.opensMenu(rightClick: true))
    }

    @Test func dock_policy_counts_only_ordinary_windows() {
        for count in [0, 1, 2] {
            #expect(DockIconMode.always.isVisible(ordinaryWindowCount: count))
            #expect(!DockIconMode.never.isVisible(ordinaryWindowCount: count))
            #expect(DockIconMode.followWindows.isVisible(ordinaryWindowCount: count) == (count > 0))
        }
    }

    @Test func language_override_selects_resources_and_plural_rules_without_mutating_system_preferences() throws {
        for (language, copy, count) in [
            ("en", "Copy", "1 item"), ("fr", "Copier", "1 élément"),
            ("de", "Kopieren", "1 Eintrag"),
            ("zh-Hans", "拷贝", "1 项"),
        ] {
            let selected = AppLocalization.selectedBundle(in: .module, language: language)
            #expect(selected.bundleURL.pathExtension == "lproj")
            #expect(localized("Copy", bundle: selected) == copy)
            #expect(localized("\(1) items", bundle: selected) == count)
            #expect(AppLocalization.selectedBundle(in: selected, language: "en") == selected)
        }
        #expect(AppLocalization.selectedBundle(in: .module, language: nil) == .module)
        #expect(AppLocalization.selectedBundle(in: .module, language: "unsupported") == .module)
        #expect(AppLanguage.system.code == nil)
        #expect(AppLanguage.french.code == "fr")
        #expect(AppLanguage.german.code == "de")
    }

    @Test func settings_pages_render_both_layouts_with_custom_color_privacy_and_shortcuts() throws {
        _ = NSApplication.shared
        let previousLanguage = AppLocalization.language
        if let language = ProcessInfo.processInfo.environment["WHISK_UI_LANGUAGE"] {
            AppLocalization.language = language
        }
        defer { AppLocalization.language = previousLanguage }
        let sandbox = try IsolatedDefaults()
        let appearance = AppearanceSettingsStore(defaults: sandbox.defaults)
        let bindings = KeyBindingsStore(defaults: sandbox.defaults)
        let general = GeneralSettingsStore(defaults: sandbox.defaults)
        let privacy = PrivacyController(defaults: sandbox.defaults)
        let vim = VimBindingsStore(defaults: sandbox.defaults)
        general.vimNavigation = true
        bindings.setGlobalEnabled(true, for: .togglePanel)
        bindings.registrationFailures = [.togglePanel]
        general.sensitiveApps = [ExcludedApp(bundleID: "synthetic.sensitive", name: "Synthetic")]
        general.excludedApps = [ExcludedApp(bundleID: "synthetic.excluded", name: "Synthetic")]
        appearance.accentMode = .custom
        for scheme in [ColorScheme.light, .dark] {
            for navigation in SettingsNavigation.allCases {
                appearance.navigation = navigation
                for page in SettingsPage.allCases {
                    let view = SettingsView(
                        store: bindings, general: general, loginItem: LoginItemManager(),
                        vimBindings: vim, privacy: privacy, appearance: appearance, selectedPage: page
                    )
                    .environment(\.colorScheme, scheme)
                    let host = NSHostingView(rootView: view)
                    let window = NSWindow(
                        contentRect: NSRect(x: 0, y: 0, width: 840, height: 720),
                        styleMask: .borderless, backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                    window.contentView = host
                    host.frame = window.contentLayoutRect
                    host.layoutSubtreeIfNeeded()
                    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    #expect(bitmap.pixelsWide >= 840)
                    if let output = ProcessInfo.processInfo.environment["WHISK_UI_ARTIFACTS"] {
                        let directory = URL(fileURLWithPath: output)
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        try bitmap.representation(using: .png, properties: [:])?.write(
                            to: directory.appendingPathComponent(
                                "settings-\(navigation.rawValue)-\(page.rawValue)-\(scheme == .dark ? "dark" : "light").png"
                            ))
                    }
                    window.close()
                }
            }
        }
        // Exercise system accent and masked settings as distinct states.
        appearance.accentMode = .system
        privacy.setProtected(true)
        let image = ImageRenderer(
            content: SettingsView(
                store: bindings, general: general, loginItem: LoginItemManager(),
                vimBindings: vim, privacy: privacy, appearance: appearance, selectedPage: .privacy))
        #expect(image.nsImage != nil)
    }

    @Test func titled_settings_window_keeps_shortcuts_wide_in_both_navigation_layouts() throws {
        _ = NSApplication.shared
        let sandbox = try IsolatedDefaults()
        let appearance = AppearanceSettingsStore(defaults: sandbox.defaults)
        let previousLanguage = AppLocalization.language
        AppLocalization.language = "zh-Hans"
        defer { AppLocalization.language = previousLanguage }

        func scrollView(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
        }

        for navigation in SettingsNavigation.allCases {
            appearance.navigation = navigation
            for height in [SettingsWindowSize.minimumHeight, SettingsWindowSize.height] {
                let hosting = NSHostingController(
                    rootView: SettingsView(
                        store: KeyBindingsStore(defaults: sandbox.defaults),
                        general: GeneralSettingsStore(defaults: sandbox.defaults), loginItem: LoginItemManager(),
                        vimBindings: VimBindingsStore(defaults: sandbox.defaults),
                        privacy: PrivacyController(defaults: sandbox.defaults), appearance: appearance,
                        selectedPage: .shortcuts))
                // Match AppDelegate's real window construction, including full-size content and its title bar.
                let window = NSWindow(contentViewController: hosting)
                window.isReleasedWhenClosed = false
                defer { window.close() }
                window.setContentSize(hosting.view.fittingSize)
                window.styleMask.remove([.resizable, .miniaturizable])
                SettingsWindowConfiguration.apply(to: window)
                window.setContentSize(NSSize(width: SettingsWindowSize.width, height: height))
                hosting.view.layoutSubtreeIfNeeded()
                let scroll = try #require(scrollView(in: hosting.view))
                let frame = scroll.convert(scroll.bounds, to: hosting.view)
                let sidebarWidth: CGFloat = navigation == .sidebar ? 185 : 0
                // A horizontal divider in the sidebar HStack used to steal half the content width.
                #expect(abs(frame.minX - sidebarWidth) <= 2, "\(navigation), height \(height): \(frame)")
                #expect(frame.width >= SettingsWindowSize.width - sidebarWidth - 2)
                #expect(frame.maxX <= hosting.view.bounds.maxX + 1)
                #expect(frame.height > 100)
            }
        }
    }

    @Test func settings_glass_supports_accessibility_appearance_and_expanded_controls() throws {
        _ = NSApplication.shared
        let sandbox = try IsolatedDefaults()
        let appearance = AppearanceSettingsStore(defaults: sandbox.defaults)
        let bindings = KeyBindingsStore(defaults: sandbox.defaults)
        let general = GeneralSettingsStore(defaults: sandbox.defaults)
        let vim = VimBindingsStore(defaults: sandbox.defaults)
        appearance.accentMode = .custom
        general.vimNavigation = true
        let privacy = PrivacyController(defaults: sandbox.defaults)
        privacy.setAutomaticEnabled(true)

        for scheme in [ColorScheme.light, .dark] {
            for navigation in SettingsNavigation.allCases {
                appearance.navigation = navigation
                let view = SettingsView(
                    store: bindings, general: general, loginItem: LoginItemManager(),
                    vimBindings: vim, privacy: privacy, appearance: appearance, selectedPage: .shortcuts
                )
                .environment(\.colorScheme, scheme)
                .environment(
                    \.settingsAccessibilityOverride,
                    SettingsAccessibilityValues(
                        reduceMotion: true, reduceTransparency: true, increasedContrast: true))
                let host = NSHostingView(rootView: view)
                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 840, height: 720),
                    styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                host.frame = window.contentLayoutRect
                host.layoutSubtreeIfNeeded()
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                #expect(bitmap.pixelsWide >= 840)
                window.close()
            }
        }
    }
}

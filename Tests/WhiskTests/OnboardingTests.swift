// WhiskyMac: modified or added 2026-11-18 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI
import Testing

@testable import Whisk

@MainActor
@Suite(.serialized) struct OnboardingTests {
    @Test func debug_replay_restarts_the_guide_without_resetting_completion() throws {
        for completed in [false, true] {
            let sandbox = try IsolatedDefaults()
            sandbox.defaults.set(completed, forKey: "didShowOnboarding")
            let state = OnboardingState(
                defaults: sandbox.defaults, readClipboardAccess: { .denied }, readAccessibility: { false })
            state.select(.ready)
            state.restart()
            #expect(state.page == .welcome)
            #expect(sandbox.defaults.bool(forKey: "didShowOnboarding") == completed)
            #expect(state.clipboardAccess == .denied && !state.accessibilityGranted)
            #expect(KeyBindingsStore(defaults: sandbox.defaults).enabledGlobalActions.isEmpty)
        }
    }

    @Test func unfinished_setup_resumes_without_enabling_optional_features() throws {
        let sandbox = try IsolatedDefaults()
        let state = OnboardingState(
            defaults: sandbox.defaults, readClipboardAccess: { .requiresConsent }, readAccessibility: { false })
        state.select(.privacy)
        let resumed = OnboardingState(
            defaults: sandbox.defaults, readClipboardAccess: { .requiresConsent }, readAccessibility: { false })
        #expect(resumed.page == .privacy)
        #expect(!sandbox.defaults.bool(forKey: "didShowOnboarding"))
        let general = GeneralSettingsStore(defaults: sandbox.defaults)
        let bindings = KeyBindingsStore(defaults: sandbox.defaults)
        #expect(!general.linkPreviews)
        #expect(!general.checkForUpdates)
        #expect(bindings.enabledGlobalActions.isEmpty)
        resumed.complete()
        #expect(sandbox.defaults.bool(forKey: "didShowOnboarding"))
        #expect(sandbox.defaults.object(forKey: "onboardingPage") == nil)
    }

    @Test func the_cover_precedes_the_numbered_steps_and_reopening_resumes_after_it() throws {
        let sandbox = try IsolatedDefaults()
        func open() -> OnboardingState {
            OnboardingState(
                defaults: sandbox.defaults, readClipboardAccess: { .requiresConsent }, readAccessibility: { false })
        }
        let state = open()
        #expect(state.page == .welcome)
        #expect(Array(OnboardingPage.steps.prefix(3)) == [.basicSettings, .permissions, .practice])
        #expect(OnboardingPage.steps.map(\.stepNumber) == Array(1...8))
        state.move(1)
        #expect(state.page == .basicSettings)
        #expect(open().page == .basicSettings)
        state.move(1)
        #expect(open().page == .permissions)
        state.move(-1)
        #expect(state.page == .basicSettings)
        state.move(-1)
        #expect(state.page == .welcome)
        #expect(open().page == .welcome)

        let legacyPages: [OnboardingPage] = [
            .welcome, .permissions, .practice, .tools, .privacy, .preferences, .guide, .ready,
        ]
        for (id, page) in legacyPages.enumerated() {
            sandbox.defaults.set(id, forKey: "onboardingPage")
            #expect(open().page == page)
        }
    }

    @Test func permissions_refresh_without_prompting_and_navigation_does_not_require_access() throws {
        let sandbox = try IsolatedDefaults()
        var access = PasteboardAccess.denied
        var trusted = false
        let state = OnboardingState(
            defaults: sandbox.defaults, readClipboardAccess: { access }, readAccessibility: { trusted })
        state.refreshPermissions()
        #expect(state.clipboardAccess == .denied)
        #expect(!state.accessibilityGranted)
        state.select(.ready)
        state.move(1)
        #expect(state.page == .ready)
        access = .granted
        trusted = true
        state.refreshPermissions()
        #expect(state.clipboardAccess == .granted)
        #expect(state.accessibilityGranted)
        state.select(.welcome)
        state.move(-1)
        #expect(state.page == .welcome)
    }

    @Test func visiting_practice_does_not_complete_first_run() throws {
        let sandbox = try IsolatedDefaults()
        let state = OnboardingState(
            defaults: sandbox.defaults, readClipboardAccess: { .denied }, readAccessibility: { false })
        state.select(.practice)
        state.select(.guide)
        state.select(.practice)
        #expect(!sandbox.defaults.bool(forKey: "didShowOnboarding"))
        sandbox.defaults.set(900, forKey: "onboardingPage")
        let recovered = OnboardingState(
            defaults: sandbox.defaults, readClipboardAccess: { .denied }, readAccessibility: { false })
        #expect(recovered.page == .welcome)
    }

    @Test func every_page_fits_a_compact_window_and_renders_in_both_appearances() async throws {
        _ = NSApplication.shared
        let oldLanguage = AppLocalization.language
        let capturing = ProcessInfo.processInfo.environment["WHISK_ONBOARDING_ARTIFACTS"] != nil
        defer { if capturing { AppLocalization.language = oldLanguage } }
        let sandbox = try IsolatedDefaults()
        let bindings = KeyBindingsStore(defaults: sandbox.defaults)
        let general = GeneralSettingsStore(defaults: sandbox.defaults)
        let appearance = AppearanceSettingsStore(defaults: sandbox.defaults)
        let loginItem = LoginItemManager()
        let directory = ProcessInfo.processInfo.environment["WHISK_ONBOARDING_ARTIFACTS"].map {
            URL(fileURLWithPath: $0)
        }
        if let directory { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        for language in capturing ? ["zh-Hans", "zh-Hant", "en", "fr", "de", "it", "ja"] : [oldLanguage ?? "en"] {
            if capturing { AppLocalization.language = language }
            let state = OnboardingState(
                defaults: sandbox.defaults, readClipboardAccess: { .requiresConsent }, readAccessibility: { false })
            for page in OnboardingPage.allCases {
                state.select(page)
                for dark in [false, true] {
                    let size = NSSize(
                        width: language == "zh-Hans" ? 980 : 780, height: language == "zh-Hans" ? 700 : 540)
                    let view = MacOS15OnboardingView(
                        state: state, bindings: bindings, general: general, appearance: appearance, loginItem: loginItem
                    )
                    .environment(\.colorScheme, dark ? .dark : .light)
                    try await snapshot(
                        view, size: size, dark: dark, directory: directory,
                        name: "\(language)-\(page.rawValue)-\(dark ? "dark" : "light")")
                }
            }
        }
    }

    @Test func largest_interface_text_previews_in_compact_setup() async throws {
        _ = NSApplication.shared
        let directory = ProcessInfo.processInfo.environment["WHISK_ONBOARDING_ARTIFACTS"].map {
            URL(fileURLWithPath: $0)
        }
        let oldLanguage = AppLocalization.language
        defer { if directory != nil { AppLocalization.language = oldLanguage } }
        let sandbox = try IsolatedDefaults()
        let state = OnboardingState(defaults: sandbox.defaults, readClipboardAccess: { .denied })
        let bindings = KeyBindingsStore(defaults: sandbox.defaults)
        let general = GeneralSettingsStore(defaults: sandbox.defaults)
        let appearance = AppearanceSettingsStore(defaults: sandbox.defaults)
        let login = LoginItemManager()
        let languages = directory == nil ? [oldLanguage ?? "en"] : AppLanguage.allCases.compactMap(\.code)
        let sizes = directory == nil ? [300] : [85, 100, 150, 151, 200, 250, 300]
        for language in languages {
            if directory != nil { AppLocalization.language = language }
            for percent in sizes {
                appearance.setInterfaceFontPercent(percent)
                #expect(
                    AppearanceSettingsStore(defaults: sandbox.defaults).interfaceTypography
                        == appearance.interfaceTypography)
                for page in OnboardingPage.allCases {
                    state.select(page)
                    let view = MacOS15OnboardingView(
                        state: state, bindings: bindings, general: general, appearance: appearance, loginItem: login
                    )
                    .transaction { $0.disablesAnimations = true }
                    try await snapshot(
                        view, size: NSSize(width: 780, height: 508), dark: false, directory: directory,
                        name: "\(language)-\(percent)-onboarding-\(page.rawValue)")
                }
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["WHISK_EXHAUSTIVE_TYPOGRAPHY"] == "1"))
    func every_setup_page_keeps_a_readable_document_at_every_font_size() async throws {
        _ = NSApplication.shared
        let saved = AppLocalization.language
        defer { AppLocalization.language = saved }
        let sandbox = try IsolatedDefaults()
        let state = OnboardingState(
            defaults: sandbox.defaults, readClipboardAccess: { .denied }, readAccessibility: { false })
        let appearance = AppearanceSettingsStore(defaults: sandbox.defaults)
        let context = OnboardingUIContext(
            state: state, bindings: KeyBindingsStore(defaults: sandbox.defaults),
            general: GeneralSettingsStore(defaults: sandbox.defaults), appearance: appearance,
            loginItem: LoginItemManager(), actions: OnboardingActions())
        let viewport = NSSize(width: 780, height: 508)

        func scrolls(_ view: NSView) -> [NSScrollView] {
            if let scroll = view as? NSScrollView { return [scroll] }
            return view.subviews.flatMap(scrolls)
        }
        for language in AppLanguage.allCases {
            AppLocalization.language = language.code
            appearance.language = language
            let handle = AppUISelector.make().makeOnboardingWindow(context: context)
            defer { handle.release() }
            handle.window.setContentSize(viewport)
            let host = try #require(handle.window.contentView)
            for page in OnboardingPage.allCases {
                state.select(page)
                try await Task.sleep(for: .milliseconds(350))
                for percent in InterfaceTypography.percentRange {
                    appearance.setInterfaceFontPercent(percent)
                    await Task.yield()
                    host.layoutSubtreeIfNeeded()
                    let comment = Comment(rawValue: "\(language.rawValue)-\(page)-\(percent)")
                    let document = try #require(
                        scrolls(host).filter { $0.contentSize.width > 380 }.max {
                            $0.contentSize.height < $1.contentSize.height
                        }, comment)
                    #expect(document.contentSize.height >= appearance.interfaceTypography.lineHeight(13) * 2, comment)
                    #expect(document.contentView.documentRect.width <= document.contentSize.width + 1, comment)
                    #expect(
                        host.bounds.insetBy(dx: -1, dy: -1).contains(host.convert(document.bounds, from: document)),
                        comment)
                }
            }
        }
    }

    @Test func practice_shortcut_and_permission_states_render() async throws {
        _ = NSApplication.shared
        let oldLanguage = AppLocalization.language
        let directory = ProcessInfo.processInfo.environment["WHISK_ONBOARDING_ARTIFACTS"].map {
            URL(fileURLWithPath: $0)
        }
        if directory != nil { AppLocalization.language = "zh-Hans" }
        defer { if directory != nil { AppLocalization.language = oldLanguage } }
        let sandbox = try IsolatedDefaults()
        var access = PasteboardAccess.requiresConsent
        var trusted = false
        let state = OnboardingState(
            defaults: sandbox.defaults, readClipboardAccess: { access }, readAccessibility: { trusted })
        let bindings = KeyBindingsStore(defaults: sandbox.defaults)
        let general = GeneralSettingsStore(defaults: sandbox.defaults)
        let appearance = AppearanceSettingsStore(defaults: sandbox.defaults)
        let login = LoginItemManager()
        for dark in [false, true] {
            for variant in ["menu", "enabled", "recording", "permissions-partial", "permissions-ready"] {
                let isPermissions = variant.hasPrefix("permissions")
                access = variant == "menu" || variant == "permissions-partial" ? .requiresConsent : .granted
                trusted = variant != "menu"
                state.select(isPermissions ? .permissions : .practice)
                bindings.endRecording()
                bindings.setGlobalEnabled(variant == "enabled", for: .togglePanel)
                if variant == "recording" { bindings.beginRecording(.togglePanel) }
                let view = MacOS15OnboardingView(
                    state: state, bindings: bindings, general: general, appearance: appearance, loginItem: login
                )
                .environment(\.colorScheme, dark ? .dark : .light)
                try await snapshot(
                    view, size: NSSize(width: 980, height: 700), dark: dark, directory: directory,
                    name: "practice-\(variant)-\(dark ? "dark" : "light")")
            }
        }
    }

    private func snapshot<V: View>(
        _ view: V, size: NSSize, dark: Bool, directory: URL?, name: String
    ) async throws {
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        MacOS15OnboardingWindowConfiguration.apply(to: window)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.setContentSize(size)
        defer { window.close(); window.contentView = nil }
        let host = hosting.view
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(directory == nil ? 10 : 60))
        host.layoutSubtreeIfNeeded()
        #expect(host.bounds.size == size, "\(name)")
        #expect(window.standardWindowButton(.closeButton)?.isHidden == false)
        let frameView = try #require(host.superview)
        let bitmap = try #require(frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds))
        frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
        #expect(bitmap.pixelsWide > 0)
        if let directory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent(name + ".png"))
        }
    }

}

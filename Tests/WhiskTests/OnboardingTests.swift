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
    @Test func debug_replay_restarts_the_guide_and_practice_without_resetting_completion() throws {
        for completed in [false, true] {
            let sandbox = try IsolatedDefaults()
            sandbox.defaults.set(completed, forKey: "didShowOnboarding")
            let state = OnboardingState(
                defaults: sandbox.defaults, readClipboardAccess: { .denied }, readAccessibility: { false })
            state.select(.ready)
            state.practice.addExample()
            state.practice.perform(.paste)
            #expect(state.isPracticeComplete)
            state.restart()
            #expect(state.page == .welcome)
            #expect(!state.isPracticeComplete)
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
        #expect(OnboardingPage.steps.first == .permissions)
        #expect(OnboardingPage.steps.map(\.rawValue) == Array(1...7))
        state.select(.permissions)
        #expect(open().page == .permissions)
        state.move(-1)
        #expect(state.page == .welcome)
        #expect(open().page == .welcome)
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

    @Test func practice_is_repeatable_and_does_not_complete_first_run() throws {
        let sandbox = try IsolatedDefaults()
        let state = OnboardingState(
            defaults: sandbox.defaults, readClipboardAccess: { .denied }, readAccessibility: { false })
        state.practice.addExample()
        state.practice.perform(.paste)
        #expect(state.isPracticeComplete)
        state.practice.query = "Hello"
        state.select(.guide)
        state.select(.practice)
        #expect(state.isPracticeComplete)
        #expect(!sandbox.defaults.bool(forKey: "didShowOnboarding"))
        state.practice.reset()
        #expect(!state.practice.hasExample)
        #expect(state.practice.query.isEmpty)
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
        for language in capturing ? ["zh-Hans", "zh-Hant", "en", "fr", "de", "it"] : [oldLanguage ?? "en"] {
            if capturing { AppLocalization.language = language }
            let state = OnboardingState(
                defaults: sandbox.defaults, readClipboardAccess: { .requiresConsent }, readAccessibility: { false })
            for page in OnboardingPage.allCases {
                state.select(page)
                if page == .practice { state.practice.reset(); state.practice.addExample() }
                for dark in [false, true] {
                    let size = NSSize(
                        width: language == "zh-Hans" ? 980 : 780, height: language == "zh-Hans" ? 700 : 540)
                    let view = OnboardingView(
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
    @Test func practice_presentations_expanded_settings_and_permission_states_render() async throws {
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
            for variant in [
                "initial", "preview", "menu", "edit", "split", "pasted", "expanded", "recording", "permissions-partial",
                "permissions-ready",
            ] {
                state.select(variant.hasPrefix("permissions") ? .permissions : .practice)
                access = variant == "permissions-ready" ? .granted : .requiresConsent
                trusted = variant.hasPrefix("permissions")
                state.refreshPermissions()
                state.practice.reset()
                state.practice.moreInteractions = variant == "expanded"
                general.interactions.hover = .none
                bindings.endRecording()
                if variant != "initial" { state.practice.addExample() }
                switch variant {
                case "preview": state.practice.perform(.preview)
                case "menu": state.practice.perform(.menu)
                case "edit": state.practice.perform(.edit)
                case "split": state.practice.perform(.split)
                case "pasted": state.practice.perform(.paste)
                case "expanded": general.interactions.hover = .preview
                case "recording": bindings.beginRecording(.copySelection)
                default: break
                }
                let view = OnboardingView(
                    state: state, bindings: bindings, general: general, appearance: appearance, loginItem: login
                )
                .environment(\.colorScheme, dark ? .dark : .light)
                try await snapshot(
                    view, size: NSSize(width: 980, height: 700), dark: dark, directory: directory,
                    name: "practice-\(variant)-\(dark ? "dark" : "light")",
                    bottom: variant == "expanded" || variant == "recording")
            }
        }
    }

    private func snapshot<V: View>(
        _ view: V, size: NSSize, dark: Bool, directory: URL?, name: String, bottom: Bool = false
    ) async throws {
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        OnboardingWindowConfiguration.apply(to: window)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.setContentSize(size)
        defer { window.close(); window.contentView = nil }
        let host = hosting.view
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(directory == nil ? 10 : 60))
        host.layoutSubtreeIfNeeded()
        if bottom {
            func scrollViews(_ view: NSView) -> [NSScrollView] {
                ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrollViews)
            }
            if let scroll = scrollViews(host).first(where: { $0.bounds.width > 400 }),
                let document = scroll.documentView
            {
                scroll.contentView.scroll(
                    to: NSPoint(x: 0, y: max(0, document.bounds.height - scroll.contentView.bounds.height)))
                scroll.reflectScrolledClipView(scroll.contentView)
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(60))
            }
        }
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

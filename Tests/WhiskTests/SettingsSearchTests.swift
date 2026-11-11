// WhiskyMac: modified or added 2026-11-07 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI
import Testing
import Vision

@testable import Whisk

@MainActor
@Suite(.serialized)
struct SettingsSearchTests {
    @Test func query_highlights_preserve_localized_text_and_pointer_selection() {
        let title = "Réglages · REGLAGES · 设置"
        let ranges = SettingsSearchIndex.matchingRanges(in: title, query: "reglages 设置")
        #expect(ranges.map { String(title[$0]) } == ["Réglages", "REGLAGES", "设置"])
        #expect(SettingsSearchIndex.matchingRanges(in: title, query: "  ").isEmpty)
        let search = SettingsSearchModel()
        search.query = "shortcuts"
        let revision = search.keyboardSelectionRevision
        search.hover(at: 2)
        #expect(search.selectedIndex == 2)
        #expect(search.keyboardSelectionRevision == revision)
        search.move(1)
        #expect(search.selectedIndex == 3)
        #expect(search.keyboardSelectionRevision > revision)
    }

    @Test func search_matches_localized_names_english_keywords_and_accents() {
        let previous = AppLocalization.language
        defer { AppLocalization.language = previous }
        let context = SettingsSearchContext()
        for (language, query, expected) in [
            ("zh-Hans", "清空历史", "clearHistory"), ("zh-Hans", "音量", "volume"),
            ("zh-Hans", "CARD SIZE", "cardSize"), ("fr", "DISPOSITION DES REGLAGES", "navigation"),
            ("de", "GROSSE", "cardSize"), ("it", "volume", "volume"),
        ] {
            AppLocalization.language = language
            let results = SettingsSearchIndex.matches(query, context: context)
            #expect(results.first?.id == expected, "\(language): \(query)")
            let title = SettingsSearchIndex.entries(context: context).first { $0.id == expected }!.title.localized
            #expect(
                SettingsSearchIndex.matches(
                    title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil), context: context
                ).first?.id == expected)
        }
        #expect(SettingsSearchIndex.matches("  ", context: context).isEmpty)
        #expect(SettingsSearchIndex.matches("NONEXISTENTSEARCH123", context: context).isEmpty)
        AppLocalization.language = "en"
        #expect(SettingsSearchIndex.matches("Sound volume", context: context).first?.id == "volume")
        #expect(SettingsSearchIndex.matches("Sounds and effects", context: context).map(\.id).contains("volume"))
        #expect(SettingsSearchIndex.matches("privacy", context: context).first?.id == "privacyIcon")
        let entries = SettingsSearchIndex.entries(context: context)
        #expect(Set(entries.map(\.id)).count == entries.count)
    }

    @Test func availability_and_prerequisites_are_resolved_without_changing_settings() {
        var context = SettingsSearchContext()
        context.checksForUpdates = false
        context.isProtected = true
        let hidden = SettingsSearchIndex.entries(context: context)
        #expect(!hidden.contains { $0.section == .sensitiveAccess })
        #expect(!hidden.contains { $0.id == "checkUpdates" || $0.id == "startupUpdates" })
        #expect(hidden.first { $0.id == "normal.delay" }?.destination.anchor == "normal.hover")
        #expect(hidden.first { $0.id == "vim.undo" }?.destination.anchor == "vim")
        context.normalHover = true
        context.vimEnabled = true
        let enabled = SettingsSearchIndex.entries(context: context)
        #expect(enabled.first { $0.id == "normal.delay" }?.destination.anchor == "normal.delay")
        #expect(enabled.first { $0.id == "vim.undo" }?.destination.anchor == "vim.undo")
        let destination = SettingsDestination(section: .network, anchor: "linkPreviews")
        #expect(destination.resolvedSection(isProtected: false) == .network)
        #expect(destination.resolvedSection(isProtected: true) == .network)
        #expect(SettingsDestination(section: .sensitiveAccess).resolvedSection(isProtected: true) == nil)
        #expect(SettingsDestination(page: .about, sectionIndex: 2).resolvedSection(isProtected: false) == .licenses)
    }

    @Test func selecting_and_dismissing_search_only_changes_navigation() throws {
        let sandbox = try IsolatedDefaults()
        let settings = GeneralSettingsStore(defaults: sandbox.defaults)
        let side = settings.cardSide
        let search = SettingsSearchModel()
        search.query = "card size"
        #expect(search.isPresented)
        search.activateSelection()
        #expect(search.query.isEmpty)
        #expect(!search.isPresented)
        #expect(search.destination?.section == .cards)
        #expect(search.highlightedAnchor == "cardSize")
        #expect(settings.cardSide == side)
        search.query = "shortcut"
        search.move(1000)
        #expect(search.selectedIndex == search.results.count - 1)
        let selected = search.results[search.selectedIndex].id
        // Native text fields may commit the same value again before onSubmit.
        search.query = "shortcut"
        #expect(search.results[search.selectedIndex].id == selected)
        search.move(-1000)
        #expect(search.selectedIndex == 0)
        search.dismiss()
        #expect(!search.isPresented)
        #expect(search.query == "shortcut")
        search.refresh(context: SettingsSearchContext(isProtected: true))
        #expect(!search.isPresented, "Refreshing availability must not reopen a dismissed list")
        search.reset()
        #expect(search.destination == nil)
        #expect(search.highlightedAnchor == nil)
        #expect(search.query.isEmpty)
    }

    @Test func titled_window_results_stay_nonactivating_and_scroll_after_six_rows() async throws {
        _ = NSApplication.shared
        let previous = AppLocalization.language
        defer { AppLocalization.language = previous }
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 840, height: 360),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSView()
        SettingsWindowConfiguration.apply(to: window)
        let search = SettingsSearchModel()
        let toolbar = SettingsSearchToolbar(window: window, search: search)
        window.orderFront(nil)
        defer { window.close(); withExtendedLifetime(toolbar) {} }

        for language in ["zh-Hans", "en", "fr", "de", "it"] {
            AppLocalization.language = language
            search.refresh(context: SettingsSearchContext())
            search.query = "shortcuts"
            await pump(toolbar.fieldHost)
            let panel = try #require(toolbar.resultsPanel)
            #expect(panel.isVisible)
            #expect(panel.parent === window)
            #expect(!panel.canBecomeKey && !panel.canBecomeMain)
            #expect(search.results.count > 6)
            #expect(abs(panel.frame.height - 6 * SettingsSearchResults.rowHeight) < 0.5)
            let view = try #require(panel.contentView)
            await pump(view)
            search.move(7)
            await pump(view)
            let scroll = try #require(scrollViews(view).first)
            #expect(scroll.documentVisibleRect.minY > 0)
            if let output = ProcessInfo.processInfo.environment["WHISK_UI_ARTIFACTS"] {
                let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(
                    to: URL(fileURLWithPath: output).appendingPathComponent("search-results-\(language).png"))
            }
            search.query = "NONEXISTENTSEARCH123"
            await pump(view)
            #expect(panel.isVisible && search.results.isEmpty)
            #expect(panel.frame.height == 64)
            search.query = ""
            await pump(view)
            #expect(!panel.isVisible)
        }
        search.query = "card size"
        await pump(toolbar.fieldHost)
        window.close()
        #expect(search.query.isEmpty)
        #expect(toolbar.resultsPanel?.isVisible == false)
    }

    @Test func titled_window_search_clears_traffic_lights_and_scrolls_to_results() async throws {
        _ = NSApplication.shared
        let previous = AppLocalization.language
        AppLocalization.language = "en"
        defer { AppLocalization.language = previous }
        let sandbox = try IsolatedDefaults()
        let appearance = AppearanceSettingsStore(defaults: sandbox.defaults)
        let general = GeneralSettingsStore(defaults: sandbox.defaults)
        let privacy = PrivacyController(defaults: sandbox.defaults)
        let search = SettingsSearchModel()

        for navigation in SettingsNavigation.allCases {
            appearance.navigation = navigation
            let hosting = NSHostingController(
                rootView: SettingsView(
                    store: KeyBindingsStore(defaults: sandbox.defaults), general: general,
                    loginItem: LoginItemManager(), vimBindings: VimBindingsStore(defaults: sandbox.defaults),
                    privacy: privacy, appearance: appearance, search: search
                )
                .environment(
                    \.settingsAccessibilityOverride,
                    SettingsAccessibilityValues(reduceMotion: navigation == .top)))
            let window = NSWindow(contentViewController: hosting)
            window.isReleasedWhenClosed = false
            window.styleMask.remove([.resizable, .miniaturizable])
            SettingsWindowConfiguration.apply(to: window)
            let toolbar = SettingsSearchToolbar(window: window, search: search, appearance: appearance)
            window.setContentSize(NSSize(width: 840, height: SettingsWindowSize.minimumHeight))
            window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
            window.orderFront(nil)
            defer { window.close(); withExtendedLifetime(toolbar) {} }
            window.displayIfNeeded()
            await pump(hosting.view)
            let field = toolbar.fieldHost.convert(toolbar.fieldHost.bounds, to: nil)
            let close = try #require(window.standardWindowButton(.closeButton))
            let closeFrame = close.convert(close.bounds, to: nil)
            #expect(field.minX > closeFrame.maxX + 40)
            #expect(abs(field.midY - closeFrame.midY) < 12)
            #expect(field.width == 260)
            let navigationView = try #require(
                window.toolbar?.items.first { $0.itemIdentifier == SettingsSearchToolbar.navigationID }?.view)
            let brandView = try #require(
                window.toolbar?.items.first { $0.itemIdentifier == SettingsSearchToolbar.brandID }?.view)
            let navigationFrame = navigationView.convert(navigationView.bounds, to: nil)
            let brandFrame = brandView.convert(brandView.bounds, to: nil)
            #expect(abs(navigationFrame.midY - field.midY) < 1)
            #expect(abs(brandFrame.midY - field.midY) < 1)
            #expect(navigationFrame.maxX < field.minX)
            #expect(field.maxX < brandFrame.minX)

            search.activate("diameter")
            await pump(hosting.view)
            #expect(search.destination?.section == .privacyInteractions)
            #expect(search.highlightedAnchor == "diameter")
            #expect(try visibleText(hosting.view).contains("diameter"))

            search.activate("shortcut.togglePinned")
            await pump(hosting.view)
            #expect(search.destination?.section == .globalShortcuts)
            #expect(search.highlightedAnchor == "shortcut.togglePinned")
            #expect(try visibleText(hosting.view).contains("showhidepinneditems"))
            if let output = ProcessInfo.processInfo.environment["WHISK_UI_ARTIFACTS"] {
                let directory = URL(fileURLWithPath: output)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let frameView = try #require(hosting.view.superview)
                let bitmap = try #require(frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds))
                frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(
                    to: directory.appendingPathComponent("pinned-shortcut-\(navigation.rawValue).png"))
            }

            search.activate("shortcut.undoLastChange")
            await pump(hosting.view)
            if let output = ProcessInfo.processInfo.environment["WHISK_UI_ARTIFACTS"] {
                let directory = URL(fileURLWithPath: output)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let frameView = try #require(hosting.view.superview)
                let bitmap = try #require(frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds))
                frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(
                    to: directory.appendingPathComponent("search-\(navigation.rawValue).png"))
            }
            let scroll = try #require(
                scrollViews(hosting.view).filter { $0.bounds.width > 400 }.max { $0.bounds.height < $1.bounds.height })
            #expect(scroll.documentVisibleRect.minY > 100, "\(navigation): must scroll to the last shortcut")
            #expect(search.highlightedAnchor == "shortcut.undoLastChange")

            NotificationCenter.default.post(
                name: .settingsPageRequested, object: SettingsDestination(section: .aboutApp, anchor: "feedback"))
            await pump(hosting.view)
            let aboutScroll = try #require(
                scrollViews(hosting.view).filter { $0.bounds.width > 400 }.max { $0.bounds.height < $1.bounds.height })
            #expect(aboutScroll.documentVisibleRect.minY > 100, "\(navigation): must scroll through About cards")
            #expect(search.highlightedAnchor == "feedback")

            search.activate("linkPreviews")
            await pump(hosting.view)
            privacy.setProtected(true)
            await pump(hosting.view)
            #expect(search.destination?.resolvedSection(isProtected: true) == .network)
            #expect(try visibleText(hosting.view).contains("fetchlinkpreviews"))
            #expect(!search.results.contains { $0.section == .sensitiveAccess })
            search.activate("sensitiveApps")
            #expect(search.destination?.section == .network)
            privacy.setProtected(false)

            search.reset()
        }
    }

    private func pump(_ view: NSView) async {
        view.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(350))
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
    }

    private func scrollViews(_ view: NSView) -> [NSScrollView] {
        ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrollViews)
    }

    private func visibleText(_ view: NSView) throws -> String {
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: try #require(bitmap.cgImage)).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined()
            .filter(\.isLetter).lowercased()
    }
}

// WhiskyMac: modified or added 2026-11-18 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI
import Testing

@testable import Whisk

@MainActor
@Suite(.serialized) struct SizePreviewTests {
    @Test func screen_preview_restores_saved_sizes_and_repeated_previews_do_not_chain_unsaved_values() throws {
        _ = NSApplication.shared
        let sandbox = try IsolatedDefaults()
        let state = HistoryViewStateStore()
        state.configureCards(side: 217.5)
        state.configureFilterTags(scale: 1.15)
        let controller = PanelController(
            stateStore: state, actions: PanelActionSpy().actions,
            keyBindings: KeyBindingsStore(defaults: sandbox.defaults),
            vimBindings: VimBindingsStore(defaults: sandbox.defaults), vimMode: { false })
        let screen = try #require(NSScreen.main)
        controller.prepareSizingPreview(.init(cardSide: 500, tagScale: 2), on: screen)
        #expect(controller.isSizePreview)
        #expect(state.cardSide == 500 && state.filterTagScale == 2)
        #expect(
            controller.activeWindow.frame
                == PanelLayout(screen: PanelLayout.Screen(screen), cardSide: 500, tagScale: 2).panel)
        controller.prepareSizingPreview(.init(cardSide: 300, tagScale: 1.5), on: screen)
        #expect(state.cardSide == 300 && state.filterTagScale == 1.5)
        controller.cancelSizePreview()
        #expect(!controller.isSizePreview && !controller.activeWindow.isVisible)
        #expect(state.cardSide == 217.5 && state.filterTagScale == 1.15)
        controller.prepareSizingPreview(.init(cardSide: 350, tagScale: 1.8), on: screen)
        controller.preparePresentation(pins: false, style: nil, on: screen)
        #expect(!controller.isSizePreview)
        #expect(state.cardSide == 217.5 && state.filterTagScale == 1.15)
    }

    @Test func tag_preview_uses_the_same_scaled_geometry_as_the_real_filters() async throws {
        _ = NSApplication.shared
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        var chipHeights: [CGFloat] = []
        for scale in [1.0, 2.0] {
            let host = NSHostingView(rootView: FilterTagSizePreview(scale: scale))
            host.sizingOptions = []
            let window = NSWindow(
                contentRect: NSRect(x: -10000, y: 0, width: 520, height: FilterTagMetrics(scale: scale).rowHeight + 8),
                styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.contentView = nil; window.close() }
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(350))
            host.layoutSubtreeIfNeeded()
            let surfaces = descendants(host).compactMap { $0 as? BackdropView }
            chipHeights.append(try #require(surfaces.map { $0.bounds.height }.max()))
            #expect(host.bounds.height >= FilterTagMetrics(scale: scale).rowHeight)
            if let output = ProcessInfo.processInfo.environment["WHISK_UI_ARTIFACTS"] {
                let directory = URL(fileURLWithPath: output)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(
                    to: directory.appendingPathComponent("tag-size-\(Int(scale * 100)).png"))
            }
        }
        #expect(chipHeights[1] > chipHeights[0] * 1.8)
    }

    @Test func titled_settings_window_shows_both_size_pages_and_search_targets() async throws {
        _ = NSApplication.shared
        let previousLanguage = AppLocalization.language
        AppLocalization.language = "zh-Hans"
        defer { AppLocalization.language = previousLanguage }
        let sandbox = try IsolatedDefaults()
        let general = GeneralSettingsStore(defaults: sandbox.defaults)
        general.setCardSide(500)
        general.setFilterTagScale(2)
        let appearance = AppearanceSettingsStore(defaults: sandbox.defaults)
        let search = SettingsSearchModel()
        for navigation in SettingsNavigation.allCases {
            appearance.navigation = navigation
            let hosting = NSHostingController(
                rootView: SettingsView(
                    store: KeyBindingsStore(defaults: sandbox.defaults), general: general,
                    loginItem: LoginItemManager(), vimBindings: VimBindingsStore(defaults: sandbox.defaults),
                    appearance: appearance, search: search
                ).environment(\.settingsAccessibilityOverride, SettingsAccessibilityValues(reduceMotion: true)))
            let window = NSWindow(contentViewController: hosting)
            window.isReleasedWhenClosed = false
            SettingsWindowConfiguration.apply(to: window)
            let toolbar = SettingsSearchToolbar(window: window, search: search, appearance: appearance)
            window.setContentSize(NSSize(width: 840, height: 720))
            window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
            window.orderFront(nil)
            defer { window.close(); withExtendedLifetime(toolbar) {} }
            hosting.view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(350))
            for section in [SettingsSectionID.cards, .filterTags] {
                search.navigate(to: SettingsDestination(section: section))
                hosting.view.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(450))
                hosting.view.layoutSubtreeIfNeeded()
                #expect(window.attachedSheet == nil)
                if section == .cards {
                    func scrollViews(_ view: NSView) -> [NSScrollView] {
                        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
                    }
                    let scroll = try #require(
                        scrollViews(hosting.view).first {
                            $0.frame.width > 300
                                && ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height + 1
                        })
                    let document = try #require(scroll.documentView)
                    #expect(document.frame.height > scroll.contentView.bounds.height)
                    scroll.contentView.scroll(
                        to: NSPoint(x: 0, y: document.frame.height - scroll.contentView.bounds.height))
                    scroll.reflectScrolledClipView(scroll.contentView)
                    #expect(scroll.documentVisibleRect.maxY >= document.frame.height - 1)
                }
                if let output = ProcessInfo.processInfo.environment["WHISK_UI_ARTIFACTS"] {
                    let directory = URL(fileURLWithPath: output)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let view = try #require(window.contentView?.superview)
                    let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])?.write(
                        to: directory.appendingPathComponent("size-settings-\(navigation)-\(section).png"))
                }
            }
        }
    }
}

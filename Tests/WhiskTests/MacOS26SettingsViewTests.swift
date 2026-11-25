// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI
import Testing

@testable import Whisk

@MainActor
@Suite(.serialized)
struct MacOS26SettingsViewTests {
    @Test(.enabled(if: ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26))
    func both_layouts_mount_each_available_section_and_keep_search_destinations() async throws {
        guard #available(macOS 26, *) else { return }
        _ = NSApplication.shared
        let sandbox = try IsolatedDefaults()
        let defaults = sandbox.defaults
        let appearance = AppearanceSettingsStore(defaults: defaults)
        let general = GeneralSettingsStore(defaults: defaults)
        let bindings = KeyBindingsStore(defaults: defaults)
        let vim = VimBindingsStore(defaults: defaults)
        let privacy = PrivacyController(defaults: defaults, schedulesTimer: false)
        let search = SettingsSearchModel()
        let developer = DeveloperModeStore(defaults: defaults, channel: .debug)
        general.vimNavigation = true
        appearance.accentMode = .custom
        let hosting = NSHostingController(
            rootView: MacOS26SettingsView(
                store: bindings, general: general, loginItem: LoginItemManager(), vimBindings: vim,
                privacy: privacy, appearance: appearance, updateChecker: UpdateChecker(defaults: defaults),
                search: search, developerMode: developer)
        )
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 840, height: 520))
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        let toolbar = MacOS26SettingsToolbar(window: window, search: search, appearance: appearance) {
            bindings.recordingAction == nil
        }
        defer { window.close(); withExtendedLifetime(toolbar) {} }

        for navigation in SettingsNavigation.allCases {
            appearance.navigation = navigation
            await layout(hosting.view)
            for section in SettingsSectionID.allCases {
                search.navigate(to: SettingsDestination(section: section))
                await layout(hosting.view)
                #expect(search.destination?.section == section)
            }
            search.activate("shortcut.undoLastChange")
            await layout(hosting.view)
            #expect(search.highlightedAnchor == "shortcut.undoLastChange")
            #expect(search.destination?.section == .panelShortcuts)
            #expect(
                scrollViews(in: hosting.view).contains { $0.bounds.width > 400 && $0.documentVisibleRect.minY > 0 },
                "\(navigation) should scroll to the last panel shortcut")

            general.pinnedPresentation = .aggregated
            await layout(hosting.view)
            search.activate("pinnedWindowStyle")
            #expect(search.highlightedAnchor == "pinnedPresentation")
            general.pinnedPresentation = .separate
            await layout(hosting.view)
            search.activate("pinnedWindowStyle")
            #expect(search.highlightedAnchor == "pinnedWindowStyle")

            privacy.setProtected(true)
            await layout(hosting.view)
            search.activate("sensitiveApps")
            #expect(search.destination?.section == .pinnedItems)
            privacy.setProtected(false)
        }
        #expect(general.vimNavigation)
        #expect(AppearanceSettingsStore(defaults: defaults).navigation == appearance.navigation)
        bindings.beginRecording(.copySelection)
        NotificationCenter.default.post(name: .settingsWindowClosed, object: nil)
        #expect(bindings.recordingAction == nil)
    }

    private func layout(_ view: NSView) async {
        for _ in 0..<3 {
            view.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
        view.displayIfNeeded()
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        let descendants = view.subviews.flatMap(scrollViews)
        return (view as? NSScrollView).map { [$0] + descendants } ?? descendants
    }
}

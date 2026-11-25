import AppKit
import SwiftUI
import Testing

@testable import Whisk

@MainActor
@Suite struct UIIsolationSnapshots {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WHISK_UI_ISOLATION_SNAPSHOTS"] != nil))
    func isolated_synthetic_surfaces_keep_their_original_layout() throws {
        let destination = try #require(ProcessInfo.processInfo.environment["WHISK_UI_ISOLATION_SNAPSHOTS"])
        let defaults = try IsolatedDefaults()
        let bindings = KeyBindingsStore(defaults: defaults.defaults)
        let general = GeneralSettingsStore(defaults: defaults.defaults)
        let appearance = AppearanceSettingsStore(defaults: defaults.defaults)
        let privacy = PrivacyController(defaults: defaults.defaults, schedulesTimer: false)
        let search = SettingsSearchModel()
        let login = LoginItemManager()
        let state = HistoryViewStateStore()
        state.update(ViewFixtures.state())
        state.setPanelVisible(true)
        let onboarding = OnboardingState(
            defaults: defaults.defaults, readClipboardAccess: { .granted }, readAccessibility: { true })
        onboarding.select(.permissions)
        for dark in [false, true] {
            let scheme: ColorScheme = dark ? .dark : .light
            let suffix = dark ? "dark" : "light"
            try save(
                MacOS15HistoryPanelView(store: state, actions: PanelActionSpy().actions)
                    .environment(\.colorScheme, scheme),
                size: CGSize(width: 1200, height: 448), name: "history-\(suffix)", destination: destination)
            try save(
                MacOS15SettingsView(
                    store: bindings, general: general, loginItem: login,
                    vimBindings: VimBindingsStore(defaults: defaults.defaults), privacy: privacy,
                    appearance: appearance, search: search
                )
                .environment(\.colorScheme, scheme),
                size: CGSize(width: 840, height: 720), name: "settings-\(suffix)", destination: destination)
            try save(
                MacOS15OnboardingView(
                    state: onboarding, bindings: bindings, general: general, appearance: appearance, loginItem: login
                )
                .environment(\.colorScheme, scheme),
                size: CGSize(width: 980, height: 700), name: "onboarding-\(suffix)", destination: destination)
        }
        state.panelDidClose()
    }

    private func save<V: View>(_ view: V, size: CGSize, name: String, destination: String) throws {
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: view.transaction { $0.disablesAnimations = true })
        host.sizingOptions = []
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let directory = URL(fileURLWithPath: destination, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try #require(bitmap.representation(using: .png, properties: [:])).write(
            to: directory.appendingPathComponent(name + ".png"))
        window.contentView = nil
        window.close()
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI
import Testing

@testable import Whisk

@MainActor
@Suite(.serialized)
struct AppUIFactoryTests {
    @Test func startup_selects_the_factory_for_the_running_system() {
        let factory = AppUISelector.make()
        if #available(macOS 26, *) {
            #expect(factory is MacOS26UIFactory)
        } else {
            #expect(factory is MacOS15UIFactory)
        }
    }

    @Test func delegate_and_panel_use_the_injected_factory_and_share_live_state() throws {
        _ = NSApplication.shared
        let sandbox = try IsolatedDefaults()
        let defaults = sandbox.defaults
        let factory = FactorySpy()
        let delegate = AppDelegate(uiFactory: factory, defaults: defaults) { throw CocoaError(.fileWriteNoPermission) }
        let handle = delegate.makeSettingsWindow(initialPage: .about)
        defer { handle.release() }
        #expect(factory.settingsPage == .about)
        #expect(handle.window === factory.settingsWindow)

        let state = HistoryViewStateStore()
        let panel = PanelController(
            uiFactory: factory, stateStore: state, actions: PanelActionSpy().actions,
            keyBindings: KeyBindingsStore(defaults: defaults), vimBindings: VimBindingsStore(defaults: defaults),
            vimMode: { false })
        panel.preparePresentation(pins: false, style: nil)
        let original = panel.activeWindow
        #expect(original.contentView === factory.historyView)
        #expect(factory.historyContext?.store === state)
        #expect(factory.historyPresentation == .history)

        state.setPrivacy(true)
        panel.preparePresentation(pins: true, style: .mouseList)
        #expect(factory.historyPresentation == .pinnedList)
        #expect(factory.historyContext?.store.isProtected == true)
        #expect(original.contentView == nil)
        #expect(panel.activeWindow.contentView === factory.historyView)
    }

    @Test func macos15_factory_builds_all_surfaces_and_retains_the_settings_toolbar() throws {
        try checkSurfaces(MacOS15UIFactory())
    }

    @Test(.enabled(if: ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26))
    func macos26_factory_builds_all_surfaces_and_retains_the_settings_toolbar() throws {
        guard #available(macOS 26, *) else { return }
        try checkSurfaces(MacOS26UIFactory())
    }

    private func checkSurfaces(_ factory: any AppUIFactory) throws {
        _ = NSApplication.shared
        let frame = CGRect(x: 0, y: 0, width: 1440, height: 1000)
        let screen = PanelLayout.Screen(frame: frame, visibleFrame: frame, notchHeight: 0)
        #expect(
            factory.panelLayout(
                screen: screen, cardSide: 200, tagScale: 1, typography: .standard, showsSensitiveCopies: false
            ).panel.height == 438)
        #expect(
            factory.panelLayout(
                screen: screen, cardSide: 250, tagScale: 1, typography: .standard, showsSensitiveCopies: false
            ).panel.height == 488)
        #expect(
            factory.panelLayout(
                screen: screen, cardSide: 200, tagScale: 1.5, typography: .standard, showsSensitiveCopies: false
            ).panel.height == 462
        )
        let sandbox = try IsolatedDefaults()
        let defaults = sandbox.defaults
        let bindings = KeyBindingsStore(defaults: defaults)
        let general = GeneralSettingsStore(defaults: defaults)
        let appearance = AppearanceSettingsStore(defaults: defaults)
        let loginItem = LoginItemManager()
        let search = SettingsSearchModel()
        search.lastViewedSection = .clearHistory
        let settings = factory.makeSettingsWindow(
            context: SettingsUIContext(
                bindings: bindings, general: general, loginItem: loginItem,
                vimBindings: VimBindingsStore(defaults: defaults), privacy: PrivacyController(defaults: defaults),
                appearance: appearance, updateChecker: UpdateChecker(defaults: defaults),
                search: search, developerMode: DeveloperModeStore(defaults: defaults)),
            initialPage: .history)
        defer { settings.release() }
        settings.prepareForPresentation()
        let size = settings.window.contentRect(forFrameRect: settings.window.frame).size
        #expect(size.width > 0 && size.height > 0)
        settings.window.setContentSize(NSSize(width: 300, height: 250))
        settings.prepareForPresentation()
        #expect(settings.window.contentRect(forFrameRect: settings.window.frame).size == size)
        #expect(settings.window.toolbar?.delegate != nil)
        settings.window.contentView?.layoutSubtreeIfNeeded()
        search.lastViewedSection = nil
        NotificationCenter.default.post(name: .settingsWindowClosed, object: nil)
        #expect(search.lastViewedSection == .clearHistory)

        let state = OnboardingState(defaults: defaults, readClipboardAccess: { .granted }, readAccessibility: { true })
        let guide = factory.makeOnboardingWindow(
            context: OnboardingUIContext(
                state: state, bindings: bindings, general: general, appearance: appearance, loginItem: loginItem,
                actions: OnboardingActions()))
        defer { guide.release() }
        #expect(guide.window.contentView != nil)
        #expect(guide.window.frame.width > 1 && guide.window.frame.height > 1)

        let store = HistoryViewStateStore()
        let context = HistoryUIContext(store: store, actions: PanelActionSpy().actions)
        let history = factory.makeHistoryContent(context: context, presentation: .history)
        #expect(history !== factory.makeHistoryContent(context: context, presentation: .pinnedList))
        let preview = factory.makePreviewContent(context: context)
        #expect(preview !== history)
        #expect(factory.makeSplitContent(context: context, dismiss: {}) == nil)
        store.splitVersions = [anItem(.text("Synthetic split source"))]
        let split = try #require(factory.makeSplitContent(context: context, dismiss: {}))
        #expect(split.preferredSize == NSSize(width: 500, height: 380))
        let secret = anItem(.text("sk-SYNTHETIC_EXAMPLE_KEY_123456"))
        store.detailSource = { $0 == secret.id ? secret : nil }
        store.update(HistoryPresenter().present(items: [secret], query: "", now: secret.copiedAt))
        store.setPanelVisible(true)
        var actions = context.actions
        actions.revealSecret = { store.revealSecret($0) }
        let card = try #require(store.state.cards.first)
        CardMenuCommand.revealSecret.run(for: card, actions: actions, perform: { _ in })
        let revealed = try #require(factory.makeSplitContent(context: context, dismiss: { store.closeSplitSessions() }))
        revealed.view.frame.size = revealed.preferredSize
        revealed.view.layoutSubtreeIfNeeded()
        #expect(revealed.preferredSize == NSSize(width: 480, height: 300))
        #expect(store.revealedSecret == secret.payload.transformableText)
        store.setPrivacy(true)
        #expect(factory.makeSplitContent(context: context, dismiss: {}) == nil)

        let veil = BackgroundVeilController.makeWindow(uiFactory: factory)
        #expect(veil.ignoresMouseEvents && veil.contentView != nil)
        veil.close()
        settings.release()
        #expect(settings.window.toolbar == nil)
        #expect(settings.window.contentView == nil)
    }
}

@MainActor
private final class FactorySpy: AppUIFactory {
    var settingsPage: SettingsPage?
    var settingsWindow: NSWindow?
    var historyView: NSView?
    var historyContext: HistoryUIContext?
    var historyPresentation: HistoryUIPresentation?

    func makeSettingsWindow(context: SettingsUIContext, initialPage: SettingsPage) -> AppWindowHandle {
        settingsPage = initialPage
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        settingsWindow = window
        return AppWindowHandle(window: window)
    }

    func makeHistoryContent(context: HistoryUIContext, presentation: HistoryUIPresentation) -> NSView {
        historyContext = context
        historyPresentation = presentation
        let view = NSView()
        historyView = view
        return view
    }

    func makeOnboardingWindow(context: OnboardingUIContext) -> AppWindowHandle { fatalError("Unexpected guide") }
    func makePreviewContent(context: HistoryUIContext) -> NSView { fatalError("Unexpected preview") }
    func makeSplitContent(context: HistoryUIContext, dismiss: @escaping () -> Void) -> SplitUIContent? { nil }
    func makeStatusMessage(for text: String, typography: InterfaceTypography) -> NSMenuItem { NSMenuItem() }
    func makeBackgroundContent() -> NSView { NSView() }
    func backgroundFrame(for panelFrame: CGRect) -> CGRect { panelFrame }
    func panelLayout(
        screen: PanelLayout.Screen, cardSide: CGFloat, tagScale: Double, typography: InterfaceTypography,
        showsSensitiveCopies: Bool
    ) -> PanelLayout {
        PanelLayout(panel: screen.frame, preview: screen.visibleFrame)
    }
    func pinnedFrame(pointer: CGPoint, visibleFrame: CGRect) -> CGRect { visibleFrame }
    func configure(window: NSWindow, for role: AppWindowRole) { window.isReleasedWhenClosed = false }
}

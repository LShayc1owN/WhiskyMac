// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI

@MainActor
final class MacOS15UIFactory: AppUIFactory {
    func makeSettingsWindow(context: SettingsUIContext, initialPage: SettingsPage) -> AppWindowHandle {
        let hosting = NSHostingController(
            rootView: MacOS15SettingsView(
                store: context.bindings, general: context.general, loginItem: context.loginItem,
                vimBindings: context.vimBindings, privacy: context.privacy,
                clearHistory: context.clearHistory, showWelcomeGuide: context.showWelcomeGuide,
                exportDiagnostics: context.exportDiagnostics, previewClipboard: context.previewClipboard,
                cancelClipboardPreview: context.cancelClipboardPreview, appearance: context.appearance,
                updateChecker: context.updateChecker, search: context.search,
                developerMode: context.developerMode, selectedPage: initialPage))
        let window = NSWindow(contentViewController: hosting)
        window.setContentSize(hosting.view.fittingSize)
        window.styleMask.remove([.resizable, .miniaturizable])
        MacOS15SettingsWindowConfiguration.apply(to: window)
        window.appearance = context.appearance.settingsAppearance.nsAppearance
        window.title = localized("WhiskyMac Settings")
        window.isReleasedWhenClosed = false
        let toolbar = MacOS15SettingsSearchToolbar(
            window: window, search: context.search, appearance: context.appearance, canFocus: context.canFocusSearch)
        let handle = AppWindowHandle(
            window: window, retaining: [toolbar],
            prepare: { [weak window] in
                guard let window else { return }
                let chrome = window.frame.height - window.contentRect(forFrameRect: window.frame).height
                let visible =
                    (window.screen ?? NSScreen.main)?.visibleFrame.height
                    ?? (MacOS15SettingsWindowSize.height + chrome + 2 * MacOS15SettingsWindowSize.margin)
                window.setContentSize(MacOS15SettingsWindowSize.content(visibleHeight: visible, chromeHeight: chrome))
            })
        return handle
    }

    func makeOnboardingWindow(context: OnboardingUIContext) -> AppWindowHandle {
        let hosting = NSHostingController(
            rootView: MacOS15OnboardingView(
                state: context.state, bindings: context.bindings, general: context.general,
                appearance: context.appearance, loginItem: context.loginItem, actions: context.actions))
        let window = NSWindow(contentViewController: hosting)
        MacOS15OnboardingWindowConfiguration.apply(to: window)
        window.appearance = context.appearance.settingsAppearance.nsAppearance
        let handle = AppWindowHandle(
            window: window,
            prepare: { [weak window] in
                let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1100, height: 800)
                window?.setContentSize(
                    NSSize(width: min(980, visible.width - 60), height: min(700, visible.height - 80)))
            })
        handle.prepareForPresentation()
        return handle
    }

    func makeHistoryContent(context: HistoryUIContext, presentation: HistoryUIPresentation) -> NSView {
        switch presentation {
        case .history:
            let host = panelHost(
                store: context.store,
                MacOS15HistoryPanelView(
                    store: context.store, actions: context.actions, keyBindings: context.keyBindings,
                    popoverCoordinator: context.popoverCoordinator))
            host.sizingOptions = []
            return host
        case .pinnedList:
            return panelHost(
                store: context.store,
                MacOS15PinnedListView(
                    store: context.store, actions: context.actions, keyBindings: context.keyBindings
                )
                .environment(\.cardPopoverCoordinator, context.popoverCoordinator))
        }
    }

    func makePreviewContent(context: HistoryUIContext) -> NSView {
        let host = panelHost(
            store: context.store, MacOS15PreviewOverlayView(store: context.store, actions: context.actions))
        host.sizingOptions = []
        return host
    }

    func makeSplitContent(context: HistoryUIContext, dismiss: @escaping () -> Void) -> SplitUIContent? {
        let store = context.store
        if store.revealedSecret != nil {
            return auxiliaryContent(
                MacOS15SecretRevealView(store: store, dismiss: dismiss), store: store,
                preferredSize: NSSize(width: 480, height: 300))
        }
        if !store.splitVersions.isEmpty {
            return auxiliaryContent(
                MacOS15SplitVersionView(store: store), store: store,
                preferredSize: NSSize(width: 500, height: 380))
        }
        if let session = store.splitSession {
            return auxiliaryContent(
                MacOS15SplitContentView(session: session, close: dismiss), store: store,
                preferredSize: NSSize(width: 660, height: 740))
        }
        if let session = store.splitGroupSession {
            return auxiliaryContent(
                MacOS15SplitGroupView(session: session, close: dismiss), store: store,
                preferredSize: NSSize(width: 540, height: 540))
        }
        return nil
    }

    private func auxiliaryContent<Content: View>(
        _ content: Content, store: HistoryViewStateStore, preferredSize: NSSize
    ) -> SplitUIContent {
        let host = panelHost(store: store, content)
        // The window caps its size to the current screen. SwiftUI scrolls within that frame.
        host.sizingOptions = []
        return SplitUIContent(view: host, preferredSize: preferredSize)
    }

    private func panelHost<Content: View>(store: HistoryViewStateStore, _ content: Content)
        -> NSHostingView<MacOS15PanelTypography<Content>>
    {
        NSHostingView(rootView: MacOS15PanelTypography(store: store, content: content))
    }

    func makeStatusMessage(for text: String, typography: InterfaceTypography) -> NSMenuItem {
        MacOS15StatusMenuMessage.item(for: text, typography: typography)
    }

    func backgroundFrame(for panelFrame: CGRect) -> CGRect {
        // Keep the veil aligned to the panel's bottom while lowering its top edge.
        CGRect(
            origin: panelFrame.origin,
            size: CGSize(width: panelFrame.width, height: (panelFrame.height * 0.93).rounded()))
    }

    func makeBackgroundContent() -> NSView { NSHostingView(rootView: MacOS15GradientBlurVeil()) }
    func panelLayout(
        screen: PanelLayout.Screen, cardSide: CGFloat, tagScale: Double, typography: InterfaceTypography,
        showsSensitiveCopies: Bool
    ) -> PanelLayout {
        MacOS15PanelLayout(
            screen: screen, cardSide: cardSide, tagScale: tagScale, typography: typography,
            showsSensitiveCopies: showsSensitiveCopies
        ).result
    }
    func pinnedFrame(pointer: CGPoint, visibleFrame: CGRect) -> CGRect {
        MacOS15PinnedWindowLayout.frame(pointer: pointer, visibleFrame: visibleFrame)
    }

    func configure(window: NSWindow, for role: AppWindowRole) {
        window.isReleasedWhenClosed = false
        if let panel = window as? NSPanel { panel.isFloatingPanel = true }
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        if role == .split {
            window.title = localized("Split…")
        } else {
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
        }
        if role == .backgroundVeil { window.ignoresMouseEvents = true }
        if role == .history || role == .pinned {
            window.isMovable = false
            window.hidesOnDeactivate = false
        }
    }
}

private struct MacOS15PanelTypography<Content: View>: View {
    @ObservedObject var store: HistoryViewStateStore
    let content: Content

    var body: some View { content.interfaceType(store.interfaceTypography) }
}

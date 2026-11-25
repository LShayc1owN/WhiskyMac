// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

struct SettingsUIContext {
    let bindings: KeyBindingsStore
    let general: GeneralSettingsStore
    let loginItem: LoginItemManager
    let vimBindings: VimBindingsStore
    let privacy: PrivacyController
    let appearance: AppearanceSettingsStore
    let updateChecker: UpdateChecker
    let search: SettingsSearchModel
    let developerMode: DeveloperModeStore
    var clearHistory: () -> Void = {}
    var showWelcomeGuide: () -> Void = {}
    var exportDiagnostics: () async throws -> Void = {}
    var previewClipboard: (Double, Double) -> Void = { _, _ in }
    var cancelClipboardPreview: () -> Void = {}
    var canFocusSearch: () -> Bool = { true }
}

struct OnboardingUIContext {
    let state: OnboardingState
    let bindings: KeyBindingsStore
    let general: GeneralSettingsStore
    let appearance: AppearanceSettingsStore
    let loginItem: LoginItemManager
    let actions: OnboardingActions
}

struct HistoryUIContext {
    let store: HistoryViewStateStore
    let actions: PanelActions
    var keyBindings: KeyBindingsStore? = nil
    var popoverCoordinator: CardPopoverCoordinator? = nil
}

enum HistoryUIPresentation { case history, pinnedList }
enum AppWindowRole { case history, pinned, preview, split, backgroundVeil }

struct SplitUIContent {
    let view: NSView
    let preferredSize: NSSize
}

/// Each factory owns a complete rendering tree; contexts carry existing services.
@MainActor
protocol AppUIFactory: AnyObject {
    func makeSettingsWindow(context: SettingsUIContext, initialPage: SettingsPage) -> AppWindowHandle
    func makeOnboardingWindow(context: OnboardingUIContext) -> AppWindowHandle
    func makeHistoryContent(context: HistoryUIContext, presentation: HistoryUIPresentation) -> NSView
    func makePreviewContent(context: HistoryUIContext) -> NSView
    func makeSplitContent(context: HistoryUIContext, dismiss: @escaping () -> Void) -> SplitUIContent?
    func makeStatusMessage(for text: String, typography: InterfaceTypography) -> NSMenuItem
    func makeBackgroundContent() -> NSView
    func backgroundFrame(for panelFrame: CGRect) -> CGRect
    func panelLayout(
        screen: PanelLayout.Screen, cardSide: CGFloat, tagScale: Double, typography: InterfaceTypography,
        showsSensitiveCopies: Bool
    ) -> PanelLayout
    func pinnedFrame(pointer: CGPoint, visibleFrame: CGRect) -> CGRect
    func configure(window: NSWindow, for role: AppWindowRole)
}

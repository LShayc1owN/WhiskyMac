// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

/// Paste-style panel pinned to the bottom of the main screen. Non-activating,
/// so the frontmost application keeps focus while the user picks an item.
@MainActor
final class PanelController {
    struct Sizing: Equatable {
        var cardSide: CGFloat
        var tagScale: Double
    }
    private var sizingBeforePreview: Sizing?
    var isSizePreview: Bool { sizingBeforePreview != nil }
    var sizePreviewEnded: () -> Void = {}
    private var panel: FloatingPanel
    private let historyPanel: FloatingPanel
    private let pinsPanel: FloatingPanel
    var activeWindow: NSPanel { panel }
    private(set) var showingPinned = false
    private var pinnedStyle: PinnedWindowStyle?
    private let stateStore: HistoryViewStateStore
    private let actions: PanelActions
    private let keyBindings: KeyBindingsStore
    private var pasteTarget: NSRunningApplication?
    private var previewPanel: NSPanel?
    private let popoverCoordinator = CardPopoverCoordinator()
    private var splitPanel: SplitDialogPanel?
    /// Where the panel and its preview go on the screen they rose on.
    private var layout: PanelLayout?

    private let uiFactory: any AppUIFactory
    private let backgroundVeil: BackgroundVeilController

    var appearanceMode: AppearanceMode {
        didSet {
            guard oldValue != appearanceMode else { return }
            applyWindowAppearance()
        }
    }

    private func applyWindowAppearance() {
        for window in [historyPanel, pinsPanel, previewPanel, splitPanel].compactMap({ $0 }) {
            window.appearance = appearanceMode.nsAppearance
        }
        backgroundVeil.appearanceMode = appearanceMode
    }

    private let vimMode: () -> Bool
    private let vimBindings: VimBindingsStore

    init(
        uiFactory: any AppUIFactory,
        stateStore: HistoryViewStateStore, actions: PanelActions, keyBindings: KeyBindingsStore,
        vimBindings: VimBindingsStore, appearanceMode: AppearanceMode = .system, vimMode: @escaping () -> Bool
    ) {
        self.uiFactory = uiFactory
        self.backgroundVeil = BackgroundVeilController(uiFactory: uiFactory)
        self.stateStore = stateStore
        self.actions = actions
        self.keyBindings = keyBindings
        self.vimBindings = vimBindings
        self.appearanceMode = appearanceMode
        self.vimMode = vimMode
        popoverCoordinator.presentationChanged = { [weak stateStore] in stateStore?.cardMenuOpen = $0 }
        historyPanel = FloatingPanel()
        pinsPanel = FloatingPanel()
        uiFactory.configure(window: historyPanel, for: .history)
        uiFactory.configure(window: pinsPanel, for: .pinned)
        panel = historyPanel
        applyWindowAppearance()
        panel.keyHandler = { [weak self] event in
            guard let self else { return false }
            return self.popoverCoordinator.handleKey(event) || self.router.handle(event)
        }
        stateStore.hidePreview = { [weak self] in self?.hidePreview() }
        stateStore.showPreview = { [weak self] in self?.showPreview() }
        stateStore.auxiliaryDidChange = { [weak self] in self?.updateSplitPanel() }
        // The panel also closes behind the controller's back — Esc and
        // resignKey order it out directly — and the preview must never
        // outlive it.
        panel.onClose = { [weak self] in
            self?.popoverCoordinator.dismiss()
            self?.restoreSizingPreview()
            self?.stateStore.endEditing()
            self?.hidePreview()
            self?.backgroundVeil.hide()
            self?.stateStore.panelDidClose()
            self?.panel.discardContent()
        }
        // In vim navigation Esc walks back one mode — SEARCH to NORMAL —
        // before it may close anything, and abandons the query on the way
        // out, exactly like Esc during a / search.
        panel.onCancel = { [weak self] in
            guard let self else { return false }
            if self.stateStore.pendingAction != nil {
                self.stateStore.pendingAction = nil
                self.hidePreview()
                return true
            }
            if self.stateStore.editing != nil {
                self.stateStore.endEditing()
                return true
            }
            guard self.stateStore.vimEnabled, self.stateStore.searchActive else { return false }
            self.actions.search("")
            self.stateStore.setSearchActive(false)
            return true
        }
        // Hover-selection listens to this: only real pointer movement may
        // steal the keyboard selection (see MouseActivity).
        panel.acceptsMouseMovedEvents = true
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { event in
            // Local monitors are called on the main thread.
            MainActor.assumeIsolated { MouseActivity.lastMove = Date() }
            return event
        }
        screenObserver = MainRunLoop.observe(NSApplication.didChangeScreenParametersNotification) { [weak self] _ in
            self?.screensDidChange()
        }
        accessibilityObserver = MainRunLoop.observe(
            NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, in: NSWorkspace.shared.notificationCenter
        ) { [weak self] _ in
            self?.accessibilityDidChange()
        }
        let session = stateStore.sensitiveSession
        sensitiveVisibilityObserver = session.$ids.combineLatest(session.$isProtected)
            .map { !$0.isEmpty && !$1 }
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, !showingPinned else { return }
                cardSizeDidChange()
            }
        pinsPanel.keyHandler = panel.keyHandler
        pinsPanel.onClose = panel.onClose
        pinsPanel.onCancel = panel.onCancel
        pinsPanel.acceptsMouseMovedEvents = true
        historyPanel.keepsOpenOnResignKey = { [weak stateStore] in
            stateStore?.historyHidingOptionsOpen == true || stateStore?.cardMenuOpen == true
                || stateStore?.pinMetadataEditing == true
        }
        pinsPanel.keepsOpenOnResignKey = historyPanel.keepsOpenOnResignKey

    }

    isolated deinit {
        popoverCoordinator.dismiss()
        for window in [historyPanel, pinsPanel] {
            window.onClose = nil
            window.onCancel = nil
            window.keyHandler = nil
            window.discardContent()
            window.close()
        }
        previewPanel?.close()
        splitPanel?.close()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        ghostFadeTimer?.invalidate()
        dragEndWatcher?.invalidate()
        backgroundVeil.dispose()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        if let accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
        }
    }

    private var mouseMonitor: Any?
    private var sensitiveVisibilityObserver: AnyCancellable?
    private var screenObserver: NSObjectProtocol?
    private var accessibilityObserver: NSObjectProtocol?

    /// A display unplugged or rescaled under an open panel: the windows
    /// follow the screen the panel now sits on — macOS moves it onto a
    /// remaining one — or the pointer's when it sits on none.
    private func screensDidChange() {
        guard panel.isVisible else { return }
        let screens = NSScreen.screens
        let underPointer = Self.screenIndex(under: NSEvent.mouseLocation, frames: screens.map(\.frame))
        guard let screen = panel.screen ?? underPointer.map({ screens[$0] }) else { return }
        place(on: screen)
    }

    private func accessibilityDidChange() {
        backgroundVeil.accessibilityDidChange()
        guard panel.isVisible, dragEndWatcher == nil, backgroundVeil.window == nil else { return }
        backgroundVeil.show(frame: panel.frame, belowWindowNumber: panel.windowNumber)
    }

    /// Every key press the panel receives goes through the router; the
    /// two things a key may do to windows come back as closures.
    private lazy var router = PanelKeyRouter(
        stateStore: stateStore,
        actions: actions,
        keyBindings: keyBindings,
        vimBindings: vimBindings,
        togglePreview: { [weak self] in self?.togglePreview() },
        closePanel: { [weak self] in self?.hide() }
    )

    func toggle() {
        if panel.isVisible, !showingPinned { hide() } else { show() }
    }

    func togglePinned(presentation: PinnedPresentation, style: PinnedWindowStyle) {
        if panel.isVisible, showingPinned { hide(); return }
        display(pins: true, style: presentation == .separate ? style : nil)
    }

    /// The screen the panel rises on: the one under the pointer, else the
    /// first — the primary display — when the pointer sits on no screen.
    nonisolated static func screenIndex(under point: CGPoint, frames: [CGRect]) -> Int? {
        guard !frames.isEmpty else { return nil }
        return frames.firstIndex { $0.contains(point) } ?? 0
    }

    func show() { display(pins: false, style: nil) }

    func previewSize(cardSide: Double, tagScale: Double) {
        display(
            pins: false, style: nil,
            sizingPreview: Sizing(
                cardSide: CGFloat(GeneralSettingsStore.boundedCardSide(cardSide)),
                tagScale: GeneralSettingsStore.boundedFilterTagScale(tagScale)))
    }

    func prepareSizingPreview(_ sizing: Sizing, on screen: NSScreen) {
        preparePresentation(pins: false, style: nil)
        sizingBeforePreview = Sizing(cardSide: stateStore.cardSide, tagScale: stateStore.filterTagScale)
        stateStore.configureCards(side: sizing.cardSide)
        stateStore.configureFilterTags(scale: sizing.tagScale)
        place(on: screen)
    }

    func cancelSizePreview() {
        guard isSizePreview else { return }
        hide()
        restoreSizingPreview()
    }

    private func restoreSizingPreview() {
        guard let sizingBeforePreview else { return }
        self.sizingBeforePreview = nil
        stateStore.configureCards(side: sizingBeforePreview.cardSide)
        stateStore.configureFilterTags(scale: sizingBeforePreview.tagScale)
        sizePreviewEnded()
    }

    /// Prepares the surface without activation. Kept separate from show so
    /// routing and window reuse can be validated without stealing focus.
    func preparePresentation(pins: Bool, style: PinnedWindowStyle?, on screen: NSScreen? = nil) {
        hide()
        restoreSizingPreview()
        showingPinned = pins
        pinnedStyle = style
        panel = pins && style != nil ? pinsPanel : historyPanel
        stateStore.isPinnedWorkspace = pins
        stateStore.isPinnedList = pins && style == .mouseList
        actions.panelWillShow()
        if pins { actions.preparePinned(style != nil) }
        stateStore.configureInput(vim: vimMode(), searchKey: vimBindings.key(for: .search))
        if let screen {
            resetDragGhost()
            place(on: screen)
        }
        installContent()
    }

    private func display(pins: Bool, style: PinnedWindowStyle?, sizingPreview: Sizing? = nil) {
        let screens = NSScreen.screens
        guard let index = Self.screenIndex(under: NSEvent.mouseLocation, frames: screens.map(\.frame)) else { return }
        if let sizingPreview {
            prepareSizingPreview(sizingPreview, on: screens[index])
        } else {
            preparePresentation(pins: pins, style: style, on: screens[index])
        }
        pasteTarget = nil
        if let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != AppIdentity.bundleIdentifier {
            pasteTarget = app
        }
        stateStore.requestSearchFocus()
        // Ordering the window may draw synchronously. Let that draw use prepared previews.
        stateStore.setPanelVisible(true)
        panel.makeKeyAndOrderFront(nil)
        if !panel.isVisible { stateStore.setPanelVisible(false) }
        stateStore.sensitiveSession.setPanelVisible(panel.isVisible)
        if panel.isVisible {
            backgroundVeil.show(frame: panel.frame, belowWindowNumber: panel.windowNumber)
        }
    }

    /// Lays the panel out on the screen, and the preview with it when
    /// one is up.
    private func place(on screen: NSScreen) {
        let layout = uiFactory.panelLayout(
            screen: PanelLayout.Screen(screen), cardSide: stateStore.cardSide, tagScale: stateStore.filterTagScale,
            typography: stateStore.interfaceTypography,
            showsSensitiveCopies: !showingPinned && !stateStore.sensitiveSession.isProtected
                && !stateStore.sensitiveSession.ids.isEmpty)
        self.layout = layout
        let frame =
            pinnedStyle == .mouseList
            ? uiFactory.pinnedFrame(pointer: NSEvent.mouseLocation, visibleFrame: screen.visibleFrame) : layout.panel
        panel.setFrame(frame, display: true)
        backgroundVeil.updateFrame(frame)
        if previewPanel?.isVisible == true {
            previewPanel?.setFrame(layout.preview, display: true)
        }
    }

    func cardSizeDidChange() {
        guard panel.isVisible, let screen = panel.screen ?? NSScreen.main else { return }
        place(on: screen)
    }

    /// Reduce Motion turns every fade into a cut.
    private static func fadeDuration(_ nominal: TimeInterval) -> TimeInterval {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : nominal
    }

    func hide() {
        panel.orderOut(nil)
    }

    private var ghostFadeTimer: Timer?
    private var dragEndWatcher: Timer?

    /// A drag needs the whole screen: the panel fades out and lets events
    /// through, so the item can land on whatever it was covering. The
    /// window itself must survive — ordering it out would kill the drag
    /// session it hosts — so it only closes for real once the button is
    /// released. Timers ride the .common run-loop modes because a drag
    /// session runs the tracking mode, where default-mode timers stall.
    func dragDidBegin() {
        guard panel.isVisible, dragEndWatcher == nil else { return }
        hidePreview()
        // One beat after session start, so the system has already
        // snapshotted the drag image from the still-opaque card.
        ghostFadeTimer = MainRunLoop.timer(interval: 0.03, repeats: false) { [weak self] in
            guard let self else { return }
            panel.ignoresMouseEvents = true
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeDuration(0.18)
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.panel.animator().alphaValue = 0
            }
            self.backgroundVeil.fadeForDrag()
        }
        // SwiftUI's onDrag never reports the session's end; the mouse
        // button is the signal — released means dropped or cancelled.
        dragEndWatcher = MainRunLoop.timer(interval: 0.08, repeats: true) { [weak self] in
            if NSEvent.pressedMouseButtons & 1 == 0 {
                self?.dragDidEnd()
            }
        }
    }

    /// Dropping consumes the selection like Return does: the panel closes
    /// rather than reappearing over the freshly dropped item.
    private func dragDidEnd() {
        panel.orderOut(nil)
        backgroundVeil.hide()
        resetDragGhost()
    }

    private func resetDragGhost() {
        ghostFadeTimer?.invalidate()
        ghostFadeTimer = nil
        dragEndWatcher?.invalidate()
        dragEndWatcher = nil
        panel.alphaValue = 1
        panel.ignoresMouseEvents = false
    }

    /// Quick-Look-style preview of the selected card, floating between
    /// the panel and the top of the screen.
    private func togglePreview() {
        stateStore.toggleExplicitPreview()
    }

    private func showPreview() {
        guard panel.isVisible, !stateStore.isProtected else { stateStore.closePreview(); return }
        stateStore.preparePreview()
        guard !stateStore.previewItems.isEmpty else { stateStore.closePreview(); return }
        if previewPanel == nil {
            let preview = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            preview.appearance = appearanceMode.nsAppearance
            uiFactory.configure(window: preview, for: .preview)
            preview.contentView = uiFactory.makePreviewContent(context: historyUIContext)
            previewPanel = preview
        }
        guard let preview = previewPanel, let layout else { return }
        preview.setFrame(layout.preview, display: true)
        preview.orderFront(nil)
        popoverCoordinator.previewWindow = preview
    }

    func pasteToPreviousApplication(explicitProtectedExport: Bool = false) {
        PasteSimulator.paste(
            to: pasteTarget,
            allowed: { [weak stateStore] in
                guard let stateStore else { return false }
                return explicitProtectedExport ? stateStore.isProtected : !stateStore.isProtected
            })
    }

    private func updateSplitPanel() {
        if !stateStore.hasAuxiliaryContent {
            if let splitPanel {
                panel.removeChildWindow(splitPanel); splitPanel.orderOut(nil); splitPanel.contentView = nil
            }
            splitPanel = nil
            if panel.isVisible { panel.makeKeyAndOrderFront(nil) }
            return
        }
        guard panel.isVisible, !stateStore.isProtected else { stateStore.closeSplitSessions(); return }
        let dialog = splitPanel ?? SplitDialogPanel()
        uiFactory.configure(window: dialog, for: .split)
        dialog.appearance = appearanceMode.nsAppearance
        splitPanel = dialog
        dialog.cancel = { [weak stateStore] in stateStore?.closeSplitSessions() }
        dialog.lostFocus = { [weak self] in self?.hide() }
        guard
            let content = uiFactory.makeSplitContent(
                context: historyUIContext, dismiss: { [weak stateStore] in stateStore?.closeSplitSessions() })
        else { return }
        dialog.contentView = content.view
        let typography = stateStore.interfaceTypography
        let preferred = content.preferredSize
        let screenSize = (panel.screen ?? NSScreen.main)?.visibleFrame.size ?? preferred
        dialog.setContentSize(
            NSSize(
                width: min(typography.room(preferred.width), screenSize.width),
                height: min(typography.room(preferred.height), screenSize.height)))
        if let screen = panel.screen {
            let frame = screen.visibleFrame
            let size = NSSize(
                width: min(dialog.frame.width, frame.width), height: min(dialog.frame.height, frame.height))
            dialog.setFrame(
                NSRect(
                    x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                    width: size.width, height: size.height), display: false)
        }
        panel.addChildWindow(dialog, ordered: .above)
        dialog.makeKeyAndOrderFront(nil)
    }

    private var historyUIContext: HistoryUIContext {
        HistoryUIContext(
            store: stateStore, actions: actions, keyBindings: keyBindings,
            popoverCoordinator: popoverCoordinator)
    }

    private func installContent() {
        let inactive = panel === historyPanel ? pinsPanel : historyPanel
        inactive.discardContent()
        panel.discardContent()
        panel.contentView = HistoryPanelHosting.make(
            uiFactory: uiFactory, store: stateStore, actions: actions,
            keyBindings: keyBindings, popoverCoordinator: popoverCoordinator,
            presentation: pinnedStyle == .mouseList ? .pinnedList : .history)
    }

    func appearanceDidChange() {
        popoverCoordinator.dismiss()
        hidePreview()
        if panel.isVisible { installContent() } else { panel.discardContent() }
    }
    func privacyDidChange(animated: Bool = false) {
        popoverCoordinator.dismiss()
        hidePreview()
        guard panel.isVisible else {
            panel.discardContent()
            return
        }

        let duration = animated && dragEndWatcher == nil ? Self.fadeDuration(0.20) : 0
        // Fade through the backdrop with a synchronous swap so the old cards
        // are never kept on screen during the privacy transition.
        if duration > 0 { panel.alphaValue = 0 }
        installContent()
        guard duration > 0 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 1
        }
    }

    private func hidePreview() {
        popoverCoordinator.previewWindow = nil
        previewPanel?.orderOut(nil)
        previewPanel?.contentView = nil
        previewPanel = nil
        stateStore.closePreview()
    }
}

extension PanelLayout.Screen {
    init(_ screen: NSScreen) {
        self.init(frame: screen.frame, visibleFrame: screen.visibleFrame, notchHeight: screen.safeAreaInsets.top)
    }
}

final class FloatingPanel: NSPanel {
    var keepsOpenOnResignKey: () -> Bool = { false }
    var keyHandler: ((NSEvent) -> Bool)?
    var onClose: (() -> Void)?
    /// Gets the first shot at Esc; returning true keeps the panel open.
    var onCancel: (() -> Bool)?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

    }

    override var canBecomeKey: Bool { true }

    // Intercepted ahead of the responder chain: the field editor would
    // otherwise swallow arrow keys for caret movement.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true {
            return
        }
        super.sendEvent(event)
    }

    func discardContent() {
        guard let content = contentView else { return }
        makeFirstResponder(nil)
        contentView = nil
        // A detached host normally dies with this event. Only a surviving
        // host needs an explicit empty layout to release its rendered cards.
        DispatchQueue.main.async { [weak content] in
            guard let content, content.window == nil else { return }
            (content as? HistoryContentOwner)?.discardHistoryContent()
        }
    }

    override func orderOut(_ sender: Any?) {
        // resignKey and cancelOperation both funnel here: only a window
        // that was actually visible notifies, once.
        let wasVisible = isVisible
        super.orderOut(sender)
        if wasVisible {
            onClose?()
        }
    }

    override func cancelOperation(_ sender: Any?) {
        if onCancel?() == true {
            return
        }
        orderOut(nil)
    }

    override func resignKey() {
        super.resignKey()
        if keepsOpenOnResignKey() { return }
        if childWindows?.contains(where: { $0 is SplitDialogPanel }) == true { return }
        orderOut(nil)
    }
}

private final class SplitDialogPanel: NSPanel {
    var cancel: (() -> Void)?
    var lostFocus: (() -> Void)?
    init() {
        super.init(
            contentRect: .zero, styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)

    }
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { cancel?() }
    override func performClose(_ sender: Any?) { cancel?() }
    override func resignKey() {
        super.resignKey()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible, !self.isKeyWindow, self.parent?.isKeyWindow != true else { return }
            self.lostFocus?()
        }
    }
}

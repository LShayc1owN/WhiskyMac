// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Paste-style panel pinned to the bottom of the main screen. Non-activating,
/// so the frontmost application keeps focus while the user picks an item.
final class PanelController {
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
    private var splitPanel: SplitDialogPanel?
    /// Where the panel and its preview go on the screen they rose on.
    private var layout: PanelLayout?

    private let backgroundVeil = BackgroundVeilController()

    private let vimMode: () -> Bool
    private let vimBindings: VimBindingsStore

    init(
        stateStore: HistoryViewStateStore, actions: PanelActions, keyBindings: KeyBindingsStore,
        vimBindings: VimBindingsStore, vimMode: @escaping () -> Bool
    ) {
        self.stateStore = stateStore
        self.actions = actions
        self.keyBindings = keyBindings
        self.vimBindings = vimBindings
        self.vimMode = vimMode
        historyPanel = FloatingPanel()
        pinsPanel = FloatingPanel()
        panel = historyPanel
        panel.contentView = HistoryPanelHosting.make(store: stateStore, actions: actions)
        panel.keyHandler = { [weak self] event in
            self?.router.handle(event) ?? false
        }
        stateStore.hidePreview = { [weak self] in self?.hidePreview() }
        stateStore.showPreview = { [weak self] in self?.showPreview() }
        stateStore.auxiliaryDidChange = { [weak self] in self?.updateSplitPanel() }
        // The panel also closes behind the controller's back — Esc and
        // resignKey order it out directly — and the preview must never
        // outlive it.
        panel.onClose = { [weak self] in
            self?.stateStore.endEditing()
            self?.hidePreview()
            self?.backgroundVeil.hide()
            self?.stateStore.panelDidClose()
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
        // AppKit posts this on the main thread; a nil queue keeps the
        // hop out and the windows move in the same turn.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.screensDidChange()
        }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.accessibilityDidChange()
        }
        pinsPanel.keyHandler = panel.keyHandler
        pinsPanel.onClose = panel.onClose
        pinsPanel.onCancel = panel.onCancel
        pinsPanel.acceptsMouseMovedEvents = true

    }

    deinit {
        for window in [historyPanel, pinsPanel] {
            window.onClose = nil
            window.onCancel = nil
            window.keyHandler = nil
            window.contentView = nil
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
    static func screenIndex(under point: CGPoint, frames: [CGRect]) -> Int? {
        guard !frames.isEmpty else { return nil }
        return frames.firstIndex { $0.contains(point) } ?? 0
    }

    func show() { display(pins: false, style: nil) }

    /// Prepares the surface without activation. Kept separate from show so
    /// routing and window reuse can be validated without stealing focus.
    func preparePresentation(pins: Bool, style: PinnedWindowStyle?) {
        hide()
        showingPinned = pins
        pinnedStyle = style
        panel = pins && style != nil ? pinsPanel : historyPanel
        stateStore.isPinnedWorkspace = pins
        stateStore.isPinnedList = pins && style == .mouseList
        actions.panelWillShow()
        if pins { actions.preparePinned(style != nil) }
        installContent()
    }

    private func display(pins: Bool, style: PinnedWindowStyle?) {
        preparePresentation(pins: pins, style: style)
        pasteTarget = nil
        if let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != AppIdentity.bundleIdentifier {
            pasteTarget = app
        }
        let screens = NSScreen.screens
        guard let index = Self.screenIndex(under: NSEvent.mouseLocation, frames: screens.map(\.frame)) else {
            return
        }
        let screen = screens[index]
        resetDragGhost()
        place(on: screen)
        stateStore.configureInput(vim: vimMode(), searchKey: vimBindings.key(for: .search))
        stateStore.requestSearchFocus()
        panel.makeKeyAndOrderFront(nil)
        stateStore.setPanelVisible(panel.isVisible)
        stateStore.sensitiveSession.setPanelVisible(panel.isVisible)
        if panel.isVisible {
            backgroundVeil.show(frame: panel.frame, belowWindowNumber: panel.windowNumber)
        }
    }

    /// Lays the panel out on the screen, and the preview with it when
    /// one is up.
    private func place(on screen: NSScreen) {
        let layout = PanelLayout(screen: PanelLayout.Screen(screen), cardSide: stateStore.cardSide)
        self.layout = layout
        let frame =
            pinnedStyle == .mouseList
            ? PinnedWindowLayout.frame(pointer: NSEvent.mouseLocation, visibleFrame: screen.visibleFrame) : layout.panel
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
        let fade = Timer(timeInterval: 0.03, repeats: false) { [weak self] _ in
            guard let self else { return }
            panel.ignoresMouseEvents = true
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeDuration(0.18)
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.panel.animator().alphaValue = 0
            }
            self.backgroundVeil.fadeForDrag()
        }
        ghostFadeTimer = fade
        RunLoop.main.add(fade, forMode: .common)
        // SwiftUI's onDrag never reports the session's end; the mouse
        // button is the signal — released means dropped or cancelled.
        let watcher = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            if NSEvent.pressedMouseButtons & 1 == 0 {
                self?.dragDidEnd()
            }
        }
        dragEndWatcher = watcher
        RunLoop.main.add(watcher, forMode: .common)
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
            preview.isFloatingPanel = true
            preview.level = .statusBar
            preview.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            preview.backgroundColor = .clear
            preview.isOpaque = false
            preview.hasShadow = false
            let hosting = NSHostingView(rootView: PreviewOverlayView(store: stateStore, actions: actions))
            // The window's frame is the one measure of the preview; the
            // view fills it rather than asking for a size of its own.
            hosting.sizingOptions = []
            preview.contentView = hosting
            previewPanel = preview
        }
        guard let preview = previewPanel, let layout else { return }
        preview.setFrame(layout.preview, display: true)
        preview.orderFront(nil)
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
        if stateStore.splitSession == nil && stateStore.splitGroupSession == nil && stateStore.splitVersions.isEmpty {
            if let splitPanel {
                panel.removeChildWindow(splitPanel); splitPanel.orderOut(nil); splitPanel.contentView = nil
            }
            splitPanel = nil
            if panel.isVisible { panel.makeKeyAndOrderFront(nil) }
            return
        }
        guard panel.isVisible, !stateStore.isProtected else { stateStore.closeSplitSessions(); return }
        let dialog = splitPanel ?? SplitDialogPanel()
        splitPanel = dialog
        dialog.cancel = { [weak stateStore] in stateStore?.closeSplitSessions() }
        dialog.lostFocus = { [weak self] in self?.hide() }
        if !stateStore.splitVersions.isEmpty {
            dialog.contentView = NSHostingView(rootView: SplitVersionView(store: stateStore))
            dialog.setContentSize(NSSize(width: 500, height: 380))
        } else if let session = stateStore.splitSession {
            dialog.contentView = NSHostingView(
                rootView: SplitContentView(session: session) { [weak stateStore] in stateStore?.closeSplitSessions() })
            dialog.setContentSize(NSSize(width: 660, height: 740))
        } else if let session = stateStore.splitGroupSession {
            dialog.contentView = NSHostingView(
                rootView: SplitGroupView(session: session) { [weak stateStore] in stateStore?.closeSplitSessions() })
            dialog.setContentSize(NSSize(width: 540, height: 540))
        }
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

    private func installContent() {
        if pinnedStyle == .mouseList {
            panel.contentView = NSHostingView(
                rootView: PinnedListView(store: stateStore, actions: actions, keyBindings: keyBindings))
        } else {
            panel.contentView = HistoryPanelHosting.make(store: stateStore, actions: actions, keyBindings: keyBindings)
        }
    }

    func appearanceDidChange() { hidePreview(); installContent() }
    func privacyDidChange() { hidePreview(); installContent() }

    private func hidePreview() {
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
        isFloatingPanel = true
        isReleasedWhenClosed = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
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
        title = localized("Split…")
        isReleasedWhenClosed = false
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
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

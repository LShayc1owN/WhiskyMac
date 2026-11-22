// WhiskyMac: modified or added 2026-11-19 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

/// One operation popover belongs to the active clipboard window at a time.
/// Keep the actual presented windows ordered, including when a preview is reused.
final class CardPopoverCoordinator {
    private(set) var presentationID: UUID?
    private(set) weak var menuWindow: NSWindow?
    private(set) weak var ownerWindow: NSWindow?
    private weak var keyboard: CardPopoverKeyboard?
    weak var previewWindow: NSWindow? { didSet { maintainOrder() } }
    var presentationChanged: (Bool) -> Void = { _ in }
    private var closePresentation: ((Bool) -> Void)?

    func begin(_ id: UUID, owner: NSWindow, keyboard: CardPopoverKeyboard, close: @escaping (Bool) -> Void) {
        if presentationID != id { dismiss() }
        presentationID = id
        ownerWindow = owner
        self.keyboard = keyboard
        closePresentation = close
        presentationChanged(true)
    }

    func didShow(_ window: NSWindow, id: UUID) {
        guard presentationID == id else { return }
        menuWindow = window
        window.appearance = ownerWindow?.appearance
        maintainOrder()
    }

    func maintainOrder() {
        guard let menuWindow, menuWindow.isVisible else { return }
        let highestContentLevel = max(
            ownerWindow?.level.rawValue ?? NSWindow.Level.statusBar.rawValue,
            previewWindow?.level.rawValue ?? NSWindow.Level.statusBar.rawValue)
        menuWindow.level = NSWindow.Level(rawValue: max(menuWindow.level.rawValue, highestContentLevel + 1))
        menuWindow.orderFront(nil)
    }

    func end(_ id: UUID) {
        guard presentationID == id else { return }
        presentationID = nil
        menuWindow = nil
        ownerWindow = nil
        keyboard = nil
        closePresentation = nil
        presentationChanged(false)
    }

    func dismiss(restoreFocus: Bool = false) { closePresentation?(restoreFocus) }

    func handleKey(_ event: NSEvent) -> Bool {
        guard presentationID != nil,
            event.modifierFlags.intersection([.command, .control, .option]).isEmpty
        else { return false }
        if keyboard?.handle(event.keyCode) == true { return true }
        if event.keyCode == 53 { dismiss(restoreFocus: true); return true }
        return false
    }

    func contains(_ window: NSWindow?) -> Bool {
        var candidate = window
        while let current = candidate {
            if current === ownerWindow || current === menuWindow || current === previewWindow { return true }
            candidate = current.parent
        }
        return false
    }
}

final class CardPopoverKeyboard {
    private var registration: UUID?
    private var handler: ((UInt16) -> Bool)?
    func install(_ id: UUID, handler: @escaping (UInt16) -> Bool) {
        registration = id
        self.handler = handler
    }
    func remove(_ id: UUID) {
        guard registration == id else { return }
        registration = nil
        handler = nil
    }
    func handle(_ keyCode: UInt16) -> Bool { handler?(keyCode) ?? false }
    func reset() { registration = nil; handler = nil }
}

extension EnvironmentValues {
    @Entry var cardPopoverCoordinator: CardPopoverCoordinator? = nil
    @Entry var cardPopoverKeyboard: CardPopoverKeyboard? = nil
}

extension View {
    func cardActionPopover<Content: View>(
        isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        background(CardActionPopover(isPresented: isPresented, content: content))
    }

    func cardActionPopover<Item: Identifiable, Content: View>(
        item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        cardActionPopover(
            isPresented: Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
        ) {
            if let value = item.wrappedValue { content(value) }
        }
    }
}

/// SwiftUI owns the content; AppKit owns positioning, focus, and the presentation lifecycle.
struct CardActionPopover<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    @ViewBuilder var content: () -> Content
    @Environment(\.self) private var environment

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AnchorView {
        let anchor = AnchorView()
        anchor.didMove = { [weak coordinator = context.coordinator] in coordinator?.scheduleUpdate() }
        return anchor
    }

    func updateNSView(_ anchor: AnchorView, context: Context) {
        let coordinator = context.coordinator
        coordinator.anchor = anchor
        coordinator.binding = $isPresented
        guard isPresented else {
            coordinator.content = nil
            coordinator.scheduleUpdate()
            return
        }
        coordinator.ordering = environment.cardPopoverCoordinator ?? coordinator.fallbackOrdering
        var contentEnvironment = environment
        contentEnvironment.cardPopoverCoordinator = coordinator.ordering
        contentEnvironment.cardPopoverKeyboard = coordinator.keyboard
        coordinator.content = AnyView(content().environment(\.self, contentEnvironment))
        coordinator.reduceMotion = environment.accessibilityReduceMotion
        coordinator.scheduleUpdate()
    }

    static func dismantleNSView(_ anchor: AnchorView, coordinator: Coordinator) {
        anchor.didMove = nil
        coordinator.isDismantled = true
        coordinator.close(restoreFocus: false)
        coordinator.anchor = nil
    }

    final class AnchorView: NSView {
        var didMove: (() -> Void)?
        private var lastSize = NSSize.zero
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); didMove?() }
        override func layout() {
            super.layout()
            guard bounds.size != lastSize else { return }
            lastSize = bounds.size
            didMove?()
        }
    }

    final class Coordinator: NSObject, NSPopoverDelegate {
        let id = UUID()
        private(set) var popover: NSPopover?
        lazy var fallbackOrdering = CardPopoverCoordinator()
        lazy var keyboard = CardPopoverKeyboard()
        var ordering: CardPopoverCoordinator?
        weak var anchor: NSView?
        var binding: Binding<Bool>?
        var content: AnyView?
        var reduceMotion = false
        var isDismantled = false
        private var hosting: NSHostingController<AnyView>?
        private var updateScheduled = false
        private var presenting = false
        private var restoreOwnerFocus = true
        private var localMonitor: Any?
        private var globalMonitor: Any?
        private var observers: [NSObjectProtocol] = []

        deinit {
            if let localMonitor { NSEvent.removeMonitor(localMonitor) }
            if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        func scheduleUpdate() {
            guard !isDismantled, !updateScheduled, presenting || binding?.wrappedValue == true else { return }
            updateScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.updateScheduled = false
                self.synchronize()
            }
        }

        func synchronize() {
            guard !isDismantled else { return }
            guard binding?.wrappedValue == true else { close(); return }
            guard let content, let anchor, let owner = anchor.window, owner.isVisible, !anchor.bounds.isEmpty else {
                return
            }
            let popover = self.popover ?? NSPopover()
            if self.popover == nil {
                popover.delegate = self
                popover.behavior = .applicationDefined
                self.popover = popover
            }
            let hosting = hosting ?? NSHostingController(rootView: content)
            self.hosting = hosting
            hosting.sizingOptions = [.preferredContentSize]
            hosting.rootView = AnyView(
                content.environment(\.cardPopoverKeyboard, keyboard)
                    .onExitCommand { [weak self] in self?.close() })
            popover.contentViewController = hosting
            popover.appearance = owner.appearance
            hosting.view.window?.appearance = owner.appearance
            hosting.view.layoutSubtreeIfNeeded()
            let size = hosting.view.fittingSize
            if size.width > 0, size.height > 0 { popover.contentSize = size }
            guard !presenting else { ordering?.maintainOrder(); return }
            presenting = true
            restoreOwnerFocus = true
            ordering?.begin(id, owner: owner, keyboard: keyboard) { [weak self] in self?.close(restoreFocus: $0) }
            popover.animates = !reduceMotion
            installMonitors(owner: owner)
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
            if let window = hosting.view.window { ordering?.didShow(window, id: id) }
        }

        func popoverDidShow(_ notification: Notification) {
            guard let shown = notification.object as? NSPopover, shown === popover,
                let window = hosting?.view.window
            else { return }
            ordering?.didShow(window, id: id)
        }

        func close(restoreFocus: Bool = true) {
            guard presenting, let popover else { return }
            restoreOwnerFocus = restoreFocus
            // Release the preview freeze before the selected command runs.
            popover.animates = false
            if popover.isShown { popover.close() }
            if self.popover === popover { finishClose() }
        }

        func popoverDidClose(_ notification: Notification) {
            guard let closed = notification.object as? NSPopover, closed === popover else { return }
            finishClose()
        }

        private func finishClose() {
            guard presenting else { return }
            presenting = false
            let owner = ordering?.ownerWindow
            let ownsPresentation = ordering?.presentationID == id
            removeMonitors()
            keyboard.reset()
            ordering?.end(id)
            if binding?.wrappedValue == true { binding?.wrappedValue = false }
            hosting = nil
            popover?.contentViewController = nil
            popover = nil
            content = nil
            if ownsPresentation, restoreOwnerFocus, owner?.isVisible == true { owner?.makeKey() }
        }

        private func installMonitors(owner: NSWindow) {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) {
                [weak self] event in
                guard let self, self.presenting else { return event }
                if event.type == .keyDown {
                    if event.window === self.hosting?.view.window, self.ordering?.handleKey(event) == true {
                        return nil
                    }
                    return event
                }
                var window = event.window
                while let current = window {
                    if current === self.hosting?.view.window { return event }
                    window = current.parent
                }
                self.outsideInteraction(in: event.window)
                return event
            }
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
                [weak self] _ in self?.outsideInteraction(in: nil)
            }
            observers = [
                NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification, object: owner, queue: .main
                ) { [weak self] _ in self?.close(restoreFocus: false) },
                NotificationCenter.default.addObserver(
                    forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
                ) { [weak self] _ in self?.outsideInteraction(in: nil) },
            ]
        }

        func outsideInteraction(in window: NSWindow?) {
            guard presenting else { return }
            let owner = ordering?.ownerWindow
            let withinClipboard = ordering?.contains(window) == true
            close(restoreFocus: withinClipboard)
            if !withinClipboard { owner?.orderOut(nil) }
        }

        private func removeMonitors() {
            if let localMonitor { NSEvent.removeMonitor(localMonitor) }
            if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
            localMonitor = nil
            globalMonitor = nil
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
        }
    }
}

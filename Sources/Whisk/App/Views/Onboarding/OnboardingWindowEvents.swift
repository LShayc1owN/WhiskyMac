// WhiskyMac: modified or added 2026-11-18 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

enum OnboardingWindowConfiguration {
    static func apply(to window: NSWindow) {
        window.styleMask.remove([.resizable, .miniaturizable])
        window.styleMask.insert(.fullSizeContentView)
        window.title = localized("Welcome Guide")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = OnboardingStyle.paperColor
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
    }
}

struct OnboardingWindowEvents: NSViewRepresentable {
    var onInactive: () -> Void

    func makeNSView(context: Context) -> ObserverView { ObserverView() }
    func updateNSView(_ view: ObserverView, context: Context) { view.onInactive = onInactive }

    final class ObserverView: NSView {
        var onInactive: (() -> Void)?
        private var observers: [NSObjectProtocol] = []
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
                observers.append(
                    NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) {
                        [weak self] _ in self?.onInactive?()
                    })
            }
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}

/// The recorder gets first refusal; normal text inputs retain their own editing keys.
enum OnboardingPracticeShortcutRouter {
    static func action(for event: NSEvent, bindings: KeyBindingsStore, active: Bool, editingText: Bool) -> CardAction? {
        guard active, !editingText, bindings.recordingAction == nil else { return nil }
        if bindings.binding(for: .pasteSelection).matches(event) { return .paste }
        if bindings.binding(for: .copySelection).matches(event) { return .copy }
        return nil
    }
}

struct OnboardingPracticeKeyMonitor: NSViewRepresentable {
    var active: Bool
    let bindings: KeyBindingsStore
    var perform: (CardAction) -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView() }
    func updateNSView(_ view: MonitorView, context: Context) {
        view.handle = { event, editing in
            guard
                let action = OnboardingPracticeShortcutRouter.action(
                    for: event, bindings: bindings, active: active, editingText: editing)
            else { return false }
            perform(action)
            return true
        }
    }

    final class MonitorView: NSView {
        var handle: ((NSEvent, Bool) -> Bool)?
        private var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window, window.isKeyWindow else {
                    return event
                }
                let editing = (window.firstResponder as? NSTextView)?.isEditable == true
                return self.handle?(event, editing) == true ? nil : event
            }
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

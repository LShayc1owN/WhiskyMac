// WhiskyMac: modified or added 2026-11-18 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

@available(macOS 26, *)
enum MacOS26OnboardingWindowConfiguration {
    static func apply(to window: NSWindow) {
        window.styleMask.remove([.resizable, .miniaturizable])
        window.styleMask.insert(.fullSizeContentView)
        window.title = localized("Welcome Guide")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = MacOS26OnboardingStyle.paperColor
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
    }
}

@available(macOS 26, *)
struct MacOS26OnboardingWindowEvents: NSViewRepresentable {
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

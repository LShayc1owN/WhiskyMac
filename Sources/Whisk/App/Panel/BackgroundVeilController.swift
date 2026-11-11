// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

/// Main-thread ownership of the background, including interrupted fades.
final class BackgroundVeilController {
    typealias AlphaAnimation = (NSPanel, CGFloat, TimeInterval, @escaping () -> Void) -> Void

    private enum Phase { case visible, dragging, transparent, closing }
    private var phase = Phase.visible
    private var generation = 0
    private(set) var window: NSPanel?
    private let makeWindow: () -> NSPanel
    private let orderBelow: (NSPanel, Int) -> Void
    private let animateAlpha: AlphaAnimation
    private let reduceTransparency: () -> Bool
    private let reduceMotion: () -> Bool

    init(
        makeWindow: @escaping () -> NSPanel = BackgroundVeilController.makeWindow,
        orderBelow: @escaping (NSPanel, Int) -> Void = { $0.order(.below, relativeTo: $1) },
        animateAlpha: @escaping AlphaAnimation = { window, alpha, duration, complete in
            NSAnimationContext.runAnimationGroup(
                { context in
                    context.duration = duration
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    window.animator().alphaValue = alpha
                }, completionHandler: complete)
        },
        reduceTransparency: @escaping () -> Bool = {
            NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        },
        reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    ) {
        self.makeWindow = makeWindow
        self.orderBelow = orderBelow
        self.animateAlpha = animateAlpha
        self.reduceTransparency = reduceTransparency
        self.reduceMotion = reduceMotion
    }

    deinit { dispose() }

    func show(frame: NSRect, belowWindowNumber number: Int) {
        guard !reduceTransparency() else { dispose(); return }
        generation += 1
        phase = .visible
        let window = self.window ?? makeWindow()
        self.window = window
        window.setFrame(frame, display: true)
        window.alphaValue = 0
        orderBelow(window, number)
        animate(window, to: 1, duration: 0.22, complete: {})
    }

    func updateFrame(_ frame: NSRect) {
        window?.setFrame(frame, display: true)
    }

    func hide() {
        guard let window, phase != .closing else { return }
        guard !reduceMotion(), phase != .transparent else { dispose(); return }
        generation += 1
        let token = generation
        phase = .closing
        animate(window, to: 0, duration: 0.22) { [weak self, weak window] in
            guard let self, let window, self.generation == token, self.window === window else { return }
            self.dispose()
        }
    }

    func fadeForDrag() {
        guard let window, phase == .visible else { return }
        generation += 1
        let token = generation
        phase = .dragging
        animate(window, to: 0, duration: 0.18) { [weak self, weak window] in
            guard let self, let window, self.generation == token, self.window === window else { return }
            // alphaValue is the target immediately; only completion means
            // it is safe to skip a later close fade.
            self.phase = .transparent
        }
    }

    func accessibilityDidChange() {
        if reduceTransparency() { dispose(); return }
        guard let window, reduceMotion() else { return }
        generation += 1
        switch phase {
        case .closing: dispose()
        case .dragging, .transparent:
            window.alphaValue = 0
            phase = .transparent
        case .visible: window.alphaValue = 1
        }
    }

    func dispose() {
        generation += 1
        phase = .visible
        guard let window else { return }
        self.window = nil
        window.orderOut(nil)
        window.contentView = nil
        window.close()
    }

    private func animate(_ window: NSPanel, to alpha: CGFloat, duration: TimeInterval, complete: @escaping () -> Void) {
        if reduceMotion() {
            window.alphaValue = alpha
            complete()
        } else {
            animateAlpha(window, alpha, duration, complete)
        }
    }

    static func makeWindow() -> NSPanel {
        let window = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isFloatingPanel = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.contentView = NSHostingView(rootView: GradientBlurVeil())
        return window
    }
}

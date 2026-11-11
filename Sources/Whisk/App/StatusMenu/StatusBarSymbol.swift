// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Symbols

final class StatusBarSymbol {
    static let pointSize: CGFloat = 17

    let imageView: NSImageView = ClickThroughSymbolView()
    private(set) var wigglesForward = false

    func install(on button: NSButton) {
        // NSStatusBarButton has no symbol-effect API; keep its click handling
        // and draw the symbol in a non-interactive image view above it.
        button.image = nil
        imageView.frame = button.bounds
        imageView.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleProportionallyDown
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: Self.pointSize, weight: .regular)
        imageView.setAccessibilityElement(false)
        button.addSubview(imageView)
    }

    func wiggle(reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) {
        wigglesForward.toggle()
        imageView.removeAllSymbolEffects(animated: false)
        guard !reduceMotion else { return }
        let effect: WiggleSymbolEffect = wigglesForward ? .wiggle.byLayer.forward : .wiggle.byLayer.backward
        imageView.addSymbolEffect(effect, options: .nonRepeating)
    }
}

private final class ClickThroughSymbolView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

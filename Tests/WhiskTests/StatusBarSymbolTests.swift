// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Testing

@testable import Whisk

@Suite @MainActor struct StatusBarSymbolTests {
    @Test func symbol_overlay_preserves_the_buttons_click_target_and_resizes_with_it() throws {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        let symbol = StatusBarSymbol()
        symbol.install(on: button)
        symbol.imageView.image = AppSymbol.image()
        #expect(button.hitTest(NSPoint(x: 12, y: 12)) === button)
        button.setFrameSize(NSSize(width: 30, height: 28))
        #expect(symbol.imageView.frame == button.bounds)
        #expect(symbol.imageView.image != nil)
    }

    @Test func repeated_click_feedback_preserves_the_current_status_image() throws {
        let symbol = StatusBarSymbol()
        let image = try #require(NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil))
        symbol.imageView.image = image
        symbol.wiggle(reduceMotion: false)
        symbol.wiggle(reduceMotion: false)
        symbol.wiggle(reduceMotion: true)
        #expect(symbol.imageView.image === image)
    }
}

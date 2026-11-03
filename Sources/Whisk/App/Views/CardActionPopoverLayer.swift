// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

/// SwiftUI presents the actions in a separate window, so a view zIndex cannot
/// keep them above the status-bar-level preview when that preview is reordered.
struct CardActionPopoverLayer: NSViewRepresentable {
    func makeNSView(context: Context) -> LayerView { LayerView() }

    func updateNSView(_ view: LayerView, context: Context) {
        view.updateWindowLevel()
    }

    final class LayerView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateWindowLevel()
        }

        func updateWindowLevel() {
            guard let window else { return }
            let minimum = NSWindow.Level.statusBar.rawValue + 1
            if window.level.rawValue < minimum {
                window.level = NSWindow.Level(rawValue: minimum)
            }
        }
    }
}

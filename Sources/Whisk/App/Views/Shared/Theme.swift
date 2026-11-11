// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

extension View {
    /// The pointing hand over anything that acts on click. PointerStyle
    /// arrived in macOS 15; earlier systems keep the arrow.
    @ViewBuilder func linkPointer() -> some View {
        if #available(macOS 15, *) {
            pointerStyle(.link)
        } else {
            self
        }
    }

    /// The open hand over anything that can be picked up and dragged.
    @ViewBuilder func grabPointer() -> some View {
        if #available(macOS 15, *) {
            pointerStyle(.grabIdle)
        } else {
            self
        }
    }
}

extension NSColor {
    static var matcha: NSColor { AppAccent.color }
}

extension Color {
    static var matcha: Color { Color(nsColor: NSColor.matcha) }
}

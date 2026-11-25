// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

enum MacOS15PinnedWindowLayout {
    static func frame(pointer: CGPoint, visibleFrame: CGRect) -> CGRect {
        let width = min(400, visibleFrame.width)
        let height = min(560, visibleFrame.height)
        return CGRect(
            x: min(max(pointer.x, visibleFrame.minX), visibleFrame.maxX - width),
            y: min(max(pointer.y - height, visibleFrame.minY), visibleFrame.maxY - height),
            width: width, height: height)
    }
}

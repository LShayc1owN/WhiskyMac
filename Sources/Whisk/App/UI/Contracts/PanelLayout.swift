// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

struct PanelLayout: Equatable {
    struct Screen: Equatable {
        var frame: CGRect
        var visibleFrame: CGRect
        var notchHeight: CGFloat
    }
    let panel: CGRect
    let preview: CGRect
}

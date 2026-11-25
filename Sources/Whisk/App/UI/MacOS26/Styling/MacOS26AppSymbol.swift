// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

@available(macOS 26, *)
struct MacOS26AppSymbolView: View {
    var pointSize: CGFloat = 20

    var body: some View {
        if let image = AppSymbol.image(named: AppSymbol.brandName, pointSize: pointSize) {
            Image(nsImage: image)
                .renderingMode(.template)
                .accessibilityLabel(AppIdentity.displayName)
        }
    }
}

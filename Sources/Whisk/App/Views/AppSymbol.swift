// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

enum AppSymbol {
    // CoreUI needs a bundle identifier, which SwiftPM's resource bundle lacks.
    static let bundle: Bundle? = AppResources.bundle.url(forResource: "WhiskyMacSymbols", withExtension: "bundle")
        .flatMap(Bundle.init(url:))

    static func image(pointSize: CGFloat = 15) -> NSImage? {
        let image =
            bundle.flatMap { NSImage(symbolName: "WhiskyMac", bundle: $0, variableValue: 0) }
            ?? NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: AppIdentity.displayName)
        let configured = image?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular, scale: .medium))
        configured?.isTemplate = true
        configured?.accessibilityDescription = AppIdentity.displayName
        return configured
    }
}

struct AppSymbolView: View {
    var pointSize: CGFloat = 20

    var body: some View {
        if let image = AppSymbol.image(pointSize: pointSize) {
            Image(nsImage: image)
                .renderingMode(.template)
                .accessibilityLabel(AppIdentity.displayName)
        }
    }
}

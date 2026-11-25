// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI

enum MacOS15SourceAppPalette {
    static func cardTint(_ source: SourceAppStyle.Resolved, dark: Bool) -> Color {
        tint(source.baseColor, dark: dark).opacity(dark ? 0.38 : 0.13)
    }

    static func filterTint(_ source: SourceAppStyle.Resolved, dark: Bool) -> Color {
        tint(source.baseColor, dark: dark).opacity(dark ? 0.42 : 0.17)
    }

    private static func tint(_ color: NSColor, dark: Bool) -> Color {
        let base = color.usingColorSpace(.sRGB) ?? color
        return Color(
            nsColor: NSColor(
                hue: base.hueComponent,
                saturation: min(1, base.saturationComponent * (dark ? 1 : 0.65)),
                brightness: min(1, base.brightnessComponent * (dark ? 0.6 : 0.95)),
                alpha: 1))
    }
}

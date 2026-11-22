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

    /// Retain the accent hue while keeping small text legible on pale surfaces.
    func readableAccent(in scheme: ColorScheme) -> NSColor {
        guard scheme == .light, let rgb = usingColorSpace(.sRGB) else { return self }
        let red = Self.linearComponent(rgb.redComponent)
        let green = Self.linearComponent(rgb.greenComponent)
        let blue = Self.linearComponent(rgb.blueComponent)
        let luminance = red * 0.2126 + green * 0.7152 + blue * 0.0722
        // This also allows for the accent wash behind selected rows and chips.
        let maximumLuminance = 0.105
        guard luminance > maximumLuminance else { return rgb }
        let scale = maximumLuminance / luminance
        return NSColor(
            srgbRed: Self.encodedComponent(red * scale), green: Self.encodedComponent(green * scale),
            blue: Self.encodedComponent(blue * scale), alpha: rgb.alphaComponent)
    }

    private static func linearComponent(_ value: CGFloat) -> CGFloat {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    private static func encodedComponent(_ value: CGFloat) -> CGFloat {
        value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055
    }
}

extension Color {
    static var matcha: Color { Color(nsColor: NSColor.matcha) }

    static func readableAccent(in scheme: ColorScheme, color: NSColor = .matcha) -> Color {
        Color(nsColor: color.readableAccent(in: scheme))
    }
}

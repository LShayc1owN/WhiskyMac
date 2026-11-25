// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

@available(macOS 26, *)
extension View {
    /// The pointing hand over anything that acts on click. PointerStyle
    /// arrived in macOS 15; earlier systems keep the arrow.
    @ViewBuilder func macOS26LinkPointer() -> some View {
        pointerStyle(.link)

    }

    /// The open hand over anything that can be picked up and dragged.
    @ViewBuilder func macOS26GrabPointer() -> some View {
        pointerStyle(.grabIdle)

    }
}

@available(macOS 26, *)
extension NSColor {
    static var macOS26Matcha: NSColor { AppAccent.color }

    /// Retain the accent hue while keeping small text legible on pale surfaces.
    func macOS26ReadableAccent(in scheme: ColorScheme) -> NSColor {
        guard scheme == .light, let rgb = usingColorSpace(.sRGB) else { return self }
        let red = Self.macOS26LinearComponent(rgb.redComponent)
        let green = Self.macOS26LinearComponent(rgb.greenComponent)
        let blue = Self.macOS26LinearComponent(rgb.blueComponent)
        let luminance = red * 0.2126 + green * 0.7152 + blue * 0.0722
        // This also allows for the accent wash behind selected rows and chips.
        let maximumLuminance = 0.105
        guard luminance > maximumLuminance else { return rgb }
        let scale = maximumLuminance / luminance
        return NSColor(
            srgbRed: Self.macOS26EncodedComponent(red * scale), green: Self.macOS26EncodedComponent(green * scale),
            blue: Self.macOS26EncodedComponent(blue * scale), alpha: rgb.alphaComponent)
    }

    private static func macOS26LinearComponent(_ value: CGFloat) -> CGFloat {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    private static func macOS26EncodedComponent(_ value: CGFloat) -> CGFloat {
        value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055
    }
}

@available(macOS 26, *)
extension Color {
    static var macOS26Matcha: Color { Color(nsColor: NSColor.macOS26Matcha) }

    static func macOS26ReadableAccent(in scheme: ColorScheme, color: NSColor = .macOS26Matcha) -> Color {
        Color(nsColor: color.macOS26ReadableAccent(in: scheme))
    }
}

// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

extension View {
    /// The pointing hand over anything that acts on click. PointerStyle
    /// arrived in macOS 15; earlier systems keep the arrow.
    @ViewBuilder func macOS15LinkPointer() -> some View {
        pointerStyle(.link)

    }

    /// The open hand over anything that can be picked up and dragged.
    @ViewBuilder func macOS15GrabPointer() -> some View {
        pointerStyle(.grabIdle)

    }
}

extension NSColor {
    static var macOS15Matcha: NSColor { AppAccent.color }

    /// Retain the accent hue while keeping small text legible on pale surfaces.
    func macOS15ReadableAccent(in scheme: ColorScheme) -> NSColor {
        guard scheme == .light, let rgb = usingColorSpace(.sRGB) else { return self }
        let red = Self.macOS15LinearComponent(rgb.redComponent)
        let green = Self.macOS15LinearComponent(rgb.greenComponent)
        let blue = Self.macOS15LinearComponent(rgb.blueComponent)
        let luminance = red * 0.2126 + green * 0.7152 + blue * 0.0722
        // This also allows for the accent wash behind selected rows and chips.
        let maximumLuminance = 0.105
        guard luminance > maximumLuminance else { return rgb }
        let scale = maximumLuminance / luminance
        return NSColor(
            srgbRed: Self.macOS15EncodedComponent(red * scale), green: Self.macOS15EncodedComponent(green * scale),
            blue: Self.macOS15EncodedComponent(blue * scale), alpha: rgb.alphaComponent)
    }

    private static func macOS15LinearComponent(_ value: CGFloat) -> CGFloat {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    private static func macOS15EncodedComponent(_ value: CGFloat) -> CGFloat {
        value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055
    }
}

extension Color {
    static var macOS15Matcha: Color { Color(nsColor: NSColor.macOS15Matcha) }

    static func macOS15ReadableAccent(in scheme: ColorScheme, color: NSColor = .macOS15Matcha) -> Color {
        Color(nsColor: color.macOS15ReadableAccent(in: scheme))
    }
}

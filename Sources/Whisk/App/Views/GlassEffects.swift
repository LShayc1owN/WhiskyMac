// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

/// The panel's surfaces — cards, chips, search — are frosted glass over
/// whatever sits behind the WINDOW: SwiftUI materials only blur in-window
/// content (nothing, in a transparent panel), so the blur comes from an
/// NSVisualEffectView blending behind the window. Backdrop layers do not
/// survive SwiftUI masks or opacity groups — the system silently drops
/// the blur — so the rounding happens on the effect view's own layer.
/// A nil corner radius means capsule (half the height).
extension View {
    func liquidGlass(
        in shape: some Shape, cornerRadius: CGFloat? = nil, tint: Color? = nil
    ) -> some View {
        modifier(
            LiquidGlassModifier(shape: AnyShape(shape), cornerRadius: cornerRadius, tint: tint)
        )
    }
}

private struct LiquidGlassModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: AnyShape
    let cornerRadius: CGFloat?
    let tint: Color?

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    if reduceTransparency {
                        // Nothing to see through: a solid window background
                        // under the same tint keeps the surface legible.
                        shape.fill(Color(nsColor: .windowBackgroundColor))
                    } else {
                        BehindWindowBlur(cornerRadius: cornerRadius)
                    }
                    shape.fill(
                        tint
                            ?? (scheme == .dark
                                ? Color.black.opacity(0.25) : Color.white.opacity(0.3))
                    )
                }
            }
            // A plain hairline in the theme's inverse color keeps dark
            // surfaces legible on dark backdrops and light on light.
            .overlay(
                shape.stroke(
                    scheme == .dark ? Color.white.opacity(0.28) : Color.black.opacity(0.28),
                    lineWidth: 0.5
                ).clipShape(shape)
            )
    }
}

/// Blurs the content behind the window itself — other applications, the
/// desktop — which in-window SwiftUI materials cannot reach.
private struct BehindWindowBlur: NSViewRepresentable {
    let cornerRadius: CGFloat?

    func makeNSView(context: Context) -> BackdropView {
        let view = BackdropView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .hudWindow
        view.wantsLayer = true
        view.cornerRadius = cornerRadius
        return view
    }

    func updateNSView(_ view: BackdropView, context: Context) {
        view.cornerRadius = cornerRadius
    }
}

final class BackdropView: NSVisualEffectView {
    var cornerRadius: CGFloat? {
        didSet { needsLayout = true }
    }

    private var maskKey = ""

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0 else { return }
        let radius = cornerRadius ?? bounds.height / 2
        let key = "\(bounds.size)-\(radius)"
        guard key != maskKey else { return }
        maskKey = key
        let mask = NSImage(size: bounds.size)
        mask.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(
            roundedRect: NSRect(origin: .zero, size: bounds.size),
            xRadius: radius,
            yRadius: radius
        ).fill()
        mask.unlockFocus()
        maskImage = mask
    }
}

/// A system material with an app-owned gradient mask.
struct GradientBlurVeil: NSViewRepresentable {
    func makeNSView(context: Context) -> GradientVeilView {
        let view = GradientVeilView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .hudWindow
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: GradientVeilView, context: Context) {}
}

final class GradientVeilView: NSVisualEffectView {
    static let plateauAlpha: CGFloat = 1
    static let rampEnd: CGFloat = 0.25
    private var maskKey = ""

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0 else { return }
        let key = "\(bounds.size)"
        guard key != maskKey else { return }
        maskKey = key
        let mask = NSImage(size: bounds.size)
        mask.lockFocus()
        // Unflipped image coordinates: location 0 is the bottom edge.
        NSGradient(
            colorsAndLocations: (NSColor.white.withAlphaComponent(Self.plateauAlpha), 0),
            (NSColor.white.withAlphaComponent(Self.plateauAlpha), 1 - Self.rampEnd),
            (NSColor.white.withAlphaComponent(0), 1)
        )?.draw(in: NSRect(origin: .zero, size: bounds.size), angle: 90)
        mask.unlockFocus()
        maskImage = mask
    }
}

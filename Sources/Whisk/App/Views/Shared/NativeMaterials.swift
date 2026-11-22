// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

/// Let the native blur show through a pale surface even over dark desktop content.
struct ClipboardMaterialSurface<Surface: InsettableShape>: View {
    let shape: Surface
    var cornerRadius: CGFloat? = nil
    var material: NSVisualEffectView.Material = .hudWindow
    var tint: Color = .clear
    var castsCompactShadowInDarkMode = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        NativeMaterialBackground(material: material, cornerRadius: cornerRadius)
            .overlay {
                if scheme == .light {
                    shape.fill(.white.opacity(cornerRadius == nil ? 0.62 : 0.72))
                }
                shape.fill(tint)
                if scheme == .light, cornerRadius != nil {
                    shape.strokeBorder(.primary.opacity(contrast == .increased ? 0.24 : 0.11), lineWidth: 0.5)
                }
            }
            .background {
                if cornerRadius == nil, scheme == .light || castsCompactShadowInDarkMode {
                    Color.clear.clipboardShadow(in: shape, compact: true)
                }
            }
            .allowsHitTesting(false)
    }
}

/// Native behind-window material for the transparent clipboard panel.
/// AppKit handles appearance, contrast, and Reduce Transparency. The mask
/// rounds the native backdrop without flattening it into a SwiftUI layer.
/// A nil corner radius uses half the view's height for a capsule.
struct NativeMaterialBackground: NSViewRepresentable {
    @Environment(\.colorScheme) private var scheme
    var material: NSVisualEffectView.Material = .hudWindow
    var cornerRadius: CGFloat? = nil

    func makeNSView(context: Context) -> BackdropView {
        let view = BackdropView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = material
        view.wantsLayer = true
        view.cornerRadius = cornerRadius
        view.appearance = scheme == .dark ? AppearanceMode.dark.nsAppearance : AppearanceMode.light.nsAppearance
        return view
    }

    func updateNSView(_ view: BackdropView, context: Context) {
        view.cornerRadius = cornerRadius
        if view.material != material { view.material = material }
        let name: NSAppearance.Name = scheme == .dark ? .darkAqua : .aqua
        if view.appearance?.name != name { view.appearance = NSAppearance(named: name) }
    }
}

final class BackdropView: NSVisualEffectView {
    var cornerRadius: CGFloat? {
        didSet { if oldValue != cornerRadius { needsLayout = true } }
    }

    private var maskRadius: CGFloat?
    private var maskScale: CGFloat?
    private static weak var lastRoundedMask: NSImage?
    private static var lastRoundedScale: CGFloat?

    override func layout() {
        super.layout()
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else { return }
        let requestedRadius = cornerRadius.map { $0.isFinite ? max(0, $0) : 0 } ?? .greatestFiniteMagnitude
        let radius = min(requestedRadius, min(bounds.width, bounds.height) / 2)
        let scale = window?.backingScaleFactor
        guard maskImage == nil || maskRadius != radius || maskScale != scale else { return }
        maskRadius = radius
        maskScale = scale
        // Adjacent cards share an immutable template for as long as a view owns it.
        if cornerRadius != nil, Self.lastRoundedScale == scale, let mask = Self.lastRoundedMask,
            mask.capInsets.top == radius
        {
            maskImage = mask
            return
        }
        // Keep raster coordinates, logical size, and cap insets in agreement.
        // Resizing an existing image's logical size stretches its end caps.
        // Width-only changes reuse this small mask; height changes redraw it.
        maskImage = Self.makeMask(radius: radius)
        if cornerRadius != nil {
            Self.lastRoundedMask = maskImage
            Self.lastRoundedScale = scale
        }
    }

    private static func makeMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let mask = NSImage(size: NSSize(width: side, height: side))
        mask.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(
            roundedRect: NSRect(origin: .zero, size: mask.size),
            xRadius: radius,
            yRadius: radius
        ).fill()
        mask.unlockFocus()
        mask.resizingMode = .stretch
        mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        return mask
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
    override func layout() {
        super.layout()
        let height = bounds.height
        guard bounds.width > 0, height.isFinite, height > 0, maskImage?.size.height != height else { return }
        // Each row has uniform alpha. AppKit stretches the strip across the
        // window while the vertical gradient retains its native resolution.
        let mask = NSImage(size: NSSize(width: 3, height: height))
        mask.lockFocus()
        // Unflipped image coordinates: location 0 is the bottom edge.
        NSGradient(
            colorsAndLocations: (NSColor.white.withAlphaComponent(Self.plateauAlpha), 0),
            (NSColor.white.withAlphaComponent(Self.plateauAlpha), 1 - Self.rampEnd),
            (NSColor.white.withAlphaComponent(0), 1)
        )?.draw(in: NSRect(origin: .zero, size: mask.size), angle: 90)
        mask.unlockFocus()
        mask.resizingMode = .stretch
        // NSVisualEffectView needs nonzero cap insets to stretch the central column.
        mask.capInsets = NSEdgeInsets(top: 0, left: 1, bottom: 0, right: 1)
        maskImage = mask
    }
}

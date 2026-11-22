import AppKit
import SwiftUI

/// Per-application visual identity — icon and dominant tint — resolved from
/// a bundle identifier through NSWorkspace, so it stays in the frameworks
/// ring. A cache hit is immediate; misses load off the UI thread.
@MainActor
enum SourceAppStyle {
    struct Resolved {
        let icon: NSImage?
        let tint: Color
        let darkSurfaceColor: Color
        let lightSurfaceColor: Color

        /// The frosted-surface wash: the app color leaning darker on the
        /// dark theme, lighter and softer on the light one, translucent so
        /// the behind-window blur still reads through.
        func surfaceTint(dark: Bool) -> Color {
            dark ? darkSurfaceColor.opacity(0.38) : lightSurfaceColor.opacity(0.13)
        }

        func filterTint(dark: Bool) -> Color {
            dark ? darkSurfaceColor.opacity(0.42) : lightSurfaceColor.opacity(0.17)
        }
    }

    private static let cache = SourceAppStyleCache()
    static let limit = SourceAppStyleCache.maximumCount
    static var cachedCount: Int { cache.cachedCount }
    static var pendingCount: Int { cache.pendingCount }
    static var cachedBytes: Int { cache.cachedBytes }

    static func resolve(bundleID: String?) -> Resolved { cache.resolve(bundleID: bundleID) }
    static func releaseCache() { cache.releaseCache() }

    static let fallback = resolved(icon: nil, base: .systemGray)
    // Keep the icon slot's size stable until the background lookup finishes.
    static let pending = resolved(icon: NSImage(size: NSSize(width: 32, height: 32)), base: .systemGray)

    static func resolved(icon: NSImage?, base: NSColor) -> Resolved {
        Resolved(
            icon: icon,
            tint: Color(nsColor: base),
            darkSurfaceColor: Color(nsColor: shifted(base, saturation: 1, brightness: 0.6)),
            lightSurfaceColor: Color(nsColor: shifted(base, saturation: 0.65, brightness: 0.95))
        )
    }

    private static func shifted(_ color: NSColor, saturation: CGFloat, brightness: CGFloat) -> NSColor {
        let base = color.usingColorSpace(.sRGB) ?? color
        return NSColor(
            hue: base.hueComponent,
            saturation: min(1, base.saturationComponent * saturation),
            brightness: min(1, base.brightnessComponent * brightness),
            alpha: 1
        )
    }

}

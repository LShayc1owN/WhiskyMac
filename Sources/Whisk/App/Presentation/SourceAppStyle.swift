import AppKit
import SwiftUI

/// Per-application visual identity — icon and dominant tint — resolved from
/// a bundle identifier through NSWorkspace, so it stays in the frameworks
/// ring. A cache hit is immediate; misses load off the UI thread.
@MainActor
enum SourceAppStyle {
    struct Resolved {
        let icon: NSImage?
        let baseColor: NSColor
        var tint: Color { Color(nsColor: baseColor) }
    }

    private static let cache = SourceAppStyleCache()
    static let limit = SourceAppStyleCache.maximumCount

    static func resolve(bundleID: String?) -> Resolved { cache.resolve(bundleID: bundleID) }
    static func releaseCache() { cache.releaseCache() }

    static let fallback = resolved(icon: nil, base: .systemGray)
    // Keep the icon slot's size stable until the background lookup finishes.
    static let pending = resolved(icon: NSImage(size: NSSize(width: 32, height: 32)), base: .systemGray)

    static func resolved(icon: NSImage?, base: NSColor) -> Resolved {
        Resolved(icon: icon, baseColor: base)
    }
}

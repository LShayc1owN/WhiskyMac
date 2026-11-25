// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import CoreGraphics

struct FilterChipViewport: Equatable, Sendable {
    enum Region: Sendable { case unknown, preload, retain, outside }
    let region: Region
    let isVisible: Bool

    static let unknown = FilterChipViewport(region: .unknown, isVisible: false)

    static func measure(frame: CGRect, viewportWidth: CGFloat) -> FilterChipViewport {
        guard viewportWidth.isFinite, viewportWidth > 0, !frame.isNull,
            frame.minX.isFinite, frame.maxX.isFinite, frame.width > 0
        else { return .unknown }
        // Include the largest selection zoom without changing layout bounds.
        let bounds = frame.insetBy(dx: -frame.width * 0.03, dy: 0)
        func intersects(_ margin: CGFloat) -> Bool {
            bounds.maxX > -margin && bounds.minX < viewportWidth + margin
        }
        return FilterChipViewport(
            region: intersects(160) ? .preload : (intersects(240) ? .retain : .outside),
            isVisible: intersects(0))
    }

    func keepsGlass(previouslyMounted: Bool) -> Bool {
        switch region {
        case .preload: true
        case .retain: previouslyMounted
        case .unknown, .outside: false
        }
    }
}

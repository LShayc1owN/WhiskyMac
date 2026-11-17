// WhiskyMac: modified or added 2026-11-17 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Combine
import Foundation

/// Only the filter bar observes this scope; pixel scrolling does not rebuild the panel.
final class FilterAppScope: ObservableObject {
    @Published private(set) var visibleSourceKeys: Set<String>?
    @Published var isExpanded = false

    init(visibleSourceKeys: Set<String>? = nil) {
        self.visibleSourceKeys = visibleSourceKeys
    }

    func update(_ keys: Set<String>) {
        guard visibleSourceKeys != keys else { return }
        visibleSourceKeys = keys
    }

    static func apps(_ apps: [FilterChip], visibleKeys: Set<String>?, expanded: Bool) -> [FilterChip] {
        guard !expanded, let visibleKeys else { return apps }
        return apps.filter { visibleKeys.contains($0.id) || $0.isActive || $0.isFocused }
    }

    /// The actual viewport, excluding preload slots and an offscreen keyboard selection.
    static func visibleRange(count: Int, side: CGFloat, stride: CGFloat, start: CGFloat, width: CGFloat) -> Range<Int> {
        guard count > 0, side > 0, stride > 0, width > 0,
            side.isFinite, stride.isFinite, start.isFinite, width.isFinite
        else { return 0..<0 }
        let lower = min(CGFloat(count), max(0, floor((start - side) / stride) + 1))
        let upper = min(CGFloat(count), max(lower, ceil((start + width) / stride)))
        return Int(lower)..<Int(upper)
    }
}

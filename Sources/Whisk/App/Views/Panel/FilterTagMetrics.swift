// WhiskyMac: modified or added 2026-11-18 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

struct FilterTagMetrics {
    static let baseScale: CGFloat = 1.2
    static let originalRowHeight: CGFloat = 34
    let scale: CGFloat

    init(scale: Double) {
        self.scale = Self.baseScale * CGFloat(GeneralSettingsStore.boundedFilterTagScale(scale))
    }

    var fontSize: CGFloat { NSFont.preferredFont(forTextStyle: .callout, options: [:]).pointSize * scale }
    var smallFontSize: CGFloat { NSFont.preferredFont(forTextStyle: .caption2, options: [:]).pointSize * scale }
    var horizontalPadding: CGFloat { 12 * scale }
    var verticalPadding: CGFloat { 6 * scale }
    var rowHeight: CGFloat { Self.originalRowHeight * scale }
    var rowVerticalPadding: CGFloat { 3 * scale }
    var totalRowHeight: CGFloat { rowHeight + 2 * rowVerticalPadding }
}

extension EnvironmentValues {
    @Entry var filterTagScale: Double = GeneralSettingsStore.defaultFilterTagScale
}

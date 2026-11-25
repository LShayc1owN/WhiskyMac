// WhiskyMac: modified or added 2026-11-18 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

struct MacOS15FilterTagMetrics {
    static let baseScale: CGFloat = 1.2
    static let originalRowHeight: CGFloat = 34
    let scale: CGFloat
    let typography: InterfaceTypography

    init(scale: Double, typography: InterfaceTypography = .standard) {
        self.typography = typography
        self.scale = Self.baseScale * CGFloat(GeneralSettingsStore.boundedFilterTagScale(scale))
    }

    var fontSize: CGFloat { NSFont.preferredFont(forTextStyle: .callout, options: [:]).pointSize * scale }
    var smallFontSize: CGFloat { NSFont.preferredFont(forTextStyle: .caption2, options: [:]).pointSize * scale }
    var horizontalPadding: CGFloat { 12 * scale }
    var verticalPadding: CGFloat { 6 * scale }
    var rowHeight: CGFloat {
        let baseline = Self.originalRowHeight * scale
        guard typography.percent > 100 else { return baseline }
        let labelHeight = typography.lineHeight(fontSize)
        return max(baseline, labelHeight + 2 * verticalPadding)
    }
    var rowVerticalPadding: CGFloat { 3 * scale }
    var totalRowHeight: CGFloat { rowHeight + 2 * rowVerticalPadding }
}

extension EnvironmentValues {
    @Entry var macOS15FilterTagScale: Double = GeneralSettingsStore.defaultFilterTagScale
}

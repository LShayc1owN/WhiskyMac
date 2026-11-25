// WhiskyMac: added 2026-11-25 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

struct InterfaceTypography: Equatable {
    static let percentRange = 85...300
    static let standard = InterfaceTypography(percent: 100)
    let percent: Int
    var appliesToPlainText: Bool

    init(percent: Int, appliesToPlainText: Bool = true) {
        self.appliesToPlainText = appliesToPlainText
        self.percent = min(max(percent, Self.percentRange.lowerBound), Self.percentRange.upperBound)
    }

    var scale: CGFloat { CGFloat(percent) / 100 }
    var isStandard: Bool { percent == Self.standard.percent }
    var plainText: InterfaceTypography { appliesToPlainText ? self : .standard }
    var usesLargeLayout: Bool { percent > 150 }

    func points(_ original: CGFloat) -> CGFloat { original * scale }

    /// Fixed controls need extra room when text grows. Keep their original
    /// hit area when text shrinks.
    func room(_ original: CGFloat) -> CGFloat { original * max(scale, 1) }

    func lineHeight(_ size: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: points(size))
        return ceil(font.ascender - font.descender + font.leading)
    }

    func font(size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> Font {
        .system(size: points(size), weight: weight, design: design)
    }

    func font(_ style: Font.TextStyle, design: Font.Design? = nil) -> Font {
        if isStandard { return .system(style, design: design) }
        let nativeStyle: NSFont.TextStyle
        switch style {
        case .largeTitle: nativeStyle = .largeTitle
        case .title: nativeStyle = .title1
        case .title2: nativeStyle = .title2
        case .title3: nativeStyle = .title3
        case .headline: nativeStyle = .headline
        case .subheadline: nativeStyle = .subheadline
        case .callout: nativeStyle = .callout
        case .footnote: nativeStyle = .footnote
        case .caption: nativeStyle = .caption1
        case .caption2: nativeStyle = .caption2
        default: nativeStyle = .body
        }
        let size = NSFont.preferredFont(forTextStyle: nativeStyle, options: [:]).pointSize
        return font(size: size, weight: style == .headline ? .semibold : nil, design: design)
    }

    var menuFont: NSFont { NSFont.menuFont(ofSize: points(NSFont.menuFont(ofSize: 0).pointSize)) }
}

extension EnvironmentValues {
    @Entry var interfaceTypography = InterfaceTypography.standard
}

extension View {
    func interfaceType(_ typography: InterfaceTypography) -> some View {
        environment(\.interfaceTypography, typography)
            .font(typography.isStandard ? nil : typography.font(.body))
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

@available(macOS 26, *)
enum MacOS26CardSurface {
    static let outline = RoundedRectangle(cornerRadius: 24, style: .continuous)

    static func fill(in scheme: ColorScheme) -> Color {
        Color(white: scheme == .dark ? 0.15 : 0.98)
    }

    static func border(in contrast: ColorSchemeContrast) -> Color {
        .primary.opacity(contrast == .increased ? 0.40 : 0.13)
    }
}

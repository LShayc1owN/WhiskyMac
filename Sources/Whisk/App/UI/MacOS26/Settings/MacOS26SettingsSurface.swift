// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

@available(macOS 26, *)
enum MacOS26SettingsSurface {
    static let searchPanelRadius: CGFloat = 26

    static func rounded(minimum: CGFloat) -> ConcentricRectangle {
        ConcentricRectangle(corners: .concentric(minimum: .fixed(minimum)), isUniform: true)
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Keep keyboard- and mouse-initiated menus anchored to the same control.
@MainActor
final class SettingsMenuPresenter {
    weak var anchor: NSView?

    static func menu(_ options: some View, typography: InterfaceTypography) -> NSMenu {
        let menu = NSHostingMenu(rootView: options)
        menu.font = typography.menuFont
        return menu
    }

    func present(_ options: some View, typography: InterfaceTypography) {
        guard let anchor, anchor.window != nil else { return }
        let menu = Self.menu(options, typography: typography)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.minY - 2), in: anchor)
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

@available(macOS 26, *)
struct MacOS26SettingsSidebar<Sidebar: View, Detail: View>: View {
    @Binding var preferredWidth: CGFloat
    let minimumWidth: CGFloat
    let sidebar: Sidebar
    let detail: Detail

    private var maximumWidth: CGFloat { AppearanceSettingsStore.sidebarWidthRange.upperBound }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebar
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.width.rounded()
                } action: { width in
                    // Ignore intermediate widths when the split view first mounts or changes window bounds.
                    guard NSEvent.pressedMouseButtons & 1 != 0,
                        width >= minimumWidth, width <= maximumWidth, width != preferredWidth
                    else { return }
                    preferredWidth = width
                }
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(
                    min: minimumWidth, ideal: max(minimumWidth, preferredWidth), max: maximumWidth)
        } detail: {
            detail
        }
    }
}

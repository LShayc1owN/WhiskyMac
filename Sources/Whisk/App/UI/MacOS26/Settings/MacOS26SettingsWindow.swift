// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

@available(macOS 26, *)
@MainActor
enum MacOS26SettingsWindow {
    static func make<Content: View>(rootView: Content) -> NSWindow {
        let hosting = NSHostingController(rootView: rootView.background { MacOS26SettingsWindowBackground() })
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.styleMask.remove([.resizable, .miniaturizable])
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .windowBackgroundColor
        return window
    }
}

@available(macOS 26, *)
private struct MacOS26SettingsWindowBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                WindowMaterial()
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private struct WindowMaterial: NSViewRepresentable {
        func makeNSView(context: Context) -> NSVisualEffectView {
            let view = NSVisualEffectView()
            view.material = .windowBackground
            view.blendingMode = .behindWindow
            view.state = .followsWindowActiveState
            return view
        }

        func updateNSView(_ view: NSVisualEffectView, context: Context) {}
    }
}

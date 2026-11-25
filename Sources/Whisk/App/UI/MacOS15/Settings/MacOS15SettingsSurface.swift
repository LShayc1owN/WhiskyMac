// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

enum MacOS15SettingsSurface {
    static let groupCornerRadius: CGFloat = 14
    static let controlCornerRadius: CGFloat = 8

}

extension View {
    func macOS15SettingsSurface(in shape: some InsettableShape) -> some View {
        modifier(MacOS15SettingsSurfaceModifier(shape: shape))
    }

}

private struct MacOS15SettingsSurfaceModifier<Surface: InsettableShape>: ViewModifier {
    @SettingsAccessibility private var accessibility
    @Environment(\.colorScheme) private var scheme
    let shape: Surface

    func body(content: Content) -> some View {
        content
            .background {
                if accessibility.reduceTransparency {
                    shape.fill(Color(nsColor: .controlBackgroundColor))
                } else {
                    shape.fill(.regularMaterial)
                        .overlay {
                            if scheme == .light { shape.fill(.white.opacity(0.78)) }
                        }
                }
            }
            .overlay {
                if scheme == .light {
                    shape.strokeBorder(.primary.opacity(accessibility.increasedContrast ? 0.26 : 0.10), lineWidth: 0.5)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}

struct MacOS15SettingsWindowBackdrop: View {
    @SettingsAccessibility private var accessibility

    var body: some View {
        if accessibility.reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else {
            MacOS15SettingsBackdropView()
        }
    }
}

private struct MacOS15SettingsBackdropView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

enum MacOS15SettingsWindowConfiguration {
    static func apply(to window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
    }
}

struct MacOS15SettingsHoverButtonStyle: ButtonStyle {
    @SettingsAccessibility private var accessibility
    @State private var isHovering = false
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Color.primary.opacity(isHovering && !isSelected ? 0.065 : 0),
                in: RoundedRectangle(cornerRadius: MacOS15SettingsSurface.controlCornerRadius, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && !accessibility.reduceMotion ? 0.98 : 1)
            .animation(accessibility.reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
            .animation(accessibility.reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .onHover { isHovering = $0 }
    }
}

extension View {
    /// AppKit's bordered button is single-line. Use the wrapping action style when the title needs more room.
    func macOS15SettingsAction(prominent: Bool = false) -> some View {
        ViewThatFits(in: .horizontal) {
            if prominent {
                self.buttonStyle(.borderedProminent).fixedSize()
            } else {
                self.buttonStyle(.bordered).fixedSize()
            }
            self.buttonStyle(MacOS15DialogActionStyle(prominent: prominent))
        }
    }
}

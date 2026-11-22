// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

enum SettingsSurface {
    static let groupCornerRadius: CGFloat = 14
    static let controlCornerRadius: CGFloat = 8

}

extension View {
    func settingsSurface(in shape: some InsettableShape) -> some View {
        modifier(SettingsSurfaceModifier(shape: shape))
    }

}

private struct SettingsSurfaceModifier<Surface: InsettableShape>: ViewModifier {
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

struct SettingsWindowBackdrop: View {
    @SettingsAccessibility private var accessibility

    var body: some View {
        if accessibility.reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else {
            SettingsBackdropView()
        }
    }
}

private struct SettingsBackdropView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

enum SettingsWindowConfiguration {
    static func apply(to window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
    }
}

struct SettingsHoverButtonStyle: ButtonStyle {
    @SettingsAccessibility private var accessibility
    @State private var isHovering = false
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Color.primary.opacity(isHovering && !isSelected ? 0.065 : 0),
                in: RoundedRectangle(cornerRadius: SettingsSurface.controlCornerRadius, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && !accessibility.reduceMotion ? 0.98 : 1)
            .animation(accessibility.reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
            .animation(accessibility.reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .onHover { isHovering = $0 }
    }
}

struct SettingsAccessibilityValues {
    var reduceMotion = false
    var reduceTransparency = false
    var increasedContrast = false
}

private struct SettingsAccessibilityOverrideKey: EnvironmentKey {
    static let defaultValue: SettingsAccessibilityValues? = nil
}

extension EnvironmentValues {
    var settingsAccessibilityOverride: SettingsAccessibilityValues? {
        get { self[SettingsAccessibilityOverrideKey.self] }
        set { self[SettingsAccessibilityOverrideKey.self] = newValue }
    }
}

@propertyWrapper
struct SettingsAccessibility: DynamicProperty {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.settingsAccessibilityOverride) private var override

    var wrappedValue: SettingsAccessibilityValues {
        override
            ?? SettingsAccessibilityValues(
                reduceMotion: reduceMotion, reduceTransparency: reduceTransparency,
                increasedContrast: contrast == .increased)
    }
}

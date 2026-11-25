// WhiskyMac: modified or added 2026-11-18 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

// Semantic surfaces keep the illustrated guide legible in both system appearances.
@available(macOS 26, *)
enum MacOS26OnboardingStyle {
    static let green = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.48, green: 0.77, blue: 0.67, alpha: 1)
                : NSColor(srgbRed: 0.20, green: 0.46, blue: 0.38, alpha: 1)
        })
    static let orange = Color(nsColor: .systemOrange)
    static let paperColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.12, green: 0.135, blue: 0.13, alpha: 1)
            : NSColor(srgbRed: 0.97, green: 0.975, blue: 0.96, alpha: 1)
    }
    static let paper = Color(nsColor: paperColor)
    static let card = Color(nsColor: .controlBackgroundColor)
}

@available(macOS 26, *)
enum MacOS26OnboardingMotion {
    static let page = Animation.easeOut(duration: 0.24)
    static let cover = Animation.easeOut(duration: 0.32)
    static let detail = Animation.smooth(duration: 0.22)
    static let press = Animation.easeOut(duration: 0.13)
    static let stepDistance: CGFloat = 14

    static func enter(x: CGFloat = 0, y: CGFloat = 0) -> AnyTransition {
        // Replace the outgoing interactive view immediately, including its key handlers.
        .asymmetric(insertion: .offset(x: x, y: y).combined(with: .opacity), removal: .identity)
    }
}

@available(macOS 26, *)
struct MacOS26OnboardingSurface<Content: View>: View {
    var cornerRadius: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MacOS26OnboardingStyle.card, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

@available(macOS 26, *)
struct MacOS26OnboardingFrostedSurface: View {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        Group {
            if reduceTransparency {
                shape.fill(MacOS26OnboardingStyle.card)
            } else {
                shape.fill(.regularMaterial)
            }
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.14 : 0.06), radius: 10, y: 3)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

@available(macOS 26, *)
struct MacOS26OnboardingDisclosure<Content: View>: View {
    @Environment(\.interfaceTypography) private var typography
    let title: String
    @ViewBuilder var content: Content
    @State private var expanded = false

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            content
        } label: {
            Text(title)
                .font(typography.font(size: 14, weight: .medium))
        }
        .disclosureGroupStyle(MacOS26DisclosureRowStyle(animation: MacOS26OnboardingMotion.detail))
    }
}

@available(macOS 26, *)
struct MacOS26OnboardingKeycap: View {
    let text: String
    var recording = false
    @Environment(\.interfaceTypography) private var typography

    var body: some View {
        Text(text)
            .font(typography.font(size: 13, weight: .medium, design: .monospaced))
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.opacity)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(
                recording ? MacOS26OnboardingStyle.green.opacity(0.12) : Color.primary.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(recording ? MacOS26OnboardingStyle.green.opacity(0.55) : Color.primary.opacity(0.12))
            }
            .animation(MacOS26OnboardingMotion.detail, value: recording)
            .animation(MacOS26OnboardingMotion.detail, value: text)
    }
}

@available(macOS 26, *)
struct MacOS26OnboardingButtonStyle: ButtonStyle {
    enum Treatment { case primary, secondary, quiet }

    let treatment: Treatment

    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, treatment: treatment)
    }

    private struct Face: View {
        let configuration: ButtonStyleConfiguration
        let treatment: Treatment
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.interfaceTypography) private var typography
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        private var showsHover: Bool { isEnabled && isHovered }
        private var isScaledDown: Bool {
            isEnabled && configuration.isPressed && treatment != .quiet && !reduceMotion
        }

        var body: some View {
            face
                .contentShape(Rectangle())
                .overlay {
                    if treatment != .quiet {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(outline, lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                }
                .opacity(isEnabled ? 1 : 0.56)
                .scaleEffect(isScaledDown ? 0.98 : 1)
                .onHover { isHovered = $0 }
                .animation(reduceMotion ? nil : MacOS26OnboardingMotion.press, value: showsHover)
                .animation(reduceMotion ? nil : MacOS26OnboardingMotion.press, value: isScaledDown)
                .animation(reduceMotion ? nil : MacOS26OnboardingMotion.press, value: isEnabled)
        }

        @ViewBuilder private var face: some View {
            switch treatment {
            case .primary:
                configuration.label
                    .font(typography.font(size: 15, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .frame(minHeight: 42)
                    .foregroundStyle(.white)
                    .background {
                        let shape = RoundedRectangle(cornerRadius: cornerRadius)
                        shape.fill(Color(red: 0.19, green: 0.43, blue: 0.36).gradient)
                            .overlay {
                                shape.fill(.white.opacity(hoverAmount))
                            }
                    }
            case .secondary:
                configuration.label
                    .font(typography.font(size: 14, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(minHeight: 36)
                    .background {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(MacOS26OnboardingStyle.green.opacity(0.045 + hoverAmount))
                    }
            case .quiet:
                configuration.label
                    .background {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(MacOS26OnboardingStyle.green.opacity(hoverAmount))
                            .padding(.horizontal, -4)
                            .padding(.vertical, -2)
                    }
            }
        }

        private var cornerRadius: CGFloat { treatment == .primary ? 10 : 7 }

        private var hoverAmount: Double { showsHover ? 0.08 : 0 }

        private var outline: Color {
            if treatment == .primary {
                return .white.opacity(showsHover ? 0.26 : 0.10)
            }
            return MacOS26OnboardingStyle.green.opacity(showsHover ? 0.36 : 0.19)
        }
    }
}

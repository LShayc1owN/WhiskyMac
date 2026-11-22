// WhiskyMac: modified or added 2026-11-18 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

// Semantic surfaces keep the illustrated guide legible in both system appearances.
enum OnboardingStyle {
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
    static let ink = Color.primary
}

enum OnboardingMotion {
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

struct OnboardingSurface<Content: View>: View {
    var tint: Color = OnboardingStyle.green
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OnboardingStyle.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(tint.opacity(0.18)))
    }
}

struct OnboardingDisclosure<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @State private var expanded = false

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        DisclosureGroup(title, isExpanded: $expanded) { content }
            .animation(OnboardingMotion.detail, value: expanded)
    }
}

struct OnboardingKeycap: View {
    let text: String
    var recording = false

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .contentTransition(.opacity)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(
                recording ? OnboardingStyle.green.opacity(0.12) : Color.primary.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(recording ? OnboardingStyle.green.opacity(0.55) : Color.primary.opacity(0.12))
            }
            .animation(OnboardingMotion.detail, value: recording)
            .animation(OnboardingMotion.detail, value: text)
    }
}

struct OnboardingButtonStyle: ButtonStyle {
    enum Treatment { case primary, secondary, quiet }

    let treatment: Treatment

    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, treatment: treatment)
    }

    private struct Face: View {
        private enum Interaction { case idle, hovered, pressed, disabled }

        let configuration: ButtonStyleConfiguration
        let treatment: Treatment
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        private var interaction: Interaction {
            if !isEnabled { return .disabled }
            if configuration.isPressed { return .pressed }
            return isHovered ? .hovered : .idle
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
                .opacity(interaction == .disabled ? 0.56 : 1)
                .scaleEffect(interaction == .pressed && treatment != .quiet && !reduceMotion ? 0.98 : 1)
                .onHover { isHovered = $0 }
                .animation(reduceMotion ? nil : OnboardingMotion.press, value: interaction)
        }

        @ViewBuilder private var face: some View {
            switch treatment {
            case .primary:
                configuration.label
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .foregroundStyle(.white)
                    .background {
                        let shape = RoundedRectangle(cornerRadius: cornerRadius)
                        shape.fill(Color(red: 0.19, green: 0.43, blue: 0.36).gradient)
                            .overlay {
                                shape.fill(interaction == .pressed ? .black.opacity(0.13) : .white.opacity(hoverAmount))
                            }
                    }
            case .secondary:
                configuration.label
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(OnboardingStyle.green.opacity(0.045 + hoverAmount))
                    }
            case .quiet:
                configuration.label
                    .background {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(OnboardingStyle.green.opacity(hoverAmount))
                            .padding(.horizontal, -4)
                            .padding(.vertical, -2)
                    }
            }
        }

        private var cornerRadius: CGFloat { treatment == .primary ? 10 : 7 }

        private var hoverAmount: Double {
            switch interaction {
            case .idle, .disabled: 0
            case .hovered: 0.08
            case .pressed: 0.15
            }
        }

        private var outline: Color {
            if treatment == .primary {
                return .white.opacity(interaction == .hovered ? 0.26 : 0.10)
            }
            return OnboardingStyle.green.opacity(interaction == .hovered ? 0.36 : 0.19)
        }
    }
}

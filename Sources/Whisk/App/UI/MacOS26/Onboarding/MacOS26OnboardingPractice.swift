// WhiskyMac: modified or added 2026-11-18 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

@available(macOS 26, *)
struct MacOS26OnboardingPractice: View {
    @Environment(\.interfaceTypography) private var typography
    @ObservedObject var bindings: KeyBindingsStore
    let canPasteDirectly: Bool

    var body: some View {
        MacOS26OnboardingSurface {
            VStack(alignment: .leading, spacing: 12) {
                Label(localized("Try it with your own clipboard"), systemImage: "doc.on.clipboard")
                    .font(typography.font(size: 16, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                instruction(
                    1,
                    localized(
                        "Copy a little text in another app, such as TextEdit. Leave the cursor where you want to paste."
                    ))
                instruction(2, OnboardingPracticeInstructions.openHistory(using: bindings))
                instruction(
                    3, OnboardingPracticeInstructions.useSelection(using: bindings, canPasteDirectly: canPasteDirectly))

            }
        }
    }

    private func instruction(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number).")
                .font(typography.font(size: 14).monospacedDigit().weight(.semibold))
                .foregroundStyle(MacOS26OnboardingStyle.green)
            Text(text)
                .font(typography.font(size: 14))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

@available(macOS 26, *)
struct MacOS26OnboardingPracticeAccess: View {
    @Environment(\.interfaceTypography) private var typography
    var reviewPermissions: () -> Void

    var body: some View {
        MacOS26OnboardingSurface {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    message.fixedSize()
                    Spacer(minLength: 0)
                    reviewButton.fixedSize()
                }
                VStack(alignment: .leading, spacing: 10) {
                    message
                    reviewButton
                }
            }
        }
    }

    private var message: some View {
        Label {
            Text(localized("Allow clipboard access to see new copies in your history."))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
        }
        .font(typography.font(size: 14, weight: .medium))
    }

    private var reviewButton: some View {
        Button(localized("Review permissions"), action: reviewPermissions)
            .buttonStyle(MacOS26OnboardingButtonStyle(treatment: .secondary))
    }
}

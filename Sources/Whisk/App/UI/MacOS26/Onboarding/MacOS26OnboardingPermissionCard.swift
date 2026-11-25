// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permissions: LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

@available(macOS 26, *)
struct MacOS26OnboardingPermissionCard: View {
    @Environment(\.interfaceTypography) private var typography
    let symbol: String
    let title: String
    let explanation: String
    let granted: Bool
    let actionTitle: String
    var isOptional = false
    var action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var statusColor: Color {
        if granted { return MacOS26OnboardingStyle.green }
        return isOptional ? .secondary : MacOS26OnboardingStyle.orange
    }

    private var statusSymbol: String {
        if granted { return "checkmark.circle.fill" }
        return isOptional ? "minus.circle" : "exclamationmark.circle.fill"
    }

    var body: some View {
        let iconSide = max(46, typography.points(34))
        return MacOS26OnboardingSurface(cornerRadius: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(typography.font(size: 22, weight: .medium))
                    .foregroundStyle(MacOS26OnboardingStyle.green)
                    .frame(width: iconSide, height: iconSide)
                    .background(MacOS26OnboardingStyle.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 10) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            titleLabel.fixedSize()
                            Spacer(minLength: 0)
                            statusBadge.fixedSize()
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            titleLabel
                            statusBadge
                        }
                    }
                    Text(explanation)
                        .font(typography.font(size: 14))
                        .lineSpacing(3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !granted {
                        HStack {
                            Spacer(minLength: 0)
                            Button(actionTitle, action: action)
                                .buttonStyle(MacOS26OnboardingButtonStyle(treatment: .secondary))
                        }
                        .transition(MacOS26OnboardingMotion.enter(y: 3))
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : MacOS26OnboardingMotion.detail, value: granted)
    }

    private var titleLabel: some View {
        Text(title)
            .font(typography.font(size: 18, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var statusBadge: some View {
        Label(
            granted ? localized("Ready") : localized("Not enabled"),
            systemImage: statusSymbol
        )
        .labelStyle(PermissionBadgeLabelStyle(symbolColor: statusColor))
        .font(typography.font(size: 15, weight: .semibold))
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(statusColor.opacity(granted ? 0.30 : 0.13), in: Capsule())
        .contentTransition(.opacity)
    }

    private struct PermissionBadgeLabelStyle: LabelStyle {
        let symbolColor: Color

        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 6) {
                configuration.icon.foregroundStyle(symbolColor).accessibilityHidden(true)
                configuration.title
            }
        }
    }
}

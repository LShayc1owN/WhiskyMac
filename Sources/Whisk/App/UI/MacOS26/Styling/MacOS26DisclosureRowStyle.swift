// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

@available(macOS 26, *)
struct MacOS26DisclosureRowStyle: DisclosureGroupStyle {
    @Environment(\.interfaceTypography) private var typography
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var animation: Animation? = .easeInOut(duration: 0.2)

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    configuration.label
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(typography.font(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .frame(width: typography.room(16))
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? localized("Expanded") : localized("Collapsed"))

            if configuration.isExpanded {
                configuration.content
            }
        }
        .animation(reduceMotion ? nil : animation, value: configuration.isExpanded)
    }
}

// WhiskyMac: modified or added 2026-11-11 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

/// A separate small card so the group's count has one layout in both presentations.
struct CardGroupIndicator: View {
    let count: Int
    private let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "square.stack.fill")
                .font(.system(size: 11, weight: .medium))
                .accessibilityHidden(true)
            Text("\(count)")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(shape.fill(Color.primary.opacity(0.07)))
        .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localized("Card group"))
        .accessibilityValue(localized("\(count) items"))
    }
}

/// Empty back cards convey grouping without decoding children or adding blur views.
struct CardGroupBackdrop: View {
    static let depth: CGFloat = 8
    var cornerRadius: CGFloat = 18
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            ForEach([2, 1], id: \.self) { layer in
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                shape
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(shape.fill(Color.primary.opacity(scheme == .dark ? 0.07 : 0.03)))
                    .overlay(
                        shape.strokeBorder(
                            Color.primary.opacity(contrast == .increased ? 0.5 : 0.22), lineWidth: 0.5)
                    )
                    .padding(.horizontal, CGFloat(layer) * 5)
                    .offset(y: -CGFloat(layer) * Self.depth / 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

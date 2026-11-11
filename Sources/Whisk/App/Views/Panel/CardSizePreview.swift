// WhiskyMac: modified or added 2026-11-07 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

/// A data-free card that uses the rail card's dimensions and surface.
struct CardSizePreview: View {
    let side: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text(AppIdentity.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)

            Text(localized("Preview"))
                .font(.callout)
            Spacer(minLength: 8)

            HStack {
                Text(localized("Clipboard cards"))
                Spacer()
                Image(systemName: "text.alignleft")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(width: side, height: side)
        .liquidGlass(
            in: RoundedRectangle(cornerRadius: 18, style: .continuous), cornerRadius: 18,
            tint: SourceAppStyle.resolve(bundleID: nil).surfaceTint(dark: scheme == .dark)
        )
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localized("Card size"))
        .accessibilityValue("\(Int(side.rounded())) \(localized("pt"))")
    }
}

// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

@available(macOS 26, *)
struct MacOS26PrivacyPlaceholder: View {
    @Environment(\.interfaceTypography) private var typography

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "eye.slash").font(typography.font(.largeTitle))
            Text(localized("Content hidden by Privacy Mode"))
            Text(localized("Manage privacy protection and automatic detection in Settings."))
                .font(typography.font(.caption)).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

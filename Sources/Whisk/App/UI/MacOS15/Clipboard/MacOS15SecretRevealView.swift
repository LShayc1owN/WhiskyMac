// WhiskyMac: added 2026-11-24 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct MacOS15SecretRevealView: View {
    @Environment(\.interfaceTypography) private var typography

    @ObservedObject var store: HistoryViewStateStore
    let dismiss: () -> Void

    var body: some View {
        MacOS15AuxiliaryDialog {
            Text(localized("Reveal Secret"))
                .font(typography.font(.headline))
                .accessibilityAddTraits(.isHeader)
            if let original = store.revealedSecret {
                Text(original)
                    .font(typography.plainText.font(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } footer: {
            Button(localized("Done"), action: dismiss)
                .buttonStyle(MacOS15DialogActionStyle())
                .keyboardShortcut(.cancelAction)
        }
    }
}

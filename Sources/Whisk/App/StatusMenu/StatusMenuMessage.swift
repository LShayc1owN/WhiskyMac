// WhiskyMac: modified or added 2026-11-05 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

struct StatusMenuMessage: View {
    static let width: CGFloat = 320

    let text: String

    var body: some View {
        Text(Self.formattedText(text))
            .font(.system(size: NSFont.menuFont(ofSize: 0).pointSize))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(width: Self.width - 40, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.vertical, 7)
    }

    static func formattedText(_ text: String) -> String {
        text.replacingOccurrences(of: ". ", with: ".\n")
            .replacingOccurrences(of: "。", with: "。\n")
            .trimmingCharacters(in: .newlines)
    }

    static func item(for text: String) -> NSMenuItem {
        let view = NSHostingView(rootView: Self(text: text))
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.view = view
        return item
    }
}

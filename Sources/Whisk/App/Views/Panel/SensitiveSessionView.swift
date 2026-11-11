// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

/// Sensitive data has its own small rail and never becomes a CardViewState.
/// No drag, editing, links, Quick Look, context snippets or source metadata.
struct SensitiveSessionView: View {
    @ObservedObject var session: SensitiveSessionStore

    var body: some View {
        if !session.isProtected, !session.ids.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(session.ids, id: \.self) { id in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(localized("Sensitive copy"), systemImage: "lock")
                                Spacer()
                                Menu {
                                    Button(localized("Show for 10 seconds")) { session.reveal(id) }
                                    Button(localized("Hide")) { session.hide() }
                                    Button(localized("Copy")) { session.copy(id) }
                                        .disabled(session.revealedID != id)
                                    Button(localized("Delete"), role: .destructive) { session.remove(id) }
                                } label: {
                                    Image(systemName: "ellipsis")
                                }
                                .menuStyle(.borderlessButton)
                                .accessibilityLabel(localized("Sensitive copy actions"))
                            }
                            .font(.caption)
                            Group {
                                if let payload = session.revealedPayload(id) {
                                    revealed(payload)
                                } else {
                                    Text(localized("Hidden — right-click to show temporarily"))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        }
                        .padding(10)
                        .frame(width: 270, height: 85)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .contextMenu {
                            Button(localized("Show for 10 seconds")) { session.reveal(id) }
                            Button(localized("Hide")) { session.hide() }
                            Button(localized("Copy")) { session.copy(id) }.disabled(session.revealedID != id)
                            Button(localized("Delete"), role: .destructive) { session.remove(id) }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder private func revealed(_ payload: Payload) -> some View {
        switch payload {
        case .text(let text): Text(text).lineLimit(3)
        case .link(let url): Text(url.absoluteString).lineLimit(3)
        case .fileReferences(let paths): Text(paths.joined(separator: "\n")).lineLimit(3)
        case .image:
            // Decoding untrusted image bytes can allocate unbounded memory.
            // This session deliberately exports only after explicit reveal.
            Text(localized("Image retained in memory. Copy to view in another app."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

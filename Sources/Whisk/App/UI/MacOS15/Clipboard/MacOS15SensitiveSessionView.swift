// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

/// Sensitive data has its own small rail and never becomes a CardViewState.
/// No drag, editing, links, Quick Look, context snippets or source metadata.
struct MacOS15SensitiveSessionView: View {
    @Environment(\.interfaceTypography) private var typography
    @ObservedObject var session: SensitiveSessionStore

    var body: some View {
        if !session.isProtected, !session.ids.isEmpty {
            GeometryReader { geometry in
                let margin = MacOS15PanelLayout.contentMargin
                let width = min(typography.room(280), max(0, geometry.size.width - 2 * margin))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(session.ids, id: \.self) { id in
                            card(id)
                                .frame(width: width, height: geometry.size.height)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                                .contextMenu { actions(id) }
                        }
                    }
                    .padding(.horizontal, margin)
                }
            }
            .frame(height: MacOS15PanelLayout.sensitiveRowHeight(typography))
        }
    }

    private func card(_ id: UUID) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Label(localized("Sensitive copy"), systemImage: "lock")
                    .font(typography.font(.caption).weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Menu {
                    actions(id)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(typography.font(.body))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(localized("Sensitive copy actions"))
            }
            Group {
                if let payload = session.revealedPayload(id) {
                    ScrollView {
                        revealed(payload)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                } else {
                    Button {
                        session.reveal(id)
                    } label: {
                        Label(localized("Show for 10 seconds"), systemImage: "eye")
                            .font(typography.font(.callout))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.link)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .padding(10)
    }

    @ViewBuilder private func actions(_ id: UUID) -> some View {
        Button(localized("Show for 10 seconds")) { session.reveal(id) }
        Button(localized("Hide")) { session.hide() }
        Button(localized("Copy")) { session.copy(id) }.disabled(session.revealedID != id)
        Button(localized("Delete"), role: .destructive) { session.remove(id) }
    }

    @ViewBuilder private func revealed(_ payload: Payload) -> some View {
        switch SpotlightExcerpt(payload, includesFilePaths: true) {
        case .text(let text):
            Text(verbatim: text).font(typography.plainText.font(.body))
        case .image:
            Text(localized("Image retained in memory. Copy to view in another app."))
                .font(typography.font(.callout)).foregroundStyle(.secondary)
        }
    }
}

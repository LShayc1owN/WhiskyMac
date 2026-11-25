// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

/// The in-panel editor for a card's text: replaces the rail while it is
/// open, so the panel keeps the keyboard. The text lives on the store, so
/// the panel's key router saves it on Return — in either input mode, it
/// sees the key first — and lets Shift-Return break the line. The button
/// saves too; Escape cancels through the panel's cancel path. ⌘S is the
/// card's Save As… shortcut and stays out of here.
@available(macOS 26, *)
struct MacOS26EditItemView: View {
    @Environment(\.interfaceTypography) private var typography

    @ObservedObject var store: HistoryViewStateStore
    let card: CardViewState
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @FocusState private var focused: Bool

    private var text: Binding<String> {
        Binding(get: { store.editingText }, set: { store.setEditingText($0) })
    }

    private var isBlank: Bool {
        store.editingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 8) {
            MacOS26HeaderContentLayout(maximumHeaderFraction: 0.34, spacing: 8) {
                ViewThatFits(in: .vertical) {
                    instructions.fixedSize(horizontal: false, vertical: true)
                    ScrollView { instructions }.scrollIndicators(.visible)
                }
                editor
            }

            MacOS26DialogActions(close: onCancel) {
                Button(localized("Save")) { onSave(store.editingText) }
                    .buttonStyle(MacOS26DialogActionStyle(prominent: true))
                    .disabled(isBlank)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .layoutPriority(1)
        }
        .padding(.horizontal, typography.usesLargeLayout ? 12 : 16)
        .onAppear { focused = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localized("Editor"))
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 4) {
            let title =
                typography.usesLargeLayout
                ? localized("Editor") : String(format: localized("Editing %@"), card.sourceLabel)
            Text(title)
                .font(typography.font(.headline))
                .accessibilityAddTraits(.isHeader)
            if typography.usesLargeLayout {
                Text(card.sourceLabel)
                    .font(typography.font(.caption))
                    .foregroundStyle(.secondary)
            }
            Text(localized("Return saves, Shift-Return breaks the line, Escape cancels."))
                .font(typography.font(.caption))
                .foregroundStyle(.secondary)
            if let error = store.editingError {
                Text(error).font(typography.font(.caption)).foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var editor: some View {
        Group {
            if let rich = store.editingRichText {
                MacOS26RichTextView(text: rich, editable: true) { value in
                    store.editingRichText = value
                    store.setEditingText(value.string)
                }
            } else {
                TextEditor(text: text)
                    .font(typography.plainText.font(size: 13))
                    .scrollContentBackground(.hidden)
                    .focused($focused)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
        .background(MacOS26ClipboardMaterialSurface(shape: RoundedRectangle(cornerRadius: 14), cornerRadius: 14))
    }
}

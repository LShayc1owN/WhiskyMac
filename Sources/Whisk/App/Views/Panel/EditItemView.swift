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
struct EditItemView: View {
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: localized("Editing %@"), card.sourceLabel))
                        .font(.headline)
                    Text(localized("Return saves, Shift-Return breaks the line, Escape cancels."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(localized("Cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(localized("Save")) { onSave(store.editingText) }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBlank)
            }
            // Native button bezels extend beyond their layout bounds.
            // Keep that drawing inside the centered editor column.
            .padding(.horizontal, 8)
            if let error = store.editingError { Text(error).foregroundStyle(.red) }
            Group {
                if let rich = store.editingRichText {
                    RichTextView(text: rich, editable: true) { value in
                        store.editingRichText = value
                        store.setEditingText(value.string)
                    }
                } else {
                    TextEditor(text: text)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .focused($focused)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), cornerRadius: 14)
        }
        .padding(.horizontal, 16)
        .onAppear { focused = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localized("Editor"))
    }
}

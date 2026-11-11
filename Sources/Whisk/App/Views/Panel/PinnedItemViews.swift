// WhiskyMac: modified or added 2026-11-08 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

extension PinTagColor {
    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .gray: .gray
        }
    }
    var label: String { HistoryPresenter.tagLabel(self) }
}

struct PinTagDots: View {
    let tags: Set<PinTagColor>
    var body: some View {
        if !tags.isEmpty {
            HStack(spacing: 5) {
                ForEach(PinTagColor.allCases.filter(tags.contains)) { tag in
                    Circle().fill(tag.color).frame(width: 8, height: 8).accessibilityLabel(tag.label)
                }
            }
        }
    }
}

struct HiddenPinnedContent: View {
    let card: CardViewState
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if card.kindSymbol == ContentCategory.image.symbolName {
                Image(systemName: "photo").font(.largeTitle)
            } else if card.kindSymbol == ContentCategory.files.symbolName {
                Image(systemName: "folder.fill").font(.largeTitle)
            }
            if case .text(let placeholder) = card.preview { Text(placeholder).lineLimit(2) }
            Label(localized("Content always hidden"), systemImage: "eye.slash")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct PinnedItemEditor: View {
    @State var value: PinnedMetadata
    let save: (PinnedMetadata) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized("Pinned item details…")).font(.headline)
            TextField(localized("Note"), text: $value.note, axis: .vertical).lineLimit(1...3)
            Toggle(localized("Always hide content"), isOn: $value.hidesContent)
            Text(
                localized(
                    "The note stays visible. Copy and paste use the original; previews, editing, dragging and online link previews are blocked while hidden."
                )
            )
            .font(.caption).foregroundStyle(.secondary)
            Text(localized("Color tags")).font(.subheadline)
            ForEach(PinTagColor.allCases) { tag in
                Toggle(
                    isOn: Binding(
                        get: { value.tags.contains(tag) },
                        set: { enabled in
                            if enabled { value.tags.insert(tag) } else { value.tags.remove(tag) }
                        })
                ) {
                    HStack {
                        Circle().fill(tag.color).frame(width: 9, height: 9); Text(tag.label)
                    }
                }.toggleStyle(.checkbox)
            }
            Button(localized("Save")) { save(value.normalized) }.keyboardShortcut(.return, modifiers: [.command])
        }
        .textFieldStyle(.roundedBorder)
        .frame(width: 320)
    }
}

/// A deliberately simple vertical pins view; it shares actions and presentation
/// policy with the history rail, never another store or database connection.
struct PinnedListView: View {
    @ObservedObject var store: HistoryViewStateStore
    let actions: PanelActions
    var keyBindings: KeyBindingsStore? = nil
    @State private var query = ""
    @State private var editing: CardViewState?
    @State private var actionCard: CardViewState?
    @State private var hoverTask: Task<Void, Never>?
    @State private var hoveredID: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized("Pinned items")).font(.headline)
            if store.isProtected {
                PrivacySpotlightView(store: store)
            } else if let card = store.editing {
                EditItemView(
                    store: store, card: card, onSave: { _ in store.saveEditing(actions: actions) },
                    onCancel: { store.endEditing() })
            } else {
                TextField(localized("Search pinned items"), text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: query) { _, value in actions.search(value) }
                HStack {
                    Button(localized("All")) { actions.toggleCategoryFilter(allFiltersChipID) }
                    ForEach(store.state.filters.tags) { chip in
                        if let tag = PinTagColor.allCases.first(where: { $0.filterKey == chip.id }) {
                            Image(systemName: chip.isActive ? "checkmark.circle.fill" : "circle.fill")
                                .foregroundStyle(tag.color)
                                .beButton { actions.toggleCategoryFilter(chip.id) }
                                .buttonStyle(.plain)
                                .accessibilityLabel(tag.label)
                        }
                    }
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if store.state.cards.isEmpty { Text(localized("No pinned items")) }
                        ForEach(store.state.cards) { card in
                            row(card)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .onChange(of: editing) { _, value in actions.metadataEditorChanged(value != nil) }
        .onChange(of: actionCard) { _, value in actions.cardMenuChanged(value != nil) }
        .onChange(of: store.interactions) { _, _ in
            hoverTask?.cancel(); hoveredID = nil
        }
        .onDisappear {
            hoverTask?.cancel(); actions.metadataEditorChanged(false); actions.cardMenuChanged(false)
        }
        .onChange(of: store.isProtected) { _, _ in
            editing = nil; actionCard = nil; hoverTask?.cancel(); query = ""
        }
        .onChange(of: store.closeRevision) { _, _ in
            editing = nil; actionCard = nil; hoverTask?.cancel(); query = ""
        }
        .popover(item: $actionCard) { card in
            CardActionMenu(
                card: card, actions: actions, keyBindings: keyBindings, pinnedWorkspace: true,
                perform: { perform(card, $0) },
                editPinnedItem: {
                    actionCard = nil; editing = card
                },
                dismiss: { actionCard = nil }
            )
            .background(CardActionPopoverLayer())
        }
        .popover(item: $editing) { card in
            if store.isProtected {
                PrivacyPlaceholder()
            } else {
                PinnedItemEditor(value: card.pinnedMetadata) { value in
                    actions.updatePinnedMetadata(card.id, value); editing = nil
                }.padding().background(CardActionPopoverLayer())
            }
        }
    }

    private func perform(_ card: CardViewState, _ action: CardAction) {
        guard !store.isProtected else { return }
        if action == .menu { actionCard = card } else { store.interact(card, action: action, actions: actions) }
    }

    private func row(_ card: CardViewState) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(card.pinnedMetadata.note.isEmpty ? card.kindLabel : card.pinnedMetadata.note).font(.headline)
                Spacer()
                if card.isSplitGroup { CardGroupIndicator(count: card.splitCount) }
                Image(systemName: "ellipsis.circle")
                    .beButton { actionCard = card }
                    .buttonStyle(.plain).fixedSize()
            }
            PinTagDots(tags: card.pinnedMetadata.tags)
            if card.contentHidden {
                HiddenPinnedContent(card: card)
            } else {
                // Text-only summary here; full fidelity remains in the existing preview.
                Text(card.accessibilityLabel).font(.caption).lineLimit(3)
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(
            card.isSelected ? Color.matcha.opacity(0.15) : Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .background {
            if card.isSplitGroup { CardGroupBackdrop(cornerRadius: 8) }
        }
        .padding(.top, card.isSplitGroup ? CardGroupBackdrop.depth : 0)
        .contentShape(Rectangle())
        .background(CardRightClick { perform(card, store.interactions.rightClick) })
        .onHover { inside in
            store.cardHoverChanged(card.id, inside: inside)
            if !inside {
                if hoveredID == card.id { hoverTask?.cancel(); hoveredID = nil }
                return
            }
            hoverTask?.cancel()
            hoveredID = card.id
            if store.interactions.hover == .preview {
                hoverTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(store.interactions.hoverDelay))
                    guard !Task.isCancelled else { return }
                    store.hoverPreview(card, actions: actions)
                }
            }
        }
        .gesture(
            TapGesture(count: 2).exclusively(before: TapGesture(count: 1)).onEnded { value in
                switch value {
                case .first: perform(card, store.interactions.doubleClick)
                case .second: perform(card, store.interactions.singleClick)
                }
            })
    }
}

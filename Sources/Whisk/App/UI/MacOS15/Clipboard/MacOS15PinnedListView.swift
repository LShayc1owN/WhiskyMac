// WhiskyMac: modified or added 2026-11-08 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

extension PinTagColor {
    var macOS15Color: Color {
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
}

struct MacOS15PinTagDots: View {
    let tags: Set<PinTagColor>
    var body: some View {
        if !tags.isEmpty {
            HStack(spacing: 5) {
                ForEach(PinTagColor.allCases.filter(tags.contains)) { tag in
                    Circle().fill(tag.macOS15Color).frame(width: 8, height: 8).accessibilityLabel(tag.label)
                }
            }
        }
    }
}

struct MacOS15HiddenPinnedContent: View {
    @Environment(\.interfaceTypography) private var typography

    let card: CardViewState
    var wrapsPlaceholder = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if card.kindSymbol == ContentCategory.image.symbolName {
                Image(systemName: "photo").font(typography.font(.largeTitle))
            } else if card.kindSymbol == ContentCategory.files.symbolName {
                Image(systemName: "folder.fill").font(typography.font(.largeTitle))
            }
            if case .text(let placeholder) = card.preview {
                Text(placeholder).lineLimit(wrapsPlaceholder ? nil : 2)
            }
            if !card.secretMasked {
                Label(localized("Content always hidden"), systemImage: "eye.slash")
                    .font(typography.font(.caption)).foregroundStyle(.secondary)
            }
        }
    }
}

struct MacOS15PinnedItemEditor: View {
    @Environment(\.interfaceTypography) private var typography

    @State var value: PinnedMetadata
    let save: (PinnedMetadata) -> Void

    var body: some View {
        let available = NSScreen.main?.visibleFrame.size ?? CGSize(width: 700, height: 720)
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .vertical) {
                fields.fixedSize(horizontal: false, vertical: true)
                ScrollView { fields }
            }

            Button {
                save(value.normalized)
            } label: {
                Text(localized("Save"))
                    .font(typography.font(.body))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.fill.secondary, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [.command])
            .layoutPriority(1)
        }
        .frame(width: min(typography.room(320), available.width - 64), alignment: .leading)
        .frame(maxHeight: available.height - 80, alignment: .topLeading)
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized("Pinned item details…")).font(typography.font(.headline))
            if typography.usesLargeLayout {
                VStack(alignment: .leading, spacing: 6) {
                    Text(localized("Note")).font(typography.font(.subheadline)).accessibilityHidden(true)
                    TextEditor(text: $value.note)
                        .font(typography.font(.body))
                        .scrollContentBackground(.hidden)
                        .frame(height: typography.lineHeight(13) * 2 + 16)
                        .background(.background, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                        .accessibilityLabel(localized("Note"))
                }
            } else {
                TextField(localized("Note"), text: $value.note, axis: .vertical).lineLimit(1...3)
            }
            Toggle(isOn: $value.hidesContent) {
                Text(localized("Always hide content")).fixedSize(horizontal: false, vertical: true)
            }
            Text(
                localized(
                    "The note stays visible. Copy and paste use the original; previews, editing, dragging and online link previews are blocked while hidden."
                )
            )
            .font(typography.font(.caption)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Text(localized("Color tags")).font(typography.font(.subheadline))
            ForEach(PinTagColor.allCases) { tag in
                Toggle(
                    isOn: Binding(
                        get: { value.tags.contains(tag) },
                        set: { enabled in
                            if enabled { value.tags.insert(tag) } else { value.tags.remove(tag) }
                        })
                ) {
                    HStack {
                        Circle().fill(tag.macOS15Color).frame(width: 9, height: 9); Text(tag.label)
                    }
                }.toggleStyle(.checkbox)
            }
        }
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A deliberately simple vertical pins view; it shares actions and presentation
/// policy with the history rail, never another store or database connection.
struct MacOS15PinnedListView: View {
    @Environment(\.interfaceTypography) private var typography

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
            Text(localized("Pinned items")).font(typography.font(.headline))
            if store.isProtected {
                MacOS15PrivacySpotlightView(store: store)
            } else if let card = store.editing {
                MacOS15EditItemView(
                    store: store, card: card, onSave: { _ in store.saveEditing(actions: actions) },
                    onCancel: { store.endEditing() })
            } else {
                searchField
                ViewThatFits(in: .horizontal) {
                    HStack {
                        allTagsButton
                        tagButtons
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        allTagsButton
                        ScrollView(.horizontal) { tagButtons }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
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
        .onChange(of: store.cardMenuOpen) { _, _ in scheduleHoverPreview() }
        .onReceive(store.$state) { state in
            if let card = actionCard, !state.cards.contains(where: { $0.id == card.id }) { actionCard = nil }
            if let card = editing, !state.cards.contains(where: { $0.id == card.id }) { editing = nil }
        }
        .onChange(of: store.interactions) { _, _ in
            hoverTask?.cancel(); hoveredID = nil
        }
        .onDisappear {
            hoverTask?.cancel()
            actions.metadataEditorChanged(false)
        }
        .onChange(of: store.isProtected) { _, _ in
            editing = nil; actionCard = nil; hoverTask?.cancel(); query = ""
        }
        .onChange(of: store.closeRevision) { _, _ in
            editing = nil; actionCard = nil; hoverTask?.cancel(); query = ""
        }
        .macOS15CardActionPopover(item: $actionCard) { card in
            MacOS15CardActionMenu(
                card: card, actions: actions, keyBindings: keyBindings, pinnedWorkspace: true,
                perform: { perform(card, $0) },
                editPinnedItem: {
                    actionCard = nil; editing = card
                },
                dismiss: { actionCard = nil }
            )
        }
        .macOS15CardActionPopover(item: $editing) { card in
            if store.isProtected {
                MacOS15PrivacyPlaceholder()
            } else {
                MacOS15PinnedItemEditor(value: card.pinnedMetadata) { value in
                    actions.updatePinnedMetadata(card.id, value); editing = nil
                }.padding()
            }
        }
    }

    private var searchField: some View {
        let title = localized("Search pinned items")
        return VStack(alignment: .leading, spacing: 4) {
            if typography.usesLargeLayout {
                Text(title)
                    .font(typography.font(.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
            TextField(title, text: $query, prompt: Text(typography.usesLargeLayout ? "" : title))
                .textFieldStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
        }
        .onChange(of: query) { _, value in actions.search(value) }
    }

    private var allTagsButton: some View {
        Button(localized("All")) { actions.toggleCategoryFilter(allFiltersChipID) }
    }

    private var tagButtons: some View {
        HStack {
            ForEach(store.state.filters.tags) { chip in
                if let tag = PinTagColor.allCases.first(where: { $0.filterKey == chip.id }) {
                    Image(systemName: chip.isActive ? "checkmark.circle.fill" : "circle.fill")
                        .foregroundStyle(tag.macOS15Color)
                        .beButton { actions.toggleCategoryFilter(chip.id) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tag.label)
                }
            }
        }
    }

    private func perform(_ card: CardViewState, _ action: CardAction) {
        guard !store.isProtected else { return }
        if action == .menu { actionCard = card } else { store.interact(card, action: action, actions: actions) }
    }

    private func row(_ card: CardViewState) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if typography.usesLargeLayout {
                ViewThatFits(in: .horizontal) {
                    inlineHeading(for: card)
                    VStack(alignment: .leading, spacing: 5) {
                        rowActions(for: card)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        heading(for: card)
                    }
                }
            } else {
                inlineHeading(for: card)
            }
            MacOS15PinTagDots(tags: card.pinnedMetadata.tags)
            if card.contentHidden {
                if card.secretMasked {
                    Text(card.sourceLabel)
                        .font(typography.font(.caption))
                        .foregroundStyle(.secondary)
                }
                MacOS15HiddenPinnedContent(card: card, wrapsPlaceholder: true)
            } else {
                // Text-only summary here; full fidelity remains in the existing preview.
                Text(card.accessibilityLabel).font(typography.plainText.font(.caption)).lineLimit(3)
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(
            card.isSelected ? Color.macOS15Matcha.opacity(0.15) : Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .background {
            if card.isSplitGroup { MacOS15CardGroupBackdrop(cornerRadius: 8) }
        }
        .padding(.top, card.isSplitGroup ? MacOS15CardGroupBackdrop.depth : 0)
        .contentShape(Rectangle())
        .background(MacOS15CardRightClick { perform(card, store.interactions.rightClick) })
        .onHover { inside in
            store.cardHoverChanged(card.id, inside: inside)
            if !inside {
                if hoveredID == card.id { hoverTask?.cancel(); hoveredID = nil }
                return
            }
            hoverTask?.cancel()
            hoveredID = card.id
            scheduleHoverPreview()
        }
        .gesture(
            TapGesture(count: 2).exclusively(before: TapGesture(count: 1)).onEnded { value in
                switch value {
                case .first: perform(card, store.interactions.doubleClick)
                case .second: perform(card, store.interactions.singleClick)
                }
            })
    }

    private func inlineHeading(for card: CardViewState) -> some View {
        HStack(alignment: .top, spacing: 8) {
            heading(for: card)
            Spacer(minLength: 0)
            rowActions(for: card)
        }
    }

    private func heading(for card: CardViewState) -> some View {
        Text(card.pinnedMetadata.note.isEmpty ? card.kindLabel : card.pinnedMetadata.note)
            .font(typography.font(.headline))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func rowActions(for card: CardViewState) -> some View {
        HStack(spacing: 8) {
            if card.isSplitGroup { MacOS15CardGroupIndicator(count: card.splitCount) }
            Image(systemName: "ellipsis.circle")
                .beButton { actionCard = card }
                .buttonStyle(.plain)
        }
        .fixedSize()
    }

    private func scheduleHoverPreview() {
        hoverTask?.cancel()
        guard !store.cardMenuOpen, !store.pinMetadataEditing, store.interactions.hover == .preview,
            let card = store.state.cards.first(where: { $0.id == hoveredID })
        else { return }
        hoverTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(store.interactions.hoverDelay))
            guard !Task.isCancelled else { return }
            store.hoverPreview(card, actions: actions)
        }
    }
}

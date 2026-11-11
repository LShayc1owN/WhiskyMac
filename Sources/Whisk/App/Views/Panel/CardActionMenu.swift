// WhiskyMac: modified or added 2026-11-10 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

enum CardMenuCommand: String, Identifiable {
    case copy, paste, preview, split, edit, pastePlain, pasteAs
    case openLink, revealFiles, save, pin, pinDetails, stack
    case excludeSource, deleteSource, delete

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .copy: "doc.on.doc"
        case .paste: "doc.on.clipboard"
        case .preview: "eye"
        case .split: "square.split.2x1"
        case .edit: "square.and.pencil"
        case .pastePlain: "text.alignleft"
        case .pasteAs: "textformat"
        case .openLink: "arrow.up.right.square"
        case .revealFiles: "folder"
        case .save: "square.and.arrow.down"
        case .pin: "pin"
        case .pinDetails: "tag"
        case .stack: "square.stack.3d.up"
        case .excludeSource: "hand.raised"
        case .deleteSource: "trash.slash"
        case .delete: "trash"
        }
    }

    var keyAction: KeyAction? {
        switch self {
        case .copy: .copySelection
        case .paste: .pasteSelection
        case .preview: .previewSelection
        case .edit: .editSelection
        case .pastePlain: .pastePlain
        case .openLink: .openSelection
        case .revealFiles: .revealSelection
        case .save: .saveSelection
        case .pin: .pinSelection
        case .stack: .stackSelection
        case .excludeSource: .excludeSelectionSource
        case .deleteSource: .deleteSelectionSource
        case .delete: .deleteSelection
        case .split, .pasteAs, .pinDetails: nil
        }
    }

    var isDestructive: Bool { self == .delete || self == .deleteSource }

    func title(for card: CardViewState) -> String {
        switch self {
        case .copy: localized("Copy")
        case .paste: localized("Paste")
        case .preview: localized("Preview")
        case .split: localized("Split…")
        case .edit: localized("Edit…")
        case .pastePlain: localized("Paste as Plain Text")
        case .pasteAs: localized("Paste as…")
        case .openLink: localized("Open Link")
        case .revealFiles: localized("Reveal in Finder")
        case .save: localized("Save As…")
        case .pin: card.isPinned ? localized("Unpin") : localized("Pin")
        case .pinDetails: localized("Pinned item details…")
        case .stack: card.stackPosition == nil ? localized("Add to Paste Stack") : localized("Remove from Paste Stack")
        case .excludeSource: String(format: localized("Exclude %@"), card.sourceLabel)
        case .deleteSource: String(format: localized("Delete All from %@"), card.sourceLabel)
        case .delete: localized("Delete")
        }
    }
}

/// The same command layout is used by the card's ellipsis and by a configured Menu action.
struct CardActionMenu: View {
    let card: CardViewState
    let actions: PanelActions
    var keyBindings: KeyBindingsStore? = nil
    var pinnedWorkspace = false
    let perform: (CardAction) -> Void
    let editPinnedItem: () -> Void
    let dismiss: () -> Void

    @State private var showsTransforms = false
    @FocusState private var focusedID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func sections(for card: CardViewState, pinnedWorkspace: Bool = false) -> [[CardMenuCommand]] {
        var use: [CardMenuCommand] = [.copy, .paste]
        if !card.contentHidden { use.append(.preview) }

        var content: [CardMenuCommand] = []
        if !card.contentHidden, !card.isSplitGroup, card.transformable || card.variantIDs.count > 1 {
            content.append(.split)
        }
        if card.transformable, !card.contentHidden, !card.isSplitGroup { content.append(.edit) }
        if card.transformable || card.isSplitGroup { content.append(.pastePlain) }
        if card.transformable, !card.contentHidden, !card.isSplitGroup { content.append(.pasteAs) }

        var manage: [CardMenuCommand] = []
        if case .link = card.dragPayload { manage.append(.openLink) }
        if case .files = card.dragPayload { manage.append(.revealFiles) }
        if card.saveable, !card.contentHidden, !card.isSplitGroup { manage.append(.save) }
        if card.isPinned { manage.append(.pinDetails) }
        manage.append(.pin)
        if !card.isSplitGroup { manage.append(.stack) }

        var source: [CardMenuCommand] = []
        if card.sourceBundleID != nil { source.append(.excludeSource) }
        if card.sourceKey != nil, !pinnedWorkspace { source.append(.deleteSource) }
        source.append(.delete)
        return [use, content, manage, source].filter { !$0.isEmpty }
    }

    private var visibleCommands: [CardMenuCommand] {
        Self.sections(for: card, pinnedWorkspace: pinnedWorkspace).flatMap { $0 }
    }
    private var visibleIDs: [String] {
        showsTransforms
            ? ["back"] + TextTransform.allCases.map { "transform.\($0.rawValue)" } : visibleCommands.map(\.id)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if showsTransforms {
                        menuRow(id: "back", title: localized("Paste as…"), symbol: "chevron.left") {
                            showsTransforms = false
                        }
                        Divider().padding(.horizontal, 7).padding(.vertical, 3)
                        ForEach(TextTransform.allCases, id: \.rawValue) { transform in
                            menuRow(id: "transform.\(transform.rawValue)", title: transform.label, symbol: "textformat")
                            {
                                dismiss()
                                actions.transform(card.id, transform)
                            }
                        }
                    } else {
                        if card.variantIDs.count > 1 {
                            Text(localized("Pin, delete and stack actions apply to the newest format."))
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 7).padding(.bottom, 4)
                        }
                        ForEach(
                            Array(Self.sections(for: card, pinnedWorkspace: pinnedWorkspace).enumerated()), id: \.offset
                        ) {
                            index, section in
                            if index > 0 { Divider().padding(.horizontal, 7).padding(.vertical, 3) }
                            ForEach(section) { command in
                                menuRow(
                                    id: command.id, title: command.title(for: card), symbol: command.symbol,
                                    shortcut: command.keyAction.flatMap { keyBindings?.label(for: $0) },
                                    destructive: command.isDestructive,
                                    accessory: command == .pasteAs ? "chevron.right" : nil
                                ) {
                                    run(command)
                                }
                            }
                        }
                    }
                }
                .padding(3)
            }
            .frame(width: 304)
            .frame(maxHeight: min(520, (NSScreen.main?.visibleFrame.height ?? 700) - 70))
            .onMoveCommand { direction in
                guard let current = focusedID.flatMap({ visibleIDs.firstIndex(of: $0) }) else {
                    focusedID = visibleIDs.first
                    return
                }
                switch direction {
                case .up: focusedID = visibleIDs[max(0, current - 1)]
                case .down: focusedID = visibleIDs[min(visibleIDs.count - 1, current + 1)]
                default: break
                }
            }
            .onExitCommand {
                if showsTransforms { showsTransforms = false } else { dismiss() }
            }
            .onAppear { focusedID = visibleIDs.first }
            .onChange(of: showsTransforms) { _, _ in focusedID = visibleIDs.first }
            .onChange(of: focusedID) { _, id in
                guard let id else { return }
                if reduceMotion {
                    proxy.scrollTo(id)
                } else {
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) }
                }
            }
        }
    }

    private func menuRow(
        id: String, title: String, symbol: String, shortcut: String? = nil,
        destructive: Bool = false, accessory: String? = nil, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 14))
                    .frame(width: 18, alignment: .center)
                    .foregroundStyle(destructive ? Color.red : Color.secondary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(destructive ? Color.red : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .accessibilityHidden(true)
                }
                if let accessory {
                    Image(systemName: accessory).font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary).accessibilityHidden(true)
                }
            }
            .frame(minHeight: 30)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity)
            .background(
                focusedID == id ? Color.accentColor.opacity(0.16) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focusedID, equals: id)
        .onHover { inside in if inside { focusedID = id } }
        .id(id)
        .accessibilityLabel(title)
        .accessibilityHint(shortcut ?? "")
    }

    private func run(_ command: CardMenuCommand) {
        if command == .pasteAs { showsTransforms = true; return }
        if command == .pinDetails { editPinnedItem(); return }
        dismiss()
        switch command {
        case .copy: perform(.copy)
        case .paste: perform(.paste)
        case .preview: perform(.preview)
        case .split: actions.split(card.id)
        case .edit: perform(.edit)
        case .pastePlain: actions.selectPlain(card.id)
        case .openLink:
            if case .link(let url) = card.dragPayload { actions.openLink(url) }
        case .revealFiles:
            if case .files(let paths) = card.dragPayload { actions.revealFiles(paths) }
        case .save: actions.saveToDisk(card.dragPayload)
        case .pin: actions.togglePin(card.id)
        case .stack: actions.stack(card.id)
        case .excludeSource:
            if let bundleID = card.sourceBundleID { actions.excludeSource(bundleID, card.sourceLabel) }
        case .deleteSource:
            if let key = card.sourceKey { actions.deleteAllFromSource(key) }
        case .delete: actions.delete(card.id)
        case .pasteAs, .pinDetails: break
        }
    }
}

// WhiskyMac: modified or added 2026-11-10 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

enum CardMenuCommand: String, Identifiable {
    case copy, paste, preview, split, edit, pastePlain, pasteAs
    case revealSecret
    case openLink, revealFiles, save, pin, pinDetails, stack
    case excludeSource, deleteSource, delete

    var id: String { rawValue }

    var symbol: String {
        switch self {
            case .copy: "doc.on.doc"
            case .paste: "doc.on.clipboard"
            case .preview, .revealSecret: "eye"
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
        case .split, .pasteAs, .pinDetails, .revealSecret: nil
        }
    }

    var isDestructive: Bool { self == .delete || self == .deleteSource }

    func title(for card: CardViewState) -> String {
        switch self {
            case .copy: localized("Copy")
            case .paste: localized("Paste")
            case .preview: localized("Preview")
            case .revealSecret: localized("Reveal Secret")
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

    static func sections(for card: CardViewState, pinnedWorkspace: Bool = false) -> [[CardMenuCommand]] {
        var use: [CardMenuCommand] = [.copy, .paste]
        if !card.contentHidden { use.append(.preview) }
        if card.secretMasked { use.append(.revealSecret) }

        var content: [CardMenuCommand] = []
        if !card.contentHidden, !card.isSplitGroup, card.transformable || card.variantCount > 1 {
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

    func run(for card: CardViewState, actions: PanelActions, perform: (CardAction) -> Void) {
        switch self {
        case .copy: perform(.copy)
        case .paste: perform(.paste)
        case .preview: perform(.preview)
        case .revealSecret: actions.revealSecret(card.id)
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

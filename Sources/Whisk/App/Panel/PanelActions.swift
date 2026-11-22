// WhiskyMac: modified or added 2026-11-18 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

/// Type-erased entry points into the controller, so views stay free of the
/// controller's gateway generics.
struct PanelActions {
    let search: (String) -> Void
    let select: (UUID) -> Void
    let selectPlain: (UUID) -> Void
    /// Puts the card on the pasteboard and closes, without pasting.
    let copy: (UUID) -> Void
    let copySelected: () -> Void
    let transform: (UUID, TextTransform) -> Void
    let openLink: (URL) -> Void
    let revealFiles: ([String]) -> Void
    let saveToDisk: (DragPayload) -> Void
    let stack: (UUID) -> Void
    let excludeSource: (_ bundleID: String, _ name: String) -> Void
    let deleteAllFromSource: (String) -> Void
    let beginEditing: (CardViewState) -> Void
    let edit: (UUID, String) -> Void
    let undo: () -> Void
    let highlight: (UUID) -> Void
    let activate: () -> Void
    let activatePlain: () -> Void
    let activateCard: (Int) -> Void
    let navigate: (ArrowDirection) -> Void
    let jumpToEdge: (SelectionEdge) -> Void
    let switchChipGroup: () -> Void
    let toggleSourceFilter: (String) -> Void
    let toggleCategoryFilter: (String) -> Void
    let focusSourceChip: (String) -> Void
    let focusCategoryChip: (String) -> Void
    let togglePin: (UUID) -> Void
    let delete: (UUID) -> Void
    let dragBegan: () -> Void
    let togglePinSelected: () -> Void
    let deleteSelected: () -> Void
    let stackSelected: () -> Void
    let panelWillShow: () -> Void
    /// Starts the system's pasteboard permission flow and opens its settings.
    let requestClipboardAccess: () -> Void
    var editRich: (UUID, String, Data) -> Void = { _, _, _ in }
    var selectSourceFilter: (String) -> Void = { _ in }
    var selectCategoryFilter: (String) -> Void = { _ in }
    var clearHistory: () -> Void = {}
    var toggleHistoryVisibility: () -> Void = {}
    var setHistoryHiding: (HistoryHidingRule) -> Void = { _ in }
    var clearTypeHistoryHiding: () -> Void = {}
    var updatePinnedMetadata: (UUID, PinnedMetadata) -> Void = { _, _ in }
    var metadataEditorChanged: (Bool) -> Void = { _ in }
    var cardMenuChanged: (Bool) -> Void = { _ in }
    var split: (UUID) -> Void = { _ in }
    var preparePinned: (Bool) -> Void = { _ in }
}

extension PanelActions {
    func guarded(by isProtected: @escaping () -> Bool) -> PanelActions {
        PanelActions(
            search: { if !isProtected() { self.search($0) } },
            select: { if !isProtected() { self.select($0) } },
            selectPlain: { if !isProtected() { self.selectPlain($0) } },
            copy: { if !isProtected() { self.copy($0) } },
            copySelected: { if !isProtected() { self.copySelected() } },
            transform: { if !isProtected() { self.transform($0, $1) } },
            openLink: { if !isProtected() { self.openLink($0) } },
            revealFiles: { if !isProtected() { self.revealFiles($0) } },
            saveToDisk: { if !isProtected() { self.saveToDisk($0) } },
            stack: { if !isProtected() { self.stack($0) } },
            excludeSource: { if !isProtected() { self.excludeSource($0, $1) } },
            deleteAllFromSource: { if !isProtected() { self.deleteAllFromSource($0) } },
            beginEditing: { if !isProtected() { self.beginEditing($0) } },
            edit: { if !isProtected() { self.edit($0, $1) } },
            undo: { if !isProtected() { self.undo() } },
            highlight: { if !isProtected() { self.highlight($0) } },
            activate: { if !isProtected() { self.activate() } },
            activatePlain: { if !isProtected() { self.activatePlain() } },
            activateCard: { if !isProtected() { self.activateCard($0) } },
            navigate: { if !isProtected() { self.navigate($0) } },
            jumpToEdge: { if !isProtected() { self.jumpToEdge($0) } },
            switchChipGroup: { if !isProtected() { self.switchChipGroup() } },
            toggleSourceFilter: { if !isProtected() { self.toggleSourceFilter($0) } },
            toggleCategoryFilter: { if !isProtected() { self.toggleCategoryFilter($0) } },
            focusSourceChip: { if !isProtected() { self.focusSourceChip($0) } },
            focusCategoryChip: { if !isProtected() { self.focusCategoryChip($0) } },
            togglePin: { if !isProtected() { self.togglePin($0) } },
            delete: { if !isProtected() { self.delete($0) } },
            dragBegan: { if !isProtected() { self.dragBegan() } },
            togglePinSelected: { if !isProtected() { self.togglePinSelected() } },
            deleteSelected: { if !isProtected() { self.deleteSelected() } },
            stackSelected: { if !isProtected() { self.stackSelected() } },
            panelWillShow: { if !isProtected() { self.panelWillShow() } },
            requestClipboardAccess: { if !isProtected() { self.requestClipboardAccess() } },
            editRich: { if !isProtected() { self.editRich($0, $1, $2) } },
            selectSourceFilter: { if !isProtected() { self.selectSourceFilter($0) } },
            selectCategoryFilter: { if !isProtected() { self.selectCategoryFilter($0) } },
            clearHistory: { if !isProtected() { self.clearHistory() } },
            toggleHistoryVisibility: { self.toggleHistoryVisibility() },
            setHistoryHiding: { self.setHistoryHiding($0) },
            clearTypeHistoryHiding: { self.clearTypeHistoryHiding() },
            updatePinnedMetadata: { if !isProtected() { self.updatePinnedMetadata($0, $1) } },
            metadataEditorChanged: { self.metadataEditorChanged($0) },
            cardMenuChanged: { self.cardMenuChanged($0) },
            split: { if !isProtected() { self.split($0) } },
            preparePinned: { self.preparePinned($0) }
        )
    }
}

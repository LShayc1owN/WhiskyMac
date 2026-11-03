// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Combine
import Foundation

/// Bridges the presenter's output to SwiftUI observation. Frameworks ring:
/// nothing below the views knows this exists.
final class HistoryViewStateStore: ObservableObject {
    let sensitiveSession = SensitiveSessionStore()
    @Published private(set) var state: HistoryViewState = .empty
    @Published private(set) var appearanceRevision = 0
    func appearanceDidChange() { appearanceRevision += 1 }
    @Published private(set) var focusRevision = 0
    @Published private(set) var closeRevision = 0

    /// Vim navigation splits the panel into two input modes: SEARCH is the
    /// field with focus, NORMAL frees the letters to act as commands. With
    /// vim off the panel simply never leaves SEARCH. The search key rides
    /// along so hints always show the actual binding.
    @Published private(set) var vimEnabled = false
    @Published private(set) var searchActive = true
    @Published private(set) var vimSearchKey = "s"

    /// The card whose text is being edited in the panel, while it is, and
    /// the text as it stands — here rather than in the view, so the key
    /// router can save it on Return.
    @Published private(set) var editing: CardViewState?
    @Published private(set) var editingText = ""

    @Published private(set) var isProtected = false
    @Published private(set) var allowsSpotlight = false
    @Published private(set) var panelVisible = false
    @Published private(set) var privacyAllowsSearch = false
    @Published private(set) var privacyShowsSourceApps = false
    @Published private(set) var protectedQuery = ""
    var protectedSearch: ((String) -> Void)?
    private let protectedSearchDebounce: Debouncer
    private let previewCloseScheduler: Debouncer.Scheduler
    private var previewCloseWork: DispatchWorkItem?
    private var previewCloseGeneration = 0
    private var hoveredCards: Set<UUID> = []
    enum PreviewOrigin: Equatable { case hover(UUID), explicit }
    private(set) var previewOrigin: PreviewOrigin?
    static let hoverPreviewCloseDelay: TimeInterval = 0.4

    init(
        protectedSearchDebounce: Debouncer = Debouncer(delay: 0.18),
        previewCloseScheduler: @escaping Debouncer.Scheduler = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    ) {
        self.protectedSearchDebounce = protectedSearchDebounce
        self.previewCloseScheduler = previewCloseScheduler
    }

    deinit { previewCloseWork?.cancel() }

    private func cancelPreviewClose() {
        previewCloseGeneration += 1
        previewCloseWork?.cancel()
        previewCloseWork = nil
    }

    func cardHoverChanged(_ id: UUID, inside: Bool) {
        if inside { hoveredCards.insert(id) } else { hoveredCards.remove(id) }
        guard previewOrigin == .hover(id) else { return }
        cancelPreviewClose()
        guard !inside else { return }
        let generation = previewCloseGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.previewCloseGeneration == generation,
                self.previewOrigin == .hover(id), !self.hoveredCards.contains(id)
            else { return }
            self.dismissPreview()
        }
        previewCloseWork = work
        previewCloseScheduler(Self.hoverPreviewCloseDelay, work)
    }

    func hoverPreview(_ card: CardViewState, actions: PanelActions) {
        guard !isProtected, panelVisible, interactions.hover == .preview, hoveredCards.contains(card.id),
            state.cards.contains(where: { $0.id == card.id }), previewOrigin != .explicit
        else { return }
        cancelPreviewClose()
        previewOrigin = .hover(card.id)
        actions.highlight(card.id)
        showPreview?()
    }

    func toggleExplicitPreview() {
        guard !isProtected else { return }
        if previewVisible, previewOrigin == .explicit {
            dismissPreview()
        } else {
            cancelPreviewClose()
            previewOrigin = .explicit
            showPreview?()
        }
    }

    private func dismissPreview() {
        hidePreview?()
        closePreview()
    }

    func setPrivacyPermissions(allowSearch: Bool, showSourceApps: Bool) {
        privacyAllowsSearch = allowSearch
        privacyShowsSourceApps = showSourceApps
        if !allowSearch { resetProtectedSearch() }
    }

    func searchWhileProtected(_ query: String) {
        guard isProtected, privacyAllowsSearch, panelVisible else { return }
        protectedQuery = query
        protectedSearchDebounce.schedule { [weak self] in
            guard let self, self.isProtected, self.privacyAllowsSearch, self.panelVisible,
                self.protectedQuery == query
            else { return }
            self.protectedSearch?(query)
        }
    }

    func protectedSourceLabel(for id: UUID) -> String? {
        guard isProtected, privacyShowsSourceApps else { return nil }
        guard let card = latestState.cards.first(where: { $0.id == id }) else { return nil }
        return card.sourceKey == nil ? localized("Unknown") : card.sourceLabel
    }

    private func resetProtectedSearch(force: Bool = false) {
        protectedSearchDebounce.cancel()
        let hadQuery = !protectedQuery.isEmpty
        protectedQuery = ""
        if hadQuery || force { protectedSearch?("") }
    }

    var protectedCardIDs: [UUID] { latestState.cards.map(\.id) }

    func setSpotlightAllowed(_ allowed: Bool) { allowsSpotlight = allowed }
    func setPanelVisible(_ visible: Bool) { panelVisible = visible }

    func spotlightPayload(for id: UUID) -> Payload? {
        guard isProtected, allowsSpotlight, panelVisible, interactions.hover == .preview,
            protectedCardIDs.contains(id)
        else { return nil }
        return detailSource?(id)?.payload
    }
    @Published private(set) var previewItems: [ClipboardItem] = []
    @Published var expandedVersions = false
    @Published var pendingAction: CardAction?
    @Published private(set) var editingError: String?
    @Published var editingRichText: NSAttributedString?
    @Published var appFilterTrigger = AppFilterTrigger.click
    @Published var interactions = InteractionBindings() {
        didSet {
            if oldValue != interactions, case .hover = previewOrigin { dismissPreview() }
        }
    }
    var detailSource: ((UUID) -> ClipboardItem?)?
    var detailsSource: (([UUID]) -> [ClipboardItem])?
    var hidePreview: (() -> Void)?
    var showPreview: (() -> Void)?
    private var latestState: HistoryViewState = .empty
    private var previewVisible = false

    var previewCard: CardViewState? {
        if case .hover(let id) = previewOrigin { return state.cards.first { $0.id == id } }
        return state.selectedCard
    }

    func setPrivacy(_ protected: Bool) {
        let changed = protected != isProtected
        sensitiveSession.setProtected(protected)
        isProtected = protected
        resetProtectedSearch(force: changed)
        if protected { dismissPreview() }
        endEditing()
        previewItems = []
        pendingAction = nil
        expandedVersions = false
        state = protected ? .empty : latestState
        if !protected, previewVisible { preparePreview() }
    }

    func preparePreview() {
        guard !isProtected else { previewItems = []; return }
        previewVisible = true
        if previewOrigin == nil { previewOrigin = .explicit }
        guard let card = previewCard else { previewItems = []; return }
        let ids = card.variantIDs.isEmpty ? [card.id] : card.variantIDs
        previewItems = detailsSource?(ids) ?? ids.compactMap { detailSource?($0) }
    }

    func closePreview() {
        cancelPreviewClose()
        previewOrigin = nil
        previewVisible = false
        previewItems = []
        pendingAction = nil
        expandedVersions = false
    }

    func interact(_ card: CardViewState, action: CardAction, actions: PanelActions) {
        guard !isProtected else { return }
        if card.variantIDs.count > 1, [.paste, .copy, .edit].contains(action) {
            actions.highlight(card.id)
            pendingAction = action
            cancelPreviewClose()
            previewOrigin = .explicit
            showPreview?()
            return
        }
        switch action {
        case .paste: actions.select(card.id)
        case .copy: actions.copy(card.id)
        case .preview:
            actions.highlight(card.id)
            toggleExplicitPreview()
        case .edit: beginEditing(card)
        case .menu, .none: break
        }
    }

    func chooseVersion(_ id: UUID, actions: PanelActions) {
        guard !isProtected, previewItems.contains(where: { $0.id == id }), let item = detailSource?(id) else { return }
        let action = pendingAction ?? .copy
        pendingAction = nil
        switch action {
        case .paste: actions.select(id)
        case .copy: actions.copy(id)
        case .edit:
            if let card = state.selectedCard {
                beginEditing(card)
                editingID = id
                editingText = item.payload.searchableText ?? ""
                editingRichText = RichTextCodec.decode(item.rtf, fallback: editingText)
            }
        default: break
        }
    }

    private(set) var editingID: UUID?

    func saveEditing(actions: PanelActions) {
        guard !isProtected, let id = editingID else { return }
        if let rich = editingRichText {
            guard let rtf = RichTextCodec.encode(rich) else {
                editingError = localized("The rich text could not be saved."); return
            }
            actions.editRich(id, rich.string, rtf)
        } else {
            actions.edit(id, editingText)
        }
        endEditing()
    }

    func beginEditing(_ card: CardViewState) {
        guard !isProtected, card.transformable else { return }
        editingID = card.id
        if let item = detailSource?(card.id), let rtf = item.rtf {
            editingRichText = RichTextCodec.decode(rtf, fallback: Self.editableText(of: card))
        }
        editingText = Self.editableText(of: card)
        editing = card
        hidePreview?()
    }

    func setEditingText(_ text: String) {
        editingText = text
    }

    func endEditing() {
        editingError = nil
        editingID = nil
        editingRichText = nil
        editing = nil
        editingText = ""
    }

    /// What the editor starts from: the card's text, or a link's address.
    static func editableText(of card: CardViewState) -> String {
        switch card.dragPayload {
        case .text(let value): return value
        case .link(let url): return url.absoluteString
        case .image, .files: return ""
        }
    }

    /// The card's side in points; the selected card grows by the zoom.
    @Published private(set) var cardSide: CGFloat = 200
    static let selectionZoom: CGFloat = 1.05
    /// The room the rail gives one card: the zoomed slot plus the gap.
    static let cardGap: CGFloat = 14

    var zoomedCardSide: CGFloat {
        cardSide * Self.selectionZoom
    }

    var cardStride: CGFloat {
        zoomedCardSide + Self.cardGap
    }

    func configureCards(side: CGFloat) {
        cardSide = side
    }

    func update(_ newState: HistoryViewState) {
        if newState.selectedID != latestState.selectedID { pendingAction = nil; expandedVersions = false }
        latestState = newState
        state = isProtected ? .empty : newState
        if previewVisible, !isProtected { preparePreview() }
    }

    func requestSearchFocus() {
        focusRevision += 1
    }

    func configureInput(vim: Bool, searchKey: String) {
        vimEnabled = vim
        searchActive = !vim
        vimSearchKey = searchKey
    }

    func setSearchActive(_ active: Bool) {
        guard active != searchActive else { return }
        searchActive = active
    }

    /// One cursor at a time: while vim's search mode holds it, neither a
    /// card nor a chip may wear one. With vim off the field never holds a
    /// cursor of its own.
    var cursorOnSearch: Bool {
        vimEnabled && searchActive
    }

    /// The capsule stays folded while it has nothing to show: it stretches
    /// on the first typed character, or the moment vim's search mode
    /// engages, even empty.
    func searchExpanded(typed text: String) -> Bool {
        !text.isEmpty || cursorOnSearch
    }

    /// The panel just went away: the rail rewinds to its leading edge
    /// while nobody is looking, so every open starts at position zero
    /// with no visible travel.
    func panelDidClose() {
        dismissPreview()
        hoveredCards = []
        panelVisible = false
        resetProtectedSearch()
        sensitiveSession.setPanelVisible(false)
        closeRevision += 1
    }
}

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
            selectSourceFilter: { if !isProtected() { self.selectSourceFilter($0) } }
        )
    }
}

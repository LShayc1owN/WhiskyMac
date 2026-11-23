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
    @Published var splitSession: SplitSession?
    @Published var splitGroupSession: SplitGroupSession?
    @Published var splitVersions: [ClipboardItem] = []
    func chooseSplitVersion(_ versions: [ClipboardItem]) {
        guard !isProtected, panelVisible else { return }
        hidePreview?()
        closeSplitSessions()
        splitVersions = versions.filter { !$0.pinnedMetadata.hidesContent && $0.splitGroup == nil }
        auxiliaryDidChange()
    }
    var beginSplit: (UUID) -> Void = { _ in }
    var auxiliaryDidChange: () -> Void = {}

    func closeSplitSessions() {
        splitSession?.invalidate(); splitGroupSession?.invalidate()
        splitSession = nil; splitGroupSession = nil; splitVersions = []
        auxiliaryDidChange()
    }

    private func validateSplitSessions() {
        splitSession?.invalidateIfNeeded(); splitGroupSession?.invalidateIfNeeded()
        if !splitVersions.isEmpty, splitVersions.contains(where: { detailSource?($0.id) != $0 }) {
            closeSplitSessions()
        }
    }
    @Published var isPinnedWorkspace = false
    @Published var isPinnedList = false
    @Published var pinMetadataEditing = false
    @Published var cardMenuOpen = false {
        didSet {
            guard oldValue != cardMenuOpen else { return }
            cancelPreviewClose()
            if cardMenuOpen {
                menuPreviewCard = previewVisible ? previewCard : nil
            } else {
                menuPreviewCard = nil
                if previewVisible, !isProtected { preparePreview() }
                if case .hover(let id) = previewOrigin {
                    cardHoverChanged(id, inside: hoveredCards.contains(id))
                }
            }
        }
    }
    enum HidingOptions {
        case time, typeOrSource
    }

    @Published var historyHidingOptions: HidingOptions?
    var historyHidingOptionsOpen: Bool { historyHidingOptions != nil }
    @Published private(set) var state: HistoryViewState = .empty
    @Published private(set) var appearanceRevision = 0
    func appearanceDidChange() { appearanceRevision += 1 }
    @Published private(set) var focusRevision = 0
    @Published private(set) var closeRevision = 0
    private(set) var historyVisibilityRevision = 0

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
    @Published var spotlight = SpotlightPreferences()
    @Published private(set) var panelVisible = false
    @Published private(set) var privacyAllowsSearch = false
    @Published private(set) var privacyAllowsFiltering = false
    @Published private(set) var privacyAllowsAppFiltering = false
    @Published private(set) var privacyAllowsHandoffFiltering = false
    @Published private(set) var privacyShowsSourceApps = false
    @Published private(set) var protectedQuery = ""
    var protectedSearch: ((String) -> Void)?
    var searchMatchModeChanged: ((SearchMatchMode, String) -> Void)?
    var searchMatchMode: SearchMatchMode { latestState.searchMatchMode }

    func selectSearchMatchMode(_ mode: SearchMatchMode, query: String = "", whileProtected: Bool = false) {
        guard panelVisible, isProtected == whileProtected, searchMatchMode != mode,
            !whileProtected || privacyAllowsSearch
        else { return }
        if whileProtected { protectedSearchDebounce.cancel() }
        searchMatchModeChanged?(mode, whileProtected ? protectedQuery : query)
    }
    enum ProtectedFilterAction {
        case toggleApp(String), selectApp(String), toggleKind(String), selectKind(String), reset
    }
    var protectedFilter: ((ProtectedFilterAction) -> Void)?

    private var allowsProtectedFiltering: Bool {
        privacyAllowsFiltering || privacyAllowsAppFiltering || privacyAllowsHandoffFiltering
    }

    var protectedFilters: FilterBarViewState {
        guard isProtected, allowsProtectedFiltering else { return .empty }
        let filters = latestState.filters
        return FilterBarViewState(
            all: filters.all, pinned: privacyAllowsFiltering ? filters.pinned : [],
            apps: privacyAllowsAppFiltering ? filters.apps : [],
            kinds: privacyAllowsFiltering ? filters.kinds : [], tags: privacyAllowsFiltering ? filters.tags : [],
            origins: privacyAllowsHandoffFiltering ? filters.origins : [])
    }

    func filterWhileProtected(_ action: ProtectedFilterAction) {
        guard isProtected, panelVisible else { return }
        switch action {
        case .toggleApp(let key), .selectApp(let key):
            guard privacyAllowsAppFiltering, protectedFilters.apps.contains(where: { $0.id == key }) else { return }
        case .toggleKind(let key), .selectKind(let key):
            let filters = protectedFilters
            let groups: [[FilterChip]] = [filters.all, filters.pinned, filters.origins, filters.kinds, filters.tags]
            guard groups.joined().contains(where: { $0.id == key }) else { return }
        case .reset: return  // Reset is internal; user reset is the visible All chip.
        }
        protectedSearchDebounce.flush()
        protectedFilter?(action)
    }
    private let protectedSearchDebounce: Debouncer
    private let previewCloseScheduler: Debouncer.Scheduler
    private var previewCloseWork: DispatchWorkItem?
    private var previewCloseGeneration = 0
    private var hoveredCards: Set<UUID> = []
    private var menuPreviewCard: CardViewState?
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
        guard !cardMenuOpen else { return }
        guard previewOrigin == .hover(id) else { return }
        cancelPreviewClose()
        guard !inside else { return }
        let generation = previewCloseGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.previewCloseGeneration == generation,
                self.previewOrigin == .hover(id), !self.hoveredCards.contains(id), !self.cardMenuOpen
            else { return }
            self.dismissPreview()
        }
        previewCloseWork = work
        previewCloseScheduler(Self.hoverPreviewCloseDelay, work)
    }

    func hoverPreview(_ card: CardViewState, actions: PanelActions) {
        guard !card.contentHidden, state.cards.first(where: { $0.id == card.id })?.contentHidden == false,
            !isProtected, panelVisible, !cardMenuOpen, !pinMetadataEditing,
            interactions.hover == .preview, hoveredCards.contains(card.id),
            state.cards.contains(where: { $0.id == card.id }), previewOrigin != .explicit
        else { return }
        cancelPreviewClose()
        previewOrigin = .hover(card.id)
        actions.highlight(card.id)
        showPreview?()
    }

    func toggleExplicitPreview() {
        guard !isProtected, state.selectedCard?.contentHidden != true else { return }
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

    func setPrivacyPermissions(
        allowSearch: Bool, showSourceApps: Bool, allowFiltering: Bool = false, allowAppFiltering: Bool = false,
        allowHandoffFiltering: Bool = false
    ) {
        let resetFilters =
            isProtected
            && ((privacyAllowsFiltering && !allowFiltering)
                || (privacyAllowsAppFiltering && !allowAppFiltering)
                || (privacyAllowsHandoffFiltering && !allowHandoffFiltering))
        privacyAllowsFiltering = allowFiltering
        privacyAllowsAppFiltering = allowAppFiltering
        privacyAllowsHandoffFiltering = allowHandoffFiltering
        privacyAllowsSearch = allowSearch
        privacyShowsSourceApps = showSourceApps
        if !allowSearch { resetProtectedSearch() }
        if resetFilters { protectedFilter?(.reset) }
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
        guard let index = protectedIndex(of: id) else { return nil }
        let card = latestState.cards[index]
        return card.sourceKey == nil ? localized("Unknown") : card.sourceLabel
    }

    private func resetProtectedSearch(force: Bool = false) {
        protectedSearchDebounce.cancel()
        let hadQuery = !protectedQuery.isEmpty
        protectedQuery = ""
        if hadQuery || force { protectedSearch?("") }
    }

    private struct ProtectedRows {
        let ids: [UUID]
        let indices: [UUID: Int]

        init(_ cards: [CardViewState]) {
            ids = cards.map(\.id)
            indices = Dictionary(zip(ids, ids.indices), uniquingKeysWith: { first, _ in first })
        }
    }

    private var cachedProtectedRows: ProtectedRows?
    private var protectedRows: ProtectedRows {
        if let cachedProtectedRows { return cachedProtectedRows }
        let rows = ProtectedRows(latestState.cards)
        cachedProtectedRows = rows
        return rows
    }
    var protectedCardIDs: [UUID] {
        guard isProtected else { return [] }
        return panelVisible ? protectedRows.ids : latestState.cards.map(\.id)
    }
    private func protectedIndex(of id: UUID) -> Int? {
        panelVisible ? protectedRows.indices[id] : latestState.cards.firstIndex { $0.id == id }
    }
    var protectedCardCount: Int { latestState.cards.count }
    func containsProtectedCard(_ id: UUID) -> Bool { isProtected && protectedIndex(of: id) != nil }

    func protectedSourceKeys(in range: Range<Int>) -> Set<String> {
        guard isProtected, privacyAllowsAppFiltering else { return [] }
        let lower = min(max(0, range.lowerBound), latestState.cards.count)
        let upper = min(max(lower, range.upperBound), latestState.cards.count)
        return Set(latestState.cards[lower..<upper].compactMap(\.sourceKey))
    }

    func setSpotlightAllowed(_ allowed: Bool) { allowsSpotlight = allowed }
    var contentCacheVisibility: (Bool) -> Void = { _ in }
    func setPanelVisible(_ visible: Bool) {
        if !visible {
            cachedProtectedRows = nil
            if historyHidingOptionsOpen { historyHidingOptions = nil }
        }
        panelVisible = visible
        contentCacheVisibility(visible)
    }

    func spotlightPayload(for id: UUID) -> Payload? {
        guard privacyInteractions.hover == .preview else { return nil }
        return protectedRevealPayload(for: id)
    }

    func protectedRevealPayload(for id: UUID) -> Payload? {
        guard isProtected, allowsSpotlight, panelVisible, containsProtectedCard(id) else { return nil }
        guard let item = detailSource?(id), !item.pinnedMetadata.hidesContent else { return nil }
        return item.payload
    }
    @Published private(set) var previewItems: [ClipboardItem] = []
    @Published var expandedVersions = false
    @Published var pendingAction: CardAction?
    @Published private(set) var editingError: String?
    @Published var editingRichText: NSAttributedString?
    @Published var appFilterTrigger = AppFilterTrigger.click
    @Published var privacyInteractions = InteractionBindings(singleClick: .none, doubleClick: .none, rightClick: .menu)
    var protectedExport: ((UUID, CardAction) -> Void)?

    func protectedVersions(for id: UUID) -> [UUID] {
        guard isProtected, panelVisible, let index = protectedRows.indices[id] else { return [] }
        let card = latestState.cards[index]
        return card.variantIDs.isEmpty ? [id] : card.variantIDs
    }

    func exportWhileProtected(cardID: UUID, versionID: UUID, action: CardAction) {
        guard isProtected, panelVisible, action == .copy || action == .paste,
            protectedVersions(for: cardID).contains(versionID)
        else { return }
        protectedExport?(versionID, action)
    }

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
        if cardMenuOpen, let menuPreviewCard { return menuPreviewCard }
        if case .hover(let id) = previewOrigin { return state.cards.first { $0.id == id } }
        return state.selectedCard
    }

    func setPrivacy(_ protected: Bool) {
        let changed = protected != isProtected
        if changed {
            cachedProtectedRows = nil
            if historyHidingOptionsOpen { historyHidingOptions = nil }
        }
        sensitiveSession.setProtected(protected)
        isProtected = protected
        resetProtectedSearch(force: changed)
        if changed { protectedFilter?(.reset) }
        if protected { dismissPreview(); closeSplitSessions() }
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
        guard let card = previewCard, !card.contentHidden else { dismissPreview(); return }
        let ids = card.variantIDs.isEmpty ? [card.id] : card.variantIDs
        previewItems = (detailsSource?(ids) ?? ids.compactMap { detailSource?($0) }).filter {
            !$0.pinnedMetadata.hidesContent
        }
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
        let hidden = latestState.cards.first(where: { $0.id == card.id })?.contentHidden ?? card.contentHidden
        if hidden, action == .preview || action == .edit { return }
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
        case .split:
            let current = latestState.cards.first(where: { $0.id == card.id }) ?? card
            guard !hidden, !current.isSplitGroup, current.transformable else { return }
            actions.split(card.id)
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
                do {
                    let text = item.payload.searchableText ?? ""
                    let rich = try item.richText.map { RichTextCodec.decode(try $0.read(), fallback: text) }
                    beginEditing(card)
                    guard editing != nil else { return }
                    editingID = id
                    editingText = text
                    editingRichText = rich
                } catch {
                    editingError = localized("The rich text could not be saved.")
                }
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
        guard !isProtected, !card.isSplitGroup, !card.contentHidden,
            detailSource?(card.id)?.pinnedMetadata.hidesContent != true,
            card.transformable
        else { return }
        do {
            editingRichText = try detailSource?(card.id)?.richText.map {
                RichTextCodec.decode(try $0.read(), fallback: Self.editableText(of: card))
            }
        } catch {
            editingError = localized("The rich text could not be saved.")
            return
        }
        editingID = card.id
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
        case .image, .storedImage, .files: return ""
        }
    }

    /// The card's side in points; the selected card grows by the zoom.
    @Published private(set) var cardSide: CGFloat = 200
    @Published private(set) var filterTagScale: Double = GeneralSettingsStore.defaultFilterTagScale
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

    func configureFilterTags(scale: Double) {
        filterTagScale = GeneralSettingsStore.boundedFilterTagScale(scale)
    }

    func update(_ newState: HistoryViewState) {
        cachedProtectedRows = nil
        if newState.isHistoryHidden != isHistoryHidden || newState.historyHidingCutoff != historyHidingCutoff
            || newState.typeHidingRule != typeHidingRule
        {
            historyVisibilityRevision += 1
        }
        if newState.selectedID != latestState.selectedID { pendingAction = nil; expandedVersions = false }
        latestState = newState
        validateSplitSessions()
        if let id = editingID, newState.cards.first(where: { $0.id == id })?.contentHidden != false { endEditing() }
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

    /// A panel action, never an export. Dismiss heavy previews before deletion.
    var canClearHistory: Bool {
        panelVisible && !isProtected && !isPinnedWorkspace && editing == nil && latestState.canClearHistory
    }

    var isHistoryHidden: Bool { latestState.isHistoryHidden }
    var isTypeHistoryHidden: Bool { latestState.isTypeHistoryHidden }
    var historyHidingCutoff: Date? { latestState.historyHidingCutoff }
    var typeHidingRule: HistoryHidingRule? { latestState.typeHidingRule }

    var reservesHiddenFilterRow: Bool {
        (isHistoryHidden || isTypeHistoryHidden) && (!isProtected || allowsProtectedFiltering)
    }

    var canToggleHistoryVisibility: Bool {
        panelVisible && !isPinnedWorkspace && editing == nil && !pinMetadataEditing && !cardMenuOpen
            && (latestState.canHideHistory || isHistoryHidden || isTypeHistoryHidden)
    }

    func clearHistory(actions: PanelActions) {
        guard canClearHistory else { return }
        dismissPreview()
        pendingAction = nil
        expandedVersions = false
        actions.clearHistory()
    }

    func toggleHistoryVisibility(actions: PanelActions) {
        guard canToggleHistoryVisibility else { return }
        historyHidingOptions = nil
        prepareHistoryHidingChange()
        actions.toggleHistoryVisibility()
    }

    func toggleTypeHistoryVisibility(actions: PanelActions) {
        guard canToggleHistoryVisibility else { return }
        if isTypeHistoryHidden {
            historyHidingOptions = nil
            clearTypeHistoryHiding(actions: actions)
        } else {
            historyHidingOptions = .typeOrSource
        }
    }

    func setHistoryHiding(_ rule: HistoryHidingRule, actions: PanelActions) {
        guard canToggleHistoryVisibility, rule.categories?.isEmpty != true || rule.includesHandoff else { return }
        prepareHistoryHidingChange()
        actions.setHistoryHiding(rule)
    }

    func clearTypeHistoryHiding(actions: PanelActions) {
        guard canToggleHistoryVisibility, isTypeHistoryHidden else { return }
        prepareHistoryHidingChange()
        actions.clearTypeHistoryHiding()
    }

    private func prepareHistoryHidingChange() {
        dismissPreview()
        closeSplitSessions()
        pendingAction = nil
        expandedVersions = false
    }

    /// The panel just went away: the rail rewinds to its leading edge
    /// while nobody is looking, so every open starts at position zero
    /// with no visible travel.
    func panelDidClose() {
        closeSplitSessions()
        pinMetadataEditing = false
        cardMenuOpen = false
        dismissPreview()
        hoveredCards = []
        setPanelVisible(false)
        resetProtectedSearch()
        if isProtected { protectedFilter?(.reset) }
        sensitiveSession.setPanelVisible(false)
        closeRevision += 1
    }
}

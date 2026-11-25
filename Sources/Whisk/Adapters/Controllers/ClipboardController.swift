// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

/// One step of keyboard navigation through the visible cards.
enum SelectionMove {
    case previous
    case next
}

/// The two ends a jump can land on — the whole rail or the whole chip row.
enum SelectionEdge {
    case start
    case end
}

/// Which region of the panel the keyboard is steering. The chip row is a
/// single zone — pinned, applications and categories are groups inside it,
/// crossed with plain arrows.
enum PanelZone {
    case chips
    case cards
}

/// Which way the rail and the chip row flow. Left and right arrows are
/// visual: they mirror in a right-to-left layout.
enum LayoutDirection {
    case leftToRight
    case rightToLeft
}

/// A key-arrow press, routed by the controller to a zone change (up/down)
/// or a move within the focused zone (left/right).
enum ArrowDirection {
    case up
    case down
    case left
    case right
}

/// Translates UI and OS events into use case invocations and hands each
/// result to the presenter. Owns the current history, search query and
/// keyboard selection; generic over its gateways, like the use cases it
/// drives. A storage failure is logged and the in-memory state keeps
/// working.
final class ClipboardController<Board: Pasteboard, Time: Clock, Store: HistoryStore, Log: Logger> {
    private var history: History {
        didSet { hiddenLinksNeedRefresh = true }
    }
    private var query = ""
    private var searchMatchMode: SearchMatchMode
    private var activeSourceKeys: Set<String> = []
    private var handoffOnly = false
    private var activeCategories: Set<ContentCategory> = []
    private var filterCategoryOrder: FilterCategoryOrder
    private var pinnedOnly = false
    private var pinnedWorkspace = false
    /// A presentation-only cutoff, retained until toggled off or the app exits.
    private var historyHidingRule: HistoryHidingRule?
    private var typeHidingRule: HistoryHidingRule?
    private var activePinTags: Set<PinTagColor> = []
    private var retention: RetentionPolicy
    private(set) var secretRecognition: SecretRecognition
    /// When the oldest unpinned item crosses the age limit. Any mutation
    /// re-arms it for the next tick: an unpin or a capture can change
    /// which item expires first.
    private var nextExpiry: Date = .distantPast
    private var isPaused = false
    private var captureGeneration: UInt64 = 0
    private var asyncReadInFlight = false
    private var excludedBundleIDs: Set<String> = []
    private var sensitiveBundleIDs: Set<String> = []
    var retainSensitive: (PasteboardSnapshot) -> Void = { _ in }
    var didRecord: () -> Void = {}
    private var hiddenLinksNeedRefresh = true
    private(set) var hiddenLinkAddresses: Set<String> = []
    var hiddenLinksChanged: (Set<String>) -> Void = { _ in } {
        didSet { hiddenLinksChanged(hiddenLinkAddresses) }
    }

    private func refreshHiddenLinksIfNeeded() {
        guard hiddenLinksNeedRefresh else { return }
        hiddenLinksNeedRefresh = false
        var addresses: Set<String> = []
        for item in history.items {
            if case .link(let url) = item.payload,
                item.pinnedMetadata.hidesContent || secretRecognition.recognizes(item)
            {
                addresses.insert(url.absoluteString)
            }
        }
        guard addresses != hiddenLinkAddresses else { return }
        hiddenLinkAddresses = addresses
        hiddenLinksChanged(addresses)
    }
    /// The access state the panel last saw; a change re-presents on its own,
    /// since granting access in System Settings mutates nothing else.
    private var presentedAccess: PasteboardAccess = .granted
    private var pasteStack: [UUID] = []
    private var selectedID: UUID?
    private var focusZone: PanelZone = .cards
    /// Focus anchors to the chip's identity: toggling a filter reshapes
    /// the row, and an index would land the cursor on a different chip.
    private var focusedChipID: String?
    private var focusedChipIndex = 0
    private var layoutDirection: LayoutDirection = .leftToRight
    /// The chip row and the rail as of the last refresh. Every input they
    /// derive from changes only through methods that end in refresh, so a
    /// key press reads them instead of filtering the history again.
    private var selectedFilterSources: [SourceApp] = []
    private var cachedChips: [ChipEntry] = []
    private var visibleCopyDates: [Date] = []
    private var visibleIDs: [UUID] = []
    private var lastPresentation: HistoryViewState?
    private var presentationValidFrom = Date.distantFuture
    private var presentationExpiresAt = Date.distantPast

    private let splitStore: Store
    var requestGroupSelection: (UUID, Bool, Bool) -> Void = { _, _, _ in }

    private let capture: CaptureClipboardChange<Board, Time, Store>
    private let selectItem: SelectItem<Board, Time, Store>
    private let togglePinItem: TogglePin<Store>
    private let deleteItem: DeleteItem<Store>
    private let deleteMatching: DeleteMatching<Store>
    private let editItem: EditItem<Store>
    private let restoreHistory: RestoreHistory<Store>
    private let clearUnpinned: ClearHistory<Store>
    /// The history as it stood before each deletion, clear or edit, newest
    /// last; a session's worth, since pins and pastes lose nothing.
    /// What an undo entry remembers: the snapshot itself, plus which ids'
    /// content left the store during the change it must restore.
    private struct UndoEntry {
        let history: History
        let contentIDs: Set<UUID>
    }
    private var undoStack: [UndoEntry] = []
    private static var undoDepth: Int { 20 }
    private let enforceRetention: EnforceRetention<Store>
    private let filterHistory = FilterHistory()
    private let presenter: HistoryPresenter
    private let clock: Time
    private let pasteboard: Board
    private let logger: Log
    private let present: (HistoryViewState) -> Void

    /// The presenter's preview cache size, for the tests that watch it.
    var presenterCacheCount: Int { presenter.cachedPreviewCount }

    /// The retention policy shapes the history from the first load: a
    /// history rebuilt at the default capacity would evict what a roomier
    /// setting had kept, and the next save would make that permanent.
    /// A validated startup snapshot skips the extra store read, including
    /// when the snapshot is empty; it is not retained as a separate cache.
    init(
        pasteboard: Board,
        store: Store,
        clock: Time,
        retention: RetentionPolicy = .standard,
        initialItems: [ClipboardItem]? = nil,
        searchMatchMode: SearchMatchMode = .fuzzy,
        secretRecognition: SecretRecognition = .init(),
        filterCategoryOrder: FilterCategoryOrder = .standard,
        presenter: HistoryPresenter = HistoryPresenter(),
        logger: Log,
        present: @escaping (HistoryViewState) -> Void
    ) {
        self.splitStore = store
        self.clock = clock
        self.presenter = presenter
        self.pasteboard = pasteboard
        self.logger = logger
        self.present = present
        self.retention = retention
        self.searchMatchMode = searchMatchMode
        self.secretRecognition = secretRecognition
        self.filterCategoryOrder = filterCategoryOrder
        presentedAccess = pasteboard.access
        capture = CaptureClipboardChange(pasteboard: pasteboard, clock: clock, store: store)
        selectItem = SelectItem(pasteboard: pasteboard, clock: clock, store: store)
        togglePinItem = TogglePin(store: store)
        deleteItem = DeleteItem(store: store)
        deleteMatching = DeleteMatching(store: store)
        editItem = EditItem(store: store)
        restoreHistory = RestoreHistory(store: store)
        clearUnpinned = ClearHistory(store: store)
        enforceRetention = EnforceRetention(store: store)
        do {
            if let initialItems {
                history = History(items: initialItems, capacity: retention.capacity)
            } else {
                history = try LoadHistory(store: store, capacity: retention.capacity)()
            }
        } catch {
            logger.log(.historyLoadFailed)
            history = History(capacity: retention.capacity)
        }
        refresh()
    }

    /// Production polling keeps potentially remote pasteboard reads off the UI thread.
    func pollTick() {
        if pasteboard.access != presentedAccess {
            presentedAccess = pasteboard.access
            refresh()
        }
        if retention.maxAge != nil, clock.now() >= nextExpiry {
            enforceRetentionNow()
        }
        guard !asyncReadInFlight else { return }
        asyncReadInFlight = true
        let generation = captureGeneration
        pasteboard.readIfChangedAsync { [weak self] snapshot in
            guard let self else { return }
            self.asyncReadInFlight = false
            if self.pasteboard.access != self.presentedAccess {
                self.presentedAccess = self.pasteboard.access
                self.refresh()
            }
            if generation == self.captureGeneration, !self.isPaused, let snapshot {
                self.mutate {
                    try self.capture(
                        into: $0, excluding: self.excludedBundleIDs,
                        sensitiveBundleIDs: self.sensitiveBundleIDs,
                        retainSensitive: self.retainSensitive, didRecord: self.didRecord,
                        snapshot: snapshot)
                }
            }
        }
    }

    /// Whether the system lets Whisk read what is copied.
    var clipboardAccess: PasteboardAccess {
        pasteboard.access
    }

    /// Triggers the system's one-time question about pasteboard access,
    /// after which the user can allow Whisk for good in System Settings.
    func requestClipboardAccess() {
        pasteboard.requestAccess()
        presentedAccess = pasteboard.access
        refresh()
    }

    /// Suspends or resumes capture; everything else keeps working.
    func setPaused(_ paused: Bool) {
        guard isPaused != paused else { return }
        captureGeneration &+= 1
        isPaused = paused
        pasteboard.setCapturePaused(paused)
    }

    /// The arrows follow the direction the interface reads in.
    func setLayoutDirection(_ direction: LayoutDirection) {
        layoutDirection = direction
    }

    /// Applications whose copies must never be recorded.
    func applyExclusions(_ bundleIDs: Set<String>) {
        excludedBundleIDs = bundleIDs
    }

    func applySensitiveSources(_ bundleIDs: Set<String>) {
        sensitiveBundleIDs = bundleIDs
    }

    /// Applies a new retention policy immediately and keeps enforcing it.
    func applyRetention(_ policy: RetentionPolicy) {
        guard policy != retention || history.capacity != policy.capacity || clock.now() >= nextExpiry else { return }
        retention = policy
        enforceRetentionNow()
    }

    private func enforceRetentionNow() {
        let previous = history
        do {
            history = try enforceRetention(history, policy: retention, now: clock.now())
        } catch {
            logger.log(.historyRetentionFailed)
        }
        nextExpiry = earliestExpiry()
        guard history != previous else { return }
        presenter.prune(keeping: Set(history.items.map(\.id)))
        refresh()
    }

    // The poll skips retention until then rather than re-walking the
    // whole history four times a second.
    private func earliestExpiry() -> Date {
        guard let maxAge = retention.maxAge,
            let oldest = history.items.lazy.filter({ !$0.isPinned }).map(\.copiedAt).min()
        else { return .distantFuture }
        return oldest.addingTimeInterval(maxAge)
    }

    /// Pastes the card at a rail position (⌘1…⌘9). Returns false when the
    /// position is empty.
    @discardableResult
    func activate(at index: Int) -> Bool {
        let items = visibleIDs
        guard items.indices.contains(index) else { return false }
        return select(items[index], forPaste: true)
    }

    func refreshLocalization() {
        presenter.invalidateLocalizedLabels()
        refresh()
    }

    func search(_ newQuery: String) {
        query = newQuery
        selectedID = nil
        // Only the matching rows depend on the search text.
        refreshRows(in: displayedHistory)
    }

    func setFilterCategoryOrder(_ order: FilterCategoryOrder) {
        guard order != filterCategoryOrder else { return }
        filterCategoryOrder = order
        refresh()
    }

    func setSecretRecognition(_ options: SecretRecognition) {
        guard options != secretRecognition else { return }
        if secretRecognition.enabled != options.enabled { hiddenLinksNeedRefresh = true }
        secretRecognition = options
        refresh()
    }

    func setSearchMatchMode(_ mode: SearchMatchMode, query: String) {
        searchMatchMode = mode
        search(query)
    }

    /// Hover switches to one reachable application instead of accumulating filters.
    func selectSourceFilter(_ key: String) {
        guard
            chipEntries.contains(where: {
                if case .app = $0 { return $0.id == key }; return false
            }),
            activeSourceKeys != [key] || handoffOnly
        else { return }
        activeSourceKeys = [key]
        handoffOnly = false
        selectedID = nil
        refresh()
    }

    /// Click toggles a source application; several may be active at once (OR).
    func toggleSourceFilter(_ key: String) {
        guard
            chipEntries.contains(where: {
                if case .app = $0 { return $0.id == key }; return false
            })
        else { return }
        handoffOnly = false
        if activeSourceKeys.remove(key) == nil {
            activeSourceKeys.insert(key)
        }
        selectedID = nil
        refresh()
    }

    /// Hover selects a reachable chip without toggling off an active filter.
    func selectCategoryFilter(_ key: String) {
        guard let entry = chipEntries.first(where: { $0.id == key }) else { return }
        switch entry {
        case .all:
            guard
                !activeSourceKeys.isEmpty || !activeCategories.isEmpty || !activePinTags.isEmpty || pinnedOnly
                    || handoffOnly
            else {
                return
            }
            activeSourceKeys = []
            handoffOnly = false
            activeCategories = []
            activePinTags = []
            pinnedOnly = false
        case .pinned:
            guard !pinnedOnly else { return }
            pinnedOnly = true
        case .handoff:
            guard !handoffOnly else { return }
            handoffOnly = true
            activeSourceKeys = []
        case .category(let category):
            guard activeCategories != [category] else { return }
            activeCategories = [category]
        case .tag(let tag):
            guard activePinTags != [tag] else { return }
            activePinTags = [tag]
        case .app: return
        }
        selectedID = nil
        refresh()
    }

    /// Adds a content category to the filter, or removes it when already
    /// selected — or toggles the pinned filter when given the pinned chip.
    func toggleCategoryFilter(_ rawCategory: String) {
        if rawCategory == handoffChipID {
            guard chipEntries.contains(.handoff) else { return }
            handoffOnly.toggle()
            if handoffOnly { activeSourceKeys = [] }
            selectedID = nil
            refresh()
            return
        }
        if let tag = PinTagColor.allCases.first(where: { $0.filterKey == rawCategory }) {
            if activePinTags.remove(tag) == nil { activePinTags.insert(tag) }
            selectedID = nil
            refresh()
            return
        }
        if rawCategory == allFiltersChipID {
            activePinTags = []
            activeSourceKeys = []
            handoffOnly = false
            activeCategories = []
            pinnedOnly = false
            selectedID = nil
            refresh()
            return
        }
        if rawCategory == pinnedChipID {
            pinnedOnly.toggle()
            selectedID = nil
            refresh()
            return
        }
        guard let category = ContentCategory(rawValue: rawCategory) else { return }
        if activeCategories.remove(category) == nil {
            activeCategories.insert(category)
        }
        selectedID = nil
        refresh()
    }

    func item(for id: UUID) -> ClipboardItem? {
        history.items.first { $0.id == id }
    }

    /// The ordinary shortcut resets search and chip filters, but keeps temporary hiding rules.
    /// Count formatted variants as one slot without materializing their original bytes.
    func openingThumbnailItems(slotLimit: Int) -> [ClipboardItem] {
        var remaining = slotLimit
        var groups = Set<String>()
        var result: [ClipboardItem] = []
        for item in history.items {
            guard remaining > 0 else { break }
            guard isVisibleInMainHistory(item) else { continue }
            if let key = RichTextGroups.groupingKey(for: item), !groups.insert(key).inserted { continue }
            remaining -= 1
            guard !item.pinnedMetadata.hidesContent else { continue }
            switch item.payload {
            case .image, .storedImage, .fileReferences: result.append(item)
            default: break
            }
        }
        return result
    }

    private func isVisibleInMainHistory(_ item: ClipboardItem) -> Bool {
        historyHidingRule?.hides(item, recognition: secretRecognition) != true
            && typeHidingRule?.hides(item, recognition: secretRecognition) != true
    }

    func items(for ids: [UUID]) -> [ClipboardItem] {
        let wanted = Set(ids)
        let found = Dictionary(
            uniqueKeysWithValues: history.items.filter { wanted.contains($0.id) }.map { ($0.id, $0) })
        return ids.compactMap { found[$0] }
    }

    func editRich(_ id: UUID, text: String, rtf: Data) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let old = item(for: id), old.splitGroup == nil
        else { return }
        remember(contentIDs: [id])
        mutate { history in
            let replacement = ClipboardItem(
                id: id, payload: .text(text), source: old.source, copiedAt: old.copiedAt,
                isPinned: old.isPinned, rtf: rtf, pinnedMetadata: old.pinnedMetadata, splitSourceID: old.splitSourceID)
            let next = History(items: history.items.map { $0.id == id ? replacement : $0 }, capacity: history.capacity)
            return try self.restoreHistory(next, changedContentIDs: [id])
        }
    }

    @discardableResult
    func select(_ id: UUID, plain: Bool = false, forPaste: Bool = false) -> Bool {
        guard let item = item(for: id) else { return false }
        if item.splitGroup != nil {
            requestGroupSelection(id, plain, forPaste)
            return false
        }
        return mutate { try selectItem(id, in: $0, plain: plain, forPaste: forPaste) }
    }

    func assessSplit(_ request: SplitSaveRequest) throws -> SplitSaveAssessment {
        if let item = item(for: request.source.id), secretRecognition.masks(item) { throw SplitFailure.unavailable }
        return try SaveSplit.prepare(request, in: history, policy: retention, now: clock.now())
    }

    func saveSplit(_ request: SplitSaveRequest, confirmEviction: Bool) throws {
        let assessment = try assessSplit(request)
        guard assessment.evictedCount == 0 || confirmEviction else { throw SplitFailure.needsEvictionConfirmation }
        let previous = history
        let next = assessment.history
        let previousIDs = Set(previous.items.map(\.id))
        let nextIDs = Set(next.items.map(\.id))
        do {
            try splitStore.save(next.items, changedContentIDs: nextIDs.subtracting(previousIDs))
        } catch { throw SplitFailure.storage }
        undoStack.append(UndoEntry(history: previous, contentIDs: previousIDs.subtracting(nextIDs)))
        if undoStack.count > Self.undoDepth { undoStack.removeFirst() }
        history = History(items: try splitStore.compact(next.items), capacity: next.capacity)
        nextExpiry = .distantPast
        refresh()
    }

    func exportGroup(
        _ expected: ClipboardItem, selected: Set<UUID>, original: Bool, plain: Bool, forPaste: Bool,
        combine: ([SplitPart], Bool) throws -> (Payload, Data?)
    ) throws {
        guard item(for: expected.id) == expected, let group = expected.splitGroup else { throw SplitFailure.stale }
        let output: (Payload, Data?)
        if original {
            guard selected.isEmpty else { throw SplitFailure.noSelection }
            output = (try expected.payload.materialized(), try (plain ? nil : expected.richText?.read()))
        } else {
            let parts = group.parts.filter { selected.contains($0.id) }
            guard !parts.isEmpty, parts.count == selected.count else { throw SplitFailure.noSelection }
            output = try combine(parts, plain || group.plainText)
        }
        if forPaste {
            pasteboard.writeForPaste(output.0, rtf: output.1)
        } else {
            pasteboard.write(output.0, rtf: output.1)
        }
        let next = history.selecting(expected.id, at: clock.now())
        try splitStore.save(next.items, changedContentIDs: [])
        history = next
        refresh()
    }

    /// Puts a rewritten copy of the card's text on the pasteboard. False
    /// when the card holds no text the transform can read — nothing is
    /// written then, so the caller keeps the panel open.
    @discardableResult
    func select(_ id: UUID, transform: TextTransform) -> Bool {
        guard let item = history.items.first(where: { $0.id == id }), item.splitGroup == nil,
            !secretRecognition.masks(item), let text = item.payload.transformableText,
            let rewritten = transform.apply(to: text)
        else { return false }
        return mutate { try selectItem(id, in: $0, writing: .text(rewritten), forPaste: true) }
    }

    /// Moves the keyboard selection through the visible cards, clamped at
    /// both ends. refresh keeps the selection on a visible card, so a miss
    /// can only mean an empty rail.
    func moveSelection(_ step: SelectionMove) {
        let items = visibleIDs
        guard let current = selectedID, let index = items.firstIndex(of: current) else { return }
        let destination = step == .next ? min(index + 1, items.count - 1) : max(index - 1, 0)
        selectedID = items[destination]
        presentFocus()
    }

    /// Jumps the keyboard focus to either end of whatever zone holds it.
    func jumpSelection(to edge: SelectionEdge) {
        switch focusZone {
        case .cards:
            let items = visibleIDs
            guard !items.isEmpty else { return }
            selectedID = edge == .start ? items.first : items.last
        case .chips:
            let chips = chipEntries
            guard !chips.isEmpty else { return }
            focusedChipID = (edge == .start ? chips.first : chips.last)?.id
        }
        presentFocus()
    }

    /// Moves the keyboard selection onto a specific visible card, e.g. the
    /// one under the pointer. Selects only — nothing is written back.
    func highlight(_ id: UUID) {
        guard id != selectedID || focusZone != .cards else { return }
        guard visibleIDs.contains(id) else { return }
        selectedID = id
        focusZone = .cards
        presentFocus()
    }

    /// Moves the keyboard focus onto a specific app chip, e.g. the one
    /// under the pointer — the mouse and the arrows share one focus.
    func focusSourceChip(_ key: String) {
        focusChip(id: key)
    }

    /// Moves the keyboard focus onto a specific kind chip (or the pinned
    /// chip).
    func focusCategoryChip(_ chipID: String) {
        focusChip(id: chipID)
    }

    private func focusChip(id: String) {
        guard chipEntries.contains(where: { $0.id == id }) else { return }
        guard focusZone != .chips || focusedChipID != id else { return }
        focusZone = .chips
        focusedChipID = id
        presentFocus()
    }

    /// The focused chip's current position, resolved by identity first and
    /// by the last known index when the chip vanished.
    private func resolvedChipIndex(in chips: [ChipEntry]) -> Int {
        if let id = focusedChipID, let index = chips.firstIndex(where: { $0.id == id }) {
            return index
        }
        return max(0, min(focusedChipIndex, chips.count - 1))
    }

    /// Up and down move between the chip row and the rail; left and right
    /// move within whichever zone holds the focus.
    func navigate(_ direction: ArrowDirection) {
        switch direction {
        case .left, .right:
            let forward = (direction == .right) == (layoutDirection == .leftToRight)
            navigateHorizontally(forward ? 1 : -1)
        case .up:
            if focusZone == .cards, !chipEntries.isEmpty {
                focusZone = .chips
            }
            presentFocus()
        case .down:
            focusZone = .cards
            presentFocus()
        }
    }

    /// Jumps to the start of the next chip group (All → pinned → apps →
    /// categories, cyclically) — the fast lane next to arrowing across
    /// the separators.
    func switchChipGroup() {
        let chips = chipEntries
        let starts = chipGroupStarts
        guard !starts.isEmpty, !chips.isEmpty else { return }
        if focusZone != .chips {
            focusZone = .chips
            focusedChipID = chips[starts[0]].id
        } else {
            let index = resolvedChipIndex(in: chips)
            let current = starts.lastIndex { $0 <= index } ?? 0
            focusedChipID = chips[starts[(current + 1) % starts.count]].id
        }
        presentFocus()
    }

    // The chip groups share one visual row: arrowing simply walks the row,
    // crossing the separators.
    private func navigateHorizontally(_ step: Int) {
        switch focusZone {
        case .cards:
            moveSelection(step > 0 ? .next : .previous)
        case .chips:
            let chips = chipEntries
            guard !chips.isEmpty else { return }
            let destination = max(0, min(resolvedChipIndex(in: chips) + step, chips.count - 1))
            focusedChipID = chips[destination].id
            presentFocus()
        }
    }

    /// Acts on whatever holds the keyboard focus. Returns true only when a
    /// card was put back on the pasteboard — the caller closes the panel
    /// then, and stays open for chip toggles.
    @discardableResult
    func activateFocused(plain: Bool = false) -> Bool {
        switch focusZone {
        case .cards:
            return activateSelected(plain: plain, forPaste: true)
        case .chips:
            let chips = chipEntries
            guard !chips.isEmpty else { return false }
            switch chips[resolvedChipIndex(in: chips)] {
            case .all:
                toggleCategoryFilter(allFiltersChipID)
            case .pinned:
                toggleCategoryFilter(pinnedChipID)
            case .handoff:
                toggleCategoryFilter(handoffChipID)
            case .app(let source):
                toggleSourceFilter(source.filterKey)
            case .category(let category):
                toggleCategoryFilter(category.rawValue)
            case .tag(let tag):
                toggleCategoryFilter(tag.filterKey)
            }
            return false
        }
    }

    /// Puts the highlighted card back on the pasteboard; the first visible
    /// card counts as highlighted until the selection is stepped.
    @discardableResult
    func activateSelected(plain: Bool = false, forPaste: Bool = false) -> Bool {
        guard let id = selectedID ?? visibleIDs.first else { return false }
        return select(id, plain: plain, forPaste: forPaste)
    }

    /// Queues the highlighted card, or removes it when already queued; the
    /// global paste-next shortcut then pops the queue one item per press.
    func stackSelected() {
        guard let id = selectedID else { return }
        toggleStack(id)
    }

    /// Queues a card, or removes it when already queued.
    func toggleStack(_ id: UUID) {
        guard history.items.contains(where: { $0.id == id && $0.splitGroup == nil }) else { return }
        if let index = pasteStack.firstIndex(of: id) {
            pasteStack.remove(at: index)
        } else {
            pasteStack.append(id)
        }
        refresh()
    }

    /// Writes the next queued payload to the pasteboard. Deleted items are
    /// skipped; returns false once the queue is exhausted.
    @discardableResult
    func popStack() -> Bool {
        while !pasteStack.isEmpty {
            let id = pasteStack.removeFirst()
            if let item = history.items.first(where: { $0.id == id && $0.splitGroup == nil }) {
                do {
                    pasteboard.writeForPaste(try item.payload.materialized(), rtf: try item.richText?.read())
                    refresh()
                    return true
                } catch {
                    pasteStack.insert(id, at: 0)
                    logger.log(.pasteStackReadFailed)
                    return false
                }
            }
        }
        refresh()
        return false
    }

    func updatePinnedMetadata(_ id: UUID, value: PinnedMetadata) {
        guard let item = item(for: id), item.isPinned, item.pinnedMetadata != value.normalized else { return }
        mutate { history in
            let next = history.updatingPinnedMetadata(id, value: value)
            _ = try self.restoreHistory(next, changedContentIDs: [])
            self.undoStack = self.undoStack.map { entry in
                UndoEntry(
                    history: History(
                        items: entry.history.items.map { $0.id == id ? $0.withPinnedMetadata(value) : $0 },
                        capacity: entry.history.capacity),
                    contentIDs: entry.contentIDs)
            }
            return next
        }
    }

    func openPinnedWorkspace(locked: Bool) {
        pinnedWorkspace = locked
        pinnedOnly = true
        query = ""
        activeSourceKeys = []
        handoffOnly = false
        activeCategories = []
        activePinTags = []
        selectedID = nil
        refresh()
    }

    func togglePin(_ id: UUID) {
        mutate { try togglePinItem(id, in: $0) }
    }

    func togglePinSelected() {
        guard let id = selectedID else { return }
        togglePin(id)
    }

    func delete(_ id: UUID) {
        // Deleting the selection keeps the cursor in place: the neighbor
        // below slides into the hole and inherits the selection (the one
        // above when the last card goes).
        if id == selectedID {
            let items = visibleIDs
            if let index = items.firstIndex(of: id) {
                let successor =
                    index + 1 < items.count
                    ? items[index + 1]
                    : (index > 0 ? items[index - 1] : nil)
                selectedID = successor
            }
        }
        remember(contentIDs: [id])
        mutate { try deleteItem(id, in: $0) }
    }

    func deleteSelected() {
        guard let id = selectedID else { return }
        delete(id)
    }

    func clear() {
        guard !pinnedWorkspace else { return }
        remember(contentIDs: Set(history.items.filter { !$0.isPinned }.map(\.id)))
        mutate { try clearUnpinned($0) }
    }

    func toggleHistoryVisibility() {
        guard !pinnedWorkspace, historyHidingRule != nil || !history.items.isEmpty else { return }
        historyHidingRule = historyHidingRule == nil ? HistoryHidingRule(cutoff: clock.now()) : nil
        refreshAfterHidingChange()
    }

    func setHistoryHiding(_ rule: HistoryHidingRule) {
        guard !pinnedWorkspace, !history.items.isEmpty, rule.cutoff.timeIntervalSince1970.isFinite,
            rule.categories?.isEmpty != true || rule.includesHandoff
        else { return }
        let bounded = HistoryHidingRule(
            cutoff: min(rule.cutoff, clock.now()), categories: rule.categories, includesHandoff: rule.includesHandoff)
        if rule.categories == nil {
            historyHidingRule = bounded
        } else {
            typeHidingRule = bounded
        }
        refreshAfterHidingChange()
    }

    func clearTypeHistoryHiding() {
        guard !pinnedWorkspace, typeHidingRule != nil else { return }
        typeHidingRule = nil
        refreshAfterHidingChange()
    }

    private func refreshAfterHidingChange() {
        selectedID = nil
        focusZone = .cards
        refresh()
    }

    /// Replaces a card's text with what the user rewrote.
    func edit(_ id: UUID, text: String) {
        remember(contentIDs: [id])
        mutate { try editItem(id, text: text, in: $0) }
    }

    /// Removes every unpinned card copied from one application.
    func deleteAll(fromSource key: String) {
        guard !pinnedWorkspace else { return }
        remember(contentIDs: Set(history.items.filter { !$0.isPinned && $0.source?.filterKey == key }.map(\.id)))
        mutate { try deleteMatching({ $0.source?.filterKey == key }, in: $0) }
    }

    /// Puts the history back as it stood before the last deletion, clear
    /// or edit. False when there is nothing left to undo.
    @discardableResult
    func undo() -> Bool {
        guard let entry = undoStack.last else { return false }
        guard mutate({ _ in try restoreHistory(entry.history, changedContentIDs: entry.contentIDs) }) else {
            return false
        }
        undoStack.removeLast()
        return true
    }

    private func remember(contentIDs: Set<UUID>) {
        undoStack.append(UndoEntry(history: history, contentIDs: contentIDs))
        if undoStack.count > Self.undoDepth {
            undoStack.removeFirst()
        }
    }

    func setContentCacheEnabled(_ enabled: Bool) { splitStore.setContentCacheEnabled(enabled) }

    func releaseContentCache() { splitStore.releaseContentCache() }

    func panelWillShow() {
        let reusable =
            !pinnedWorkspace && activePinTags.isEmpty && query.isEmpty
            && activeSourceKeys.isEmpty && !handoffOnly && activeCategories.isEmpty && !pinnedOnly
            && focusZone == .cards
            && pasteboard.access == presentedAccess
        pinnedWorkspace = false
        activePinTags = []
        query = ""
        activeSourceKeys = []
        handoffOnly = false
        activeCategories = []
        pinnedOnly = false
        selectedID = nil
        focusZone = .cards
        focusedChipID = nil
        focusedChipIndex = 0
        if reusable, lastPresentation != nil {
            selectedID = visibleIDs.first
            presentFocus()
            return
        }
        refresh()
    }

    // One chip per application: deduplicated leniently (items recorded
    // before bundle ids existed carry a name only), preferring the variant
    // that has a bundle id so the chip gets an icon.
    private func distinctSources(of items: [ClipboardItem]) -> [SourceApp] {
        var chips: [SourceApp] = []
        var firstByBundle: [String: Int] = [:]
        var legacyByName: [String: Int] = [:]
        var names: Set<String> = []
        for item in items {
            guard let source = item.source, source.origin == .observedApplication else { continue }
            if let bundle = source.bundleID {
                // A legacy name and a bundle ID can both match. Preserve the
                // first chip's priority, including after an application rename.
                if let name = source.name, let index = legacyByName[name],
                    index < (firstByBundle[bundle] ?? chips.count)
                {
                    chips[index] = source
                    legacyByName[name] = nil
                    firstByBundle[bundle] = index
                    continue
                }
                guard firstByBundle[bundle] == nil else { continue }
                firstByBundle[bundle] = chips.count
                if let name = source.name { names.insert(name) }
            } else {
                guard let name = source.name, names.insert(name).inserted else { continue }
                legacyByName[name] = chips.count
            }
            chips.append(source)
        }
        return chips
    }

    /// What the chip row derives from the history under the current
    /// filters, computed once per refresh.
    private struct Facets {
        let sources: [SourceApp]
        let categories: [ContentCategory]
        let activeCategories: Set<ContentCategory>
        let hasPinned: Bool
        let hasHandoff: Bool
    }

    // Each facet narrows what the OTHER displays — selecting image hides
    // the apps that never produced an image, selecting Spotify hides the
    // categories Spotify never yielded — but an ACTIVE chip is never
    // hidden, so a selection can never be dropped by ricochet. Impossible
    // combinations are unreachable because their chips vanish before they
    // can be clicked. Active categories only fall when a history mutation
    // (deletion, eviction) makes them impossible.
    private func computeFacets(in history: History, active: [SourceApp]) -> Facets {
        let underApps = filterHistory(
            history,
            filter: HistoryFilter(
                sources: active, pinnedOnly: pinnedOnly || pinnedWorkspace, tags: activePinTags,
                handoffOnly: handoffOnly), recognition: secretRecognition)
        var reachable = Set(underApps.lazy.map { self.secretRecognition.category(of: $0) })
        let parents = reachable.compactMap(\.parentCategory)
        reachable.formUnion(parents)
        let activeCategories = self.activeCategories.intersection(reachable)
        let underCategories = filterHistory(
            history,
            filter: HistoryFilter(
                categories: activeCategories, pinnedOnly: pinnedOnly || pinnedWorkspace, tags: activePinTags),
            recognition: secretRecognition)
        let scopedSources = distinctSources(of: underCategories)
        let strayActives = active.filter { stray in !scopedSources.contains { $0.filterKey == stray.filterKey } }
        let pinScope = HistoryFilter(sources: active, categories: activeCategories, handoffOnly: handoffOnly)
        let hasPinned = history.items.contains { $0.isPinned && pinScope.includes($0, recognition: secretRecognition) }
        return Facets(
            sources: scopedSources + strayActives,
            categories: filterCategoryOrder.categories.filter(reachable.contains),
            activeCategories: activeCategories,
            hasPinned: hasPinned,
            hasHandoff: handoffOnly || underCategories.contains { $0.source?.origin == .handoffMarker }
        )
    }

    /// The row the keyboard steers — the same list the presenter renders.
    private var chipEntries: [ChipEntry] {
        cachedChips
    }

    /// First flat index of each chip group actually present, for ⌃⇥.
    private var chipGroupStarts: [Int] {
        var starts: [Int] = []
        var previous: ChipGroup?
        for (index, chip) in chipEntries.enumerated() where chip.group != previous {
            starts.append(index)
            previous = chip.group
        }
        return starts
    }

    private func activeSources(in history: History) -> [SourceApp] {
        guard !activeSourceKeys.isEmpty else { return [] }
        return distinctSources(of: history.items).filter { activeSourceKeys.contains($0.filterKey) }
    }

    private func currentFilter(sources: [SourceApp]) -> HistoryFilter {
        HistoryFilter(
            query: query,
            searchMatchMode: searchMatchMode,
            sources: sources,
            categories: activeCategories,
            pinnedOnly: pinnedOnly || pinnedWorkspace,
            tags: activePinTags,
            handoffOnly: handoffOnly
        )
    }

    @discardableResult
    private func mutate(_ transform: (History) throws -> History) -> Bool {
        let previous = history
        do {
            history = try transform(history)
        } catch {
            logger.log(.historyMutationFailed)
            return false
        }
        guard history != previous else { return true }
        presenter.prune(keeping: Set(history.items.map(\.id)))
        nextExpiry = .distantPast
        refresh()
        return true
    }

    private var displayedHistory: History {
        // Filter before facets, grouping and keyboard selection. Storage and
        // retention keep the complete history, including temporarily hidden cards.
        if (historyHidingRule != nil || typeHidingRule != nil), !pinnedWorkspace {
            return History(
                items: history.items.filter(isVisibleInMainHistory), capacity: history.capacity)
        }
        return history
    }

    private func refresh() {
        refreshHiddenLinksIfNeeded()
        let displayedHistory = self.displayedHistory
        // App keys survive as long as the app exists in the history at all.
        if !activeSourceKeys.isEmpty {
            var remaining: Set<String> = []
            for item in displayedHistory.items {
                guard let source = item.source, source.origin == .observedApplication,
                    activeSourceKeys.contains(source.filterKey)
                else { continue }
                remaining.insert(source.filterKey)
                if remaining.count == activeSourceKeys.count { break }
            }
            activeSourceKeys = remaining
        }
        if handoffOnly, !displayedHistory.items.contains(where: { $0.source?.origin == .handoffMarker }) {
            handoffOnly = false
        }
        var pinnedTags: Set<PinTagColor> = []
        for item in displayedHistory.items where item.isPinned {
            pinnedTags.formUnion(item.pinnedMetadata.tags)
        }
        if (historyHidingRule != nil || typeHidingRule != nil), !pinnedWorkspace {
            activePinTags.formIntersection(pinnedTags)
        }
        let sources = activeSources(in: displayedHistory)
        var facets = computeFacets(in: displayedHistory, active: sources)
        if pinnedOnly, !facets.hasPinned {
            pinnedOnly = false
            facets = computeFacets(in: displayedHistory, active: sources)
        }
        activeCategories = facets.activeCategories
        cachedChips = ChipEntry.row(
            hasPinned: facets.hasPinned, sources: facets.sources, categories: facets.categories,
            tags: PinTagColor.allCases.filter(pinnedTags.contains), hasHandoff: facets.hasHandoff)
        focusedChipIndex = resolvedChipIndex(in: cachedChips)
        focusedChipID = cachedChips.indices.contains(focusedChipIndex) ? cachedChips[focusedChipIndex].id : nil
        if focusZone == .chips, cachedChips.isEmpty {
            focusZone = .cards
        }
        selectedFilterSources = sources
        if !pasteStack.isEmpty {
            let eligible = Set(history.items.lazy.filter { $0.splitGroup == nil }.map(\.id))
            pasteStack.removeAll { !eligible.contains($0) }
        }
        refreshRows(in: displayedHistory)
    }

    private func refreshRows(in displayedHistory: History) {
        let visible = filterHistory(
            displayedHistory, filter: currentFilter(sources: selectedFilterSources), recognition: secretRecognition)
        let groups = RichTextGroups.groups(visible)
        visibleIDs = groups.indices.map { groups.item(at: $0).id }
        visibleCopyDates = groups.indices.map { groups.item(at: $0).copiedAt }
        if selectedID.map(visibleIDs.contains) != true {
            selectedID = visibleIDs.first
        }
        presentHistory(items: visible, groups: groups, now: clock.now())
    }

    /// Cursor moves reuse the filtered rows, including the active hiding rules.
    private func presentFocus() {
        focusedChipIndex = resolvedChipIndex(in: cachedChips)
        focusedChipID = cachedChips.indices.contains(focusedChipIndex) ? cachedChips[focusedChipIndex].id : nil
        if cachedChips.isEmpty { focusZone = .cards }
        let now = clock.now()
        guard let previous = lastPresentation, presentedAccess == pasteboard.access else {
            refresh()
            return
        }
        let card = focusZone == .cards ? selectedID : nil
        let chip = focusZone == .chips ? focusedChipID : nil
        let changedChip = previous.filters.focusedChipID != chip
        let expired = now < presentationValidFrom || now >= presentationExpiresAt
        guard expired || changedChip || previous.selectedID != card else { return }
        var next = previous.selecting(card, filters: changedChip ? presenter.filterBar(from: filterContext) : nil)
        if expired {
            presentationExpiresAt = presenter.refreshTimes(
                in: &next, dates: visibleCopyDates, from: presentationValidFrom, now: now)
            presentationValidFrom = now
        }
        lastPresentation = next
        present(next)
    }

    private var filterContext: FilterContext {
        FilterContext(
            chips: cachedChips, activeSourceKeys: activeSourceKeys, activeCategories: activeCategories,
            pinnedOnly: pinnedOnly || pinnedWorkspace, focusedChipID: focusZone == .chips ? focusedChipID : nil,
            activeTags: activePinTags, handoffOnly: handoffOnly)
    }

    private func presentHistory(items: [ClipboardItem], groups: RichTextGroups.Rows, now: Date) {
        let state = presenter.present(
            items: items,
            query: query,
            searchMatchMode: searchMatchMode,
            now: now,
            // One cursor at a time: while the chip row holds it, no
            // card wears the ring — the selection itself survives for
            // the way back down.
            selectedID: focusZone == .cards ? selectedID : nil,
            stack: pasteStack,
            filters: filterContext,
            clipboardAccess: pasteboard.access,
            canClearHistory: history.items.contains { !$0.isPinned },
            isHistoryHidden: historyHidingRule != nil && !pinnedWorkspace,
            canHideHistory: !pinnedWorkspace && !history.items.isEmpty,
            historyHidingCutoff: pinnedWorkspace ? nil : historyHidingRule?.cutoff,
            typeHidingRule: pinnedWorkspace ? nil : typeHidingRule, groups: groups, recognition: secretRecognition
        )
        presentedAccess = pasteboard.access
        lastPresentation = state
        presentationValidFrom = now
        presentationExpiresAt = visibleCopyDates.reduce(Date.distantFuture) { earliest, date in
            min(earliest, HistoryPresenter.nextTimeChange(copiedAt: date, now: now))
        }
        present(state)
    }
}

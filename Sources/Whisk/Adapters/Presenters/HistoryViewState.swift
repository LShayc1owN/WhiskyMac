// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

/// Display-ready state for the history panel. Views render this verbatim;
/// all formatting decisions were made by the presenter.
struct HistoryViewState: Equatable {
    private(set) var cards: [CardViewState]
    let countLabel: String
    let query: String
    let searchMatchMode: SearchMatchMode
    private(set) var selectedID: UUID?
    private(set) var selectedCardIndex: Int?
    let stackCount: Int
    /// Reflects all history, including items hidden by search or filters.
    let canClearHistory: Bool
    let isHistoryHidden: Bool
    let canHideHistory: Bool
    let historyHidingCutoff: Date?
    let typeHidingRule: HistoryHidingRule?
    var isTypeHistoryHidden: Bool { typeHidingRule != nil }
    private(set) var filters: FilterBarViewState
    /// What the rail says when it has no card to show; nil while it has.
    let emptyMessage: String?
    /// What to tell the user while the system keeps Whisk from reading the
    /// pasteboard, and the button that leads to the fix; nil once allowed.
    let accessPrompt: AccessPromptViewState?

    init(
        cards: [CardViewState],
        countLabel: String,
        query: String,
        searchMatchMode: SearchMatchMode = .fuzzy,
        selectedID: UUID?,
        stackCount: Int = 0,
        filters: FilterBarViewState,
        emptyMessage: String? = nil,
        accessPrompt: AccessPromptViewState? = nil,
        canClearHistory: Bool = false,
        isHistoryHidden: Bool = false,
        canHideHistory: Bool = false,
        historyHidingCutoff: Date? = nil,
        typeHidingRule: HistoryHidingRule? = nil
    ) {
        self.cards = cards
        self.countLabel = countLabel
        self.query = query
        self.searchMatchMode = searchMatchMode
        self.selectedID = selectedID
        selectedCardIndex = cards.firstIndex(where: \.isSelected)
        self.stackCount = stackCount
        self.canClearHistory = canClearHistory
        self.isHistoryHidden = isHistoryHidden
        self.canHideHistory = canHideHistory
        self.historyHidingCutoff = historyHidingCutoff
        self.typeHidingRule = typeHidingRule
        self.filters = filters
        self.emptyMessage = emptyMessage
        self.accessPrompt = accessPrompt
    }

    /// The card the preview overlay follows.
    var selectedCard: CardViewState? {
        selectedCardIndex.map { cards[$0] }
    }

    mutating func updateTime(at index: Int, label: String, accessibilityValue: String) {
        cards[index].timeLabel = label
        cards[index].accessibilityValue = accessibilityValue
    }

    static let empty = HistoryViewState(
        cards: [],
        countLabel: localized("\(0) items"),
        query: "",
        selectedID: nil,
        filters: .empty,
        emptyMessage: localized("Copy something to get started")
    )

    /// Resetting the cursor changes two cards, not their previews, labels,
    /// rich-text groups or filter facets. The original bytes stay deferred.
    func selecting(_ id: UUID?, filters newFilters: FilterBarViewState? = nil) -> HistoryViewState {
        guard selectedID != id || newFilters != nil else { return self }
        var next = self
        if selectedID != id {
            if let previous = selectedCardIndex { next.cards[previous].isSelected = false }
            next.selectedID = id
            next.selectedCardIndex = id.flatMap { id in cards.firstIndex { $0.id == id } }
            if let index = next.selectedCardIndex { next.cards[index].isSelected = true }
        }
        if let newFilters { next.filters = newFilters }
        return next
    }
}

/// The notice shown while the pasteboard cannot be read, with the button
/// that opens the way to allowing it.
struct AccessPromptViewState: Equatable {
    let message: String
    let buttonTitle: String
}

/// The chip bar, in display order: All, the pinned toggle, one
/// independent origins, source applications and content categories — all adapted to
/// what the current selection can still match.
struct FilterBarViewState: Equatable {
    let all: [FilterChip]
    let pinned: [FilterChip]
    let apps: [FilterChip]
    let kinds: [FilterChip]
    let tags: [FilterChip]
    let origins: [FilterChip]
    let focusedChipID: String?
    let activeChipIDs: [String]

    init(
        all: [FilterChip] = [], pinned: [FilterChip] = [], apps: [FilterChip], kinds: [FilterChip],
        tags: [FilterChip] = [], origins: [FilterChip] = []
    ) {
        self.all = all
        self.pinned = pinned
        self.apps = apps
        self.kinds = kinds
        self.tags = tags
        self.origins = origins
        let groups = [all, pinned, origins, apps, kinds, tags]
        focusedChipID = groups.lazy.compactMap { $0.first(where: \.isFocused)?.id }.first
        activeChipIDs = groups.flatMap { $0.compactMap { $0.isActive ? $0.id : nil } }
    }

    var isEmpty: Bool {
        all.isEmpty && pinned.isEmpty && origins.isEmpty && apps.isEmpty && kinds.isEmpty && tags.isEmpty
    }

    var orderedChips: [FilterChip] {
        let groups: [[FilterChip]] = [all, pinned, origins, apps, kinds, tags]
        return groups.flatMap { $0 }
    }

    static let empty = FilterBarViewState(apps: [], kinds: [])
}

/// What a chip wears before its label. App chips carry their app's icon
/// through `sourceBundleID` instead and have none.
enum ChipIcon: Equatable {
    case symbol(String)
    /// A bundled image by resource name, with a symbol to fall back on
    /// when the bundle lacks it.
    case resource(String, fallback: String)
}

struct FilterChip: Equatable, Identifiable {
    let id: String
    let label: String
    let sourceBundleID: String?
    let icon: ChipIcon?
    /// What VoiceOver reads: the label plus the group the chip filters on.
    let accessibilityLabel: String
    let isActive: Bool
    let isFocused: Bool

    init(
        id: String, label: String, sourceBundleID: String?, icon: ChipIcon? = nil, accessibilityLabel: String,
        isActive: Bool, isFocused: Bool
    ) {
        self.id = id
        self.label = label
        self.sourceBundleID = sourceBundleID
        self.icon = icon
        self.accessibilityLabel = accessibilityLabel
        self.isActive = isActive
        self.isFocused = isFocused
    }
}

/// One rendered clipboard entry.
struct CardViewState: Equatable, Identifiable {
    let id: UUID
    let sourceLabel: String
    let sourceBundleID: String?
    let kindLabel: String
    let kindSymbol: String
    var timeLabel: String
    /// Extra footer fact, e.g. the character count of textual payloads.
    let detailLabel: String?
    let isPinned: Bool
    var isSelected: Bool
    /// 1-based rank in the paste stack, nil when the card isn't queued.
    let stackPosition: Int?
    /// What VoiceOver reads for the whole card: source, kind, a one-line
    /// summary of the content. The icons and texts inside are decorative.
    let accessibilityLabel: String
    /// The card's state for VoiceOver: pin, paste-stack rank, age.
    var accessibilityValue: String
    /// What leaves the app when the card is dragged out.
    let dragPayload: DragPayload
    /// Whether the card holds text a paste-time transform can rewrite.
    let transformable: Bool
    /// Whether "Save As…" applies: files already live on disk.
    let saveable: Bool
    /// The filter key of the card's application, for "delete all from"
    /// and the exclusion; nil for a card without a source.
    let sourceKey: String?
    /// Where the query's words landed in a textual preview, for the view
    /// to underline; empty without a live query.
    let matches: [MatchSpan]
    /// Opaque bytes; decoded only by mounted rich-text card views.
    let richText: BinaryContent?
    let preview: CardPreview
    var splitCount = 0
    var isSplitGroup: Bool { splitCount > 0 }
    var pinnedMetadata = PinnedMetadata()
    var contentHidden: Bool { pinnedMetadata.hidesContent }
    var variantIDs: [UUID] = []

    init(
        id: UUID,
        sourceLabel: String,
        sourceBundleID: String?,
        kindLabel: String,
        kindSymbol: String = "text.alignleft",
        timeLabel: String,
        detailLabel: String? = nil,
        isPinned: Bool,
        isSelected: Bool,
        stackPosition: Int? = nil,
        accessibilityLabel: String,
        accessibilityValue: String,
        dragPayload: DragPayload,
        transformable: Bool = false,
        saveable: Bool = false,
        sourceKey: String? = nil,
        matches: [MatchSpan] = [],
        preview: CardPreview,
        pinnedMetadata: PinnedMetadata = PinnedMetadata(), splitCount: Int = 0, richText: BinaryContent? = nil
    ) {
        self.id = id
        self.sourceLabel = sourceLabel
        self.sourceBundleID = sourceBundleID
        self.kindLabel = kindLabel
        self.kindSymbol = kindSymbol
        self.timeLabel = timeLabel
        self.detailLabel = detailLabel
        self.isPinned = isPinned
        self.isSelected = isSelected
        self.stackPosition = stackPosition
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.dragPayload = dragPayload
        self.transformable = transformable
        self.saveable = saveable
        self.sourceKey = sourceKey
        self.matches = matches
        self.preview = preview
        self.richText = richText
        self.pinnedMetadata = pinnedMetadata
        self.splitCount = splitCount
    }
}

/// A stretch of preview text the query matched, in UTF-16 offsets like a
/// CodeToken, so views apply attributes without re-parsing.
struct MatchSpan: Equatable {
    let start: Int
    let length: Int
}

/// What a dragged card hands to the drop target — the item itself, never
/// a detail of how the card happens to be drawn.
enum DragPayload: Equatable {
    case text(String)
    case link(URL)
    case image(Data)
    case storedImage(StoredBytes)
    case files([String])
}

/// What a card shows, decided by the presenter. Image bytes stay opaque.
enum CardPreview: Equatable {
    case text(String)
    case code(text: String, tokens: [CodeToken])
    case color(code: String, rgb: RGB)
    case link(String)
    case image(Data)
    case storedImage(StoredBytes)
    case files(names: [String], overflow: Int, thumbnailPath: String?)
}

/// Framework-free color components in the 0...1 range.
struct RGB: Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

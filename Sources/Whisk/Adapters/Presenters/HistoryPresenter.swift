// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

/// Stable identities for the row-wide reset and pinned filters.
let pinnedChipID = "pinned"
let allFiltersChipID = "all-filters"
let handoffChipID = SourceApp.handoffFilterKey

/// The groups of the chip row, in display order.
enum ChipGroup: Equatable {
    case all
    case pinned
    case origins
    case apps
    case kinds
    case tags
}

/// One chip of the filter row. The row's order is decided in `row` alone:
/// the controller steers the keyboard along that list and the presenter
/// renders it, so an index can never land on a chip other than the one
/// drawn.
enum ChipEntry: Equatable {
    case all
    case pinned
    case handoff
    case app(SourceApp)
    case category(ContentCategory)
    case tag(PinTagColor)

    var id: String {
        switch self {
        case .all: allFiltersChipID
        case .pinned: pinnedChipID
        case .handoff: handoffChipID
        case .app(let source): source.filterKey
        case .category(let category): category.rawValue
        case .tag(let tag): tag.filterKey
        }
    }

    var group: ChipGroup {
        switch self {
        case .all: .all
        case .pinned: .pinned
        case .handoff: .origins
        case .app: .apps
        case .category: .kinds
        case .tag: .tags
        }
    }

    /// All, pinned, Handoff, observed applications, content types, then tags.
    static func row(
        hasPinned: Bool, sources: [SourceApp], categories: [ContentCategory], tags: [PinTagColor] = [],
        hasHandoff: Bool = false
    )
        -> [ChipEntry]
    {
        let origins: [ChipEntry] =
            hasHandoff || sources.contains(where: { $0.origin == .handoffMarker }) ? [.handoff] : []
        let apps = sources.filter { $0.origin == .observedApplication }.map(ChipEntry.app)
        let groups: [[ChipEntry]] = [
            hasPinned ? [.pinned] : [], origins, apps, categories.map(ChipEntry.category), tags.map(ChipEntry.tag),
        ]
        let entries = groups.flatMap { $0 }
        return entries.isEmpty ? [] : [.all] + entries
    }
}

/// What the controller knows about filtering, handed over for the chip
/// bar: the row as steered, which chips are active, and which one holds
/// the keyboard cursor.
struct FilterContext: Equatable {
    let chips: [ChipEntry]
    let activeSourceKeys: Set<String>
    let activeCategories: Set<ContentCategory>
    let pinnedOnly: Bool
    let focusedChipID: String?
    var activeTags: Set<PinTagColor> = []
    var handoffOnly: Bool

    init(
        chips: [ChipEntry] = [],
        activeSourceKeys: Set<String> = [],
        activeCategories: Set<ContentCategory> = [],
        pinnedOnly: Bool = false,
        focusedChipID: String? = nil,
        activeTags: Set<PinTagColor> = [],
        handoffOnly: Bool = false
    ) {
        self.chips = chips
        self.activeSourceKeys = activeSourceKeys
        self.activeCategories = activeCategories
        self.pinnedOnly = pinnedOnly
        self.focusedChipID = focusedChipID
        self.activeTags = activeTags
        self.handoffOnly = handoffOnly
    }

    static let empty = FilterContext()
}

/// Maps kernel entities to display-ready view state. Pure in behaviour —
/// time comes in as a value, never read from the system — with memoization
/// underneath: previews (regex tokenization, color parsing) and minute-
/// grained time labels are cached per immutable item, so a selection move
/// re-renders in microseconds instead of re-running regexes on 60 cards.
/// Past the limit a cache keeps only the items being presented, so what
/// is on screen never has to be recomputed and what was deleted is let go.
final class HistoryPresenter {
    /// A memoized preview and the text it was drawn from: editing keeps a
    /// card's identity and changes its text, so identity alone cannot
    /// vouch for the cache.
    private struct CachedPreview {
        let text: String?
        let preview: CardPreview
        let characterCount: Int?
    }

    /// A single presentation often formats the same category and footer hundreds of times.
    /// Sharing these strings within the batch also keeps a language change self-contained.
    private struct CardLabels {
        private var kinds: [ContentCategory: String] = [:]
        private var counts: [Int: String] = [:]

        mutating func kind(_ category: ContentCategory) -> String {
            if let label = kinds[category] { return label }
            let label = HistoryPresenter.kindLabel(category)
            kinds[category] = label
            return label
        }

        mutating func characterCount(_ count: Int?) -> String? {
            guard let count else { return nil }
            if let label = counts[count] { return label }
            let label = localized("\(count) characters")
            counts[count] = label
            return label
        }
    }

    private var previewCache: [UUID: CachedPreview] = [:]
    private lazy var relativeFormatter = Self.makeRelativeFormatter()
    private var timeCache: [UUID: (bucket: Int, label: String)] = [:]
    private var presentedIDs: Set<UUID> = []
    private var previewPruned = false
    private var timePruned = false
    private let cacheLimit = 2048
    private(set) var cachePrunePasses = 0

    init() {}

    func invalidateLocalizedLabels() {
        timeCache = [:]
        relativeFormatter.locale = AppLocalization.interfaceLocale
    }

    /// Drops cached previews and time labels for ids that no longer exist
    /// in the history — a deleted image must not keep its bytes resident.
    func prune(keeping validIDs: Set<UUID>) {
        previewCache = previewCache.filter { validIDs.contains($0.key) }
        timeCache = timeCache.filter { validIDs.contains($0.key) }
    }

    /// How many previews are held back, for the tests that watch the purge.
    var cachedPreviewCount: Int {
        previewCache.count
    }

    func present(
        items: [ClipboardItem],
        query: String,
        now: Date,
        selectedID: UUID? = nil,
        stack: [UUID] = [],
        filters: FilterContext = .empty,
        clipboardAccess: PasteboardAccess = .granted,
        canClearHistory: Bool? = nil,
        isHistoryHidden: Bool = false,
        canHideHistory: Bool? = nil,
        historyHidingCutoff: Date? = nil,
        typeHidingRule: HistoryHidingRule? = nil, groups preparedGroups: [[ClipboardItem]]? = nil
    ) -> HistoryViewState {
        // Prune lazily on a miss, at most once per cache for this entire
        // presentation. Cache hits under a search need no eviction, and a
        // large cold presentation must not filter its cache once per card.
        presentedIDs = Set(items.map(\.id))
        previewPruned = false
        timePruned = false
        let accessPrompt = Self.accessPrompt(for: clipboardAccess)
        let words = ParsedQuery(query).words
        let groups = preparedGroups ?? RichTextGroups.groups(items)
        var labels = CardLabels()
        let stackPositions = Dictionary(zip(stack, 1...), uniquingKeysWith: { first, _ in first })
        return HistoryViewState(
            cards: groups.map { group in
                let item = group[0]
                var result = card(
                    for: item, now: now, isSelected: group.contains { $0.id == selectedID },
                    stackPosition: stackPositions[item.id], words: words, labels: &labels)
                result.variantIDs = group.map(\.id)
                return result
            },
            countLabel: countLabel(groups.count),
            query: query,
            selectedID: selectedID,
            stackCount: stack.count,
            filters: filterBar(from: filters),
            emptyMessage: items.isEmpty && accessPrompt == nil
                ? Self.emptyMessage(
                    query: query, filters: filters, isHistoryHidden: isHistoryHidden || typeHidingRule != nil) : nil,
            accessPrompt: accessPrompt,
            canClearHistory: canClearHistory ?? items.contains { !$0.isPinned },
            isHistoryHidden: isHistoryHidden, canHideHistory: canHideHistory ?? !items.isEmpty,
            historyHidingCutoff: historyHidingCutoff, typeHidingRule: typeHidingRule
        )
    }

    /// While the system stands between Whisk and the pasteboard, the panel
    /// says so and offers the way out; the message replaces the invitation
    /// to copy, which nothing could honour.
    private static func accessPrompt(for access: PasteboardAccess) -> AccessPromptViewState? {
        switch access {
        case .granted:
            nil
        case .requiresConsent:
            AccessPromptViewState(
                message: localized("WhiskyMac needs your permission to read what you copy."),
                buttonTitle: localized("Allow Clipboard Access"))
        case .denied:
            AccessPromptViewState(
                message: localized("WhiskyMac is not allowed to read the clipboard."),
                buttonTitle: localized("Open Pasteboard Settings"))
        }
    }

    /// An empty rail either invites the first copy or reports that the
    /// query and chips matched nothing.
    private static func emptyMessage(query: String, filters: FilterContext, isHistoryHidden: Bool) -> String {
        let narrowed =
            !query.isEmpty || !filters.activeSourceKeys.isEmpty || !filters.activeCategories.isEmpty
            || filters.pinnedOnly
        if !narrowed, isHistoryHidden {
            return localized("Older cards are temporarily hidden. New copies will appear here.")
        }
        return narrowed ? localized("No matches") : localized("Copy something to get started")
    }

    static func sourceLabel(_ source: SourceApp?) -> String? {
        guard let source else { return nil }
        if source.origin == .handoffMarker { return localized("Handoff") }
        return source.name ?? source.bundleID
    }

    private func card(
        for item: ClipboardItem, now: Date, isSelected: Bool, stackPosition: Int?, words: [FuzzyMatch.Pattern],
        labels: inout CardLabels
    ) -> CardViewState {
        let kind = labels.kind(item.category)
        let source = Self.sourceLabel(item.source) ?? kind.capitalized
        let time = timeLabel(id: item.id, copiedAt: item.copiedAt, now: now)
        let hidden = item.pinnedMetadata.hidesContent
        if hidden { previewCache[item.id] = nil }
        let cached = hidden ? nil : preview(for: item)
        let cardPreview = cached?.preview ?? .text(Self.hiddenSummary(item.payload))
        let spoken = Self.accessibilityLabel(source: source, kind: kind, preview: cardPreview)
        let note = item.pinnedMetadata.note
        return CardViewState(
            id: item.id,
            sourceLabel: source,
            sourceBundleID: item.source?.bundleID,
            kindLabel: kind,
            kindSymbol: item.category.symbolName,
            timeLabel: time,
            detailLabel: labels.characterCount(cached?.characterCount),
            isPinned: item.isPinned,
            isSelected: isSelected,
            stackPosition: stackPosition,
            accessibilityLabel: note.isEmpty ? spoken : note + ", " + spoken,
            accessibilityValue: Self.accessibilityValue(
                pinned: item.isPinned, tags: item.pinnedMetadata.tags, stackPosition: stackPosition, time: time),
            dragPayload: hidden ? .text("") : Self.dragPayload(of: item),
            transformable: !hidden && item.splitGroup == nil && item.payload.transformableText != nil,
            saveable: {
                if hidden || item.splitGroup != nil { return false }
                if case .fileReferences = item.payload { return false }
                return true
            }(),
            sourceKey: item.source?.filterKey,
            matches: hidden ? [] : Self.matchSpans(of: words, in: item),
            preview: cardPreview,
            pinnedMetadata: item.pinnedMetadata, splitCount: item.splitGroup?.parts.count ?? 0,
            richText: !hidden && item.category != .image ? item.richText : nil
        )
    }

    static func hiddenSummary(_ payload: Payload) -> String {
        guard case .link(let url) = payload else { return "••••••••" }
        let scheme = url.scheme ?? "https"
        let parts = url.host?.split(separator: ".") ?? []
        let suffix = parts.count > 1 ? parts.last.map(String.init) : nil
        let tld = suffix.flatMap { $0.allSatisfy({ $0.isLetter || $0 == "-" }) ? $0 : nil }
        return scheme + "://••••••" + (tld.map { "." + $0 } ?? "")
    }

    /// Card layout and highlights share an excerpt; explicit actions keep the full payload.
    private static let textPreviewLimit = 1024

    private static func matchSpans(of words: [FuzzyMatch.Pattern], in item: ClipboardItem) -> [MatchSpan] {
        guard !words.isEmpty, case .text(let value) = item.payload else { return [] }
        let scanned = value.prefix(textPreviewLimit)
        var hits: Set<Int> = []
        for word in words {
            if let positions = word.match(in: scanned)?.positions {
                hits.formUnion(positions)
            }
        }
        guard let lastHit = hits.max() else { return [] }
        var spans: [MatchSpan] = []
        var utf16Offset = 0
        var runStart: Int?
        for (offset, character) in scanned.enumerated() {
            if hits.contains(offset) {
                if runStart == nil { runStart = utf16Offset }
            } else if let start = runStart {
                spans.append(MatchSpan(start: start, length: utf16Offset - start))
                runStart = nil
            }
            utf16Offset += character.utf16.count
            if offset == lastHit { break }
        }
        if let start = runStart {
            spans.append(MatchSpan(start: start, length: utf16Offset - start))
        }
        return spans
    }

    // A color travels as its code alone, the way the swatch shows it.
    private static func dragPayload(of item: ClipboardItem) -> DragPayload {
        switch item.payload {
        case .text(let value):
            return .text(item.category == .color ? value.trimmingCharacters(in: .whitespacesAndNewlines) : value)
        case .link(let url):
            return .link(url)
        case .image(let data):
            return .image(data)
        case .storedImage(let reference):
            return .storedImage(reference)
        case .fileReferences(let paths):
            return .files(paths)
        }
    }

    private static func accessibilityLabel(source: String, kind: String, preview: CardPreview) -> String {
        var parts = [source, kind]
        if let summary = summary(of: preview) {
            parts.append(summary)
        }
        return parts.joined(separator: ", ")
    }

    private static let summaryLimit = 140

    /// One spoken line per card: whitespace collapsed, long text cut short.
    private static func summary(of preview: CardPreview) -> String? {
        switch preview {
        case .text(let value), .code(let value, _):
            let collapsed = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !collapsed.isEmpty else { return nil }
            return collapsed.count > summaryLimit ? String(collapsed.prefix(summaryLimit)) + "…" : collapsed
        case .color(let code, _):
            return code
        case .link(let address):
            return address
        case .image, .storedImage:
            return nil
        case .files(let names, let overflow, _):
            return (names + (overflow > 0 ? [localized("+ \(overflow) more")] : [])).joined(separator: ", ")
        }
    }

    private static func accessibilityValue(
        pinned: Bool, tags: Set<PinTagColor>, stackPosition: Int?, time: String
    ) -> String {
        guard pinned || !tags.isEmpty || stackPosition != nil else { return time }
        var parts: [String] = []
        if pinned {
            parts.append(localized("Pinned card"))
        }
        parts.append(contentsOf: PinTagColor.allCases.filter(tags.contains).map(tagLabel))
        if let stackPosition {
            parts.append(localized("Paste stack position \(stackPosition)"))
        }
        parts.append(time)
        return parts.joined(separator: ", ")
    }

    /// Textual payloads carry their size in the footer, whether or not the
    /// preview had to fade out.
    private static func characterCount(for item: ClipboardItem) -> Int? {
        guard case .text(let value) = item.payload,
            item.category == .text || item.category == .code
        else { return nil }
        return value.count
    }

    private static func kindLabel(_ category: ContentCategory) -> String {
        switch category {
        case .text: localized("text")
        case .code: localized("code")
        case .color: localized("color")
        case .link: localized("link")
        case .path: localized("path")
        case .image: localized("image")
        case .files: localized("files")
        }
    }

    private static func chipIcon(_ category: ContentCategory) -> ChipIcon {
        switch category {
        case .text: .symbol("text.alignleft")
        case .code: .symbol("chevron.left.forwardslash.chevron.right")
        case .color: .symbol("paintpalette")
        case .link: .symbol("link")
        case .path: .symbol(ContentCategory.path.symbolName)
        case .image: .symbol("photo")
        case .files: .symbol("folder")
        }
    }

    private func preview(for item: ClipboardItem) -> CachedPreview {
        // Image payloads carry the full encoded bytes. The card gets the
        // data straight from the item every time; caching here would only
        // hold a second reference past deletion, so images stay uncached.
        if item.category == .image {
            return CachedPreview(
                text: item.payload.transformableText, preview: computePreview(for: item), characterCount: nil)
        }
        if let cached = previewCache[item.id], cached.text == item.payload.transformableText {
            return cached
        }
        let cached = CachedPreview(
            text: item.payload.transformableText, preview: computePreview(for: item),
            characterCount: Self.characterCount(for: item))
        if !previewPruned, previewCache.count >= cacheLimit {
            previewCache = previewCache.filter { presentedIDs.contains($0.key) }
            previewPruned = true
            cachePrunePasses += 1
        }
        previewCache[item.id] = cached
        return cached
    }

    private func computePreview(for item: ClipboardItem) -> CardPreview {
        switch item.payload {
        case .text(let value):
            switch item.category {
            case .color:
                return colorSwatch(for: item.payload) ?? .text(value)
            case .code:
                let excerpt = String(value.prefix(Self.textPreviewLimit))
                return .code(text: excerpt, tokens: CodeHighlighter.tokens(in: excerpt))
            default:
                return .text(String(value.prefix(Self.textPreviewLimit)))
            }
        case .link(let url):
            return .link(url.absoluteString)
        case .image(let data):
            return .image(data)
        case .storedImage(let reference):
            return .storedImage(reference)
        case .fileReferences(let paths):
            let names = paths.prefix(4).map { ($0 as NSString).lastPathComponent }
            return .files(
                names: names,
                overflow: paths.count - names.count,
                thumbnailPath: paths.first
            )
        }
    }

    private func colorSwatch(for payload: Payload) -> CardPreview? {
        guard case .text(let value) = payload, let color = payload.parsedColor else { return nil }
        return .color(
            code: value.trimmingCharacters(in: .whitespacesAndNewlines),
            rgb: RGB(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        )
    }

    // The row arrives already ordered; each entry lands in its group.
    func filterBar(from context: FilterContext) -> FilterBarViewState {
        var all: [FilterChip] = []
        var pinned: [FilterChip] = []
        var origins: [FilterChip] = []
        var apps: [FilterChip] = []
        var kinds: [FilterChip] = []
        var tags: [FilterChip] = []
        for entry in context.chips {
            let isFocused = entry.id == context.focusedChipID
            switch entry {
            case .all:
                all.append(
                    FilterChip(
                        id: entry.id, label: localized("All"), sourceBundleID: nil,
                        icon: .symbol("square.grid.2x2"), accessibilityLabel: localized("All items, clear filters"),
                        isActive: context.activeSourceKeys.isEmpty && context.activeCategories.isEmpty
                            && !context.pinnedOnly && !context.handoffOnly && context.activeTags.isEmpty,
                        isFocused: isFocused))
            case .pinned:
                pinned.append(
                    FilterChip(
                        id: entry.id,
                        label: localized("Pinned"),
                        sourceBundleID: nil,
                        icon: .symbol("pin.fill"),
                        accessibilityLabel: localized("Pinned items, filter"),
                        isActive: context.pinnedOnly,
                        isFocused: isFocused
                    )
                )
            case .handoff:
                origins.append(
                    FilterChip(
                        id: entry.id, label: localized("Handoff"), sourceBundleID: nil,
                        icon: .symbol("macbook.and.iphone"),
                        accessibilityLabel: localized("Handoff, source filter"),
                        isActive: context.handoffOnly, isFocused: isFocused))
            case .app(let source):
                guard source.origin == .observedApplication else { continue }
                let label = Self.sourceLabel(source) ?? localized("Unknown")
                apps.append(
                    FilterChip(
                        id: entry.id,
                        label: label,
                        sourceBundleID: source.bundleID,
                        accessibilityLabel: localized("\(label), application filter"),
                        isActive: context.activeSourceKeys.contains(entry.id),
                        isFocused: isFocused
                    )
                )
            case .tag(let tag):
                tags.append(
                    FilterChip(
                        id: tag.filterKey, label: Self.tagLabel(tag), sourceBundleID: nil,
                        icon: .symbol("circle.fill"), accessibilityLabel: Self.tagLabel(tag),
                        isActive: context.activeTags.contains(tag), isFocused: isFocused))
            case .category(let category):
                let label = Self.kindLabel(category).capitalized
                kinds.append(
                    FilterChip(
                        id: entry.id,
                        label: label,
                        sourceBundleID: nil,
                        icon: Self.chipIcon(category),
                        accessibilityLabel: localized("\(label), kind filter"),
                        isActive: context.activeCategories.contains(category),
                        isFocused: isFocused
                    )
                )
            }
        }
        return FilterBarViewState(all: all, pinned: pinned, apps: apps, kinds: kinds, tags: tags, origins: origins)
    }

    static func tagLabel(_ color: PinTagColor) -> String {
        switch color {
        case .red: localized("Red tag")
        case .orange: localized("Orange tag")
        case .yellow: localized("Yellow tag")
        case .green: localized("Green tag")
        case .blue: localized("Blue tag")
        case .purple: localized("Purple tag")
        case .gray: localized("Gray tag")
        }
    }

    /// Sub-minute labels would churn every second and force every card to
    /// re-render on each refresh, so the first minute reads as "now";
    /// beyond it the formatter only runs when the minute bucket moves.
    static func nextTimeChange(copiedAt: Date, now: Date) -> Date {
        let bucket = floor(max(0, now.timeIntervalSince(copiedAt)) / 60)
        return copiedAt.addingTimeInterval((bucket + 1) * 60)
    }

    /// Dates follow the same representative order as the displayed cards. Only
    /// cards that crossed a minute boundary need formatting or a VoiceOver update.
    func refreshTimes(in state: inout HistoryViewState, dates: [Date], from previous: Date, now: Date) -> Date {
        var expires = Date.distantFuture
        for (index, date) in dates.enumerated() {
            let next = Self.nextTimeChange(copiedAt: date, now: now)
            expires = min(expires, next)
            guard next != Self.nextTimeChange(copiedAt: date, now: previous) else { continue }
            let card = state.cards[index]
            let time = timeLabel(id: card.id, copiedAt: date, now: now)
            guard time != card.timeLabel else { continue }
            state.updateTime(
                at: index, label: time,
                accessibilityValue: Self.accessibilityValue(
                    pinned: card.isPinned, tags: card.pinnedMetadata.tags, stackPosition: card.stackPosition, time: time
                ))
        }
        return expires
    }

    private func timeLabel(id: UUID, copiedAt: Date, now: Date) -> String {
        let age = now.timeIntervalSince(copiedAt)
        guard age >= 60 else { return localized("now") }
        let bucket = Int(age / 60)
        if let cached = timeCache[id], cached.bucket == bucket {
            return cached.label
        }
        let label = relativeFormatter.localizedString(for: copiedAt, relativeTo: now)
        if !timePruned, timeCache.count >= cacheLimit {
            timeCache = timeCache.filter { presentedIDs.contains($0.key) }
            timePruned = true
            cachePrunePasses += 1
        }
        timeCache[id] = (bucket, label)
        return label
    }

    private func countLabel(_ count: Int) -> String {
        localized("\(count) items")
    }

    private static func makeRelativeFormatter() -> RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = AppLocalization.interfaceLocale
        formatter.unitsStyle = .abbreviated
        return formatter
    }
}

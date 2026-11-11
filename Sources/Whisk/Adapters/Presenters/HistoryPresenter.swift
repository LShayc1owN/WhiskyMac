// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

/// Stable identities for the row-wide reset and pinned filters.
let pinnedChipID = "pinned"
let allFiltersChipID = "all-filters"

/// The groups of the chip row, in display order.
enum ChipGroup: Equatable {
    case all
    case pinned
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
    case app(SourceApp)
    case category(ContentCategory)
    case tag(PinTagColor)

    var id: String {
        switch self {
        case .all: allFiltersChipID
        case .pinned: pinnedChipID
        case .app(let source): source.filterKey
        case .category(let category): category.rawValue
        case .tag(let tag): tag.filterKey
        }
    }

    var group: ChipGroup {
        switch self {
        case .all: .all
        case .pinned: .pinned
        case .app: .apps
        case .category: .kinds
        case .tag: .tags
        }
    }

    /// All first, then pinned and one chip per source application,
    /// then one per content category.
    static func row(hasPinned: Bool, sources: [SourceApp], categories: [ContentCategory], tags: [PinTagColor] = [])
        -> [ChipEntry]
    {
        let entries =
            (hasPinned ? [ChipEntry.pinned] : []) + sources.map(ChipEntry.app) + categories.map(ChipEntry.category)
            + tags.map(ChipEntry.tag)
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

    init(
        chips: [ChipEntry] = [],
        activeSourceKeys: Set<String> = [],
        activeCategories: Set<ContentCategory> = [],
        pinnedOnly: Bool = false,
        focusedChipID: String? = nil,
        activeTags: Set<PinTagColor> = []
    ) {
        self.chips = chips
        self.activeSourceKeys = activeSourceKeys
        self.activeCategories = activeCategories
        self.pinnedOnly = pinnedOnly
        self.focusedChipID = focusedChipID
        self.activeTags = activeTags
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
    }

    private var previewCache: [UUID: CachedPreview] = [:]
    private var timeCache: [UUID: (bucket: Int, label: String)] = [:]
    private var presentedIDs: Set<UUID> = []
    private let cacheLimit = 2048

    init() {}

    func invalidateLocalizedLabels() { timeCache = [:] }

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
        canClearHistory: Bool? = nil
    ) -> HistoryViewState {
        presentedIDs = Set(items.map(\.id))
        let accessPrompt = Self.accessPrompt(for: clipboardAccess)
        let words = ParsedQuery(query).words
        return HistoryViewState(
            cards: RichTextGroups.groups(items).map { group in
                let item = group[0]
                var result = card(
                    for: item, now: now, isSelected: group.contains { $0.id == selectedID },
                    stackPosition: stack.firstIndex(of: item.id).map { $0 + 1 }, words: words)
                result.variantIDs = group.map(\.id)
                return result
            },
            countLabel: countLabel(RichTextGroups.groups(items).count),
            query: query,
            selectedID: selectedID,
            stackCount: stack.count,
            filters: filterBar(from: filters),
            emptyMessage: items.isEmpty && accessPrompt == nil
                ? Self.emptyMessage(query: query, filters: filters) : nil,
            accessPrompt: accessPrompt,
            canClearHistory: canClearHistory ?? items.contains { !$0.isPinned }
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
    private static func emptyMessage(query: String, filters: FilterContext) -> String {
        let narrowed =
            !query.isEmpty || !filters.activeSourceKeys.isEmpty || !filters.activeCategories.isEmpty
            || filters.pinnedOnly
        return narrowed ? localized("No matches") : localized("Copy something to get started")
    }

    static func sourceLabel(_ source: SourceApp?) -> String? {
        guard let source else { return nil }
        if source.origin == .handoffMarker { return localized("Handoff (system marker)") }
        return source.name ?? source.bundleID
    }

    private func card(
        for item: ClipboardItem, now: Date, isSelected: Bool, stackPosition: Int?, words: [String]
    ) -> CardViewState {
        let kind = Self.kindLabel(item.category)
        let source = Self.sourceLabel(item.source) ?? kind.capitalized
        let time = timeLabel(for: item, now: now)
        let hidden = item.pinnedMetadata.hidesContent
        if hidden { previewCache[item.id] = nil }
        let cardPreview: CardPreview = hidden ? .text(Self.hiddenSummary(item.payload)) : preview(for: item)
        return CardViewState(
            id: item.id,
            sourceLabel: source,
            sourceBundleID: item.source?.bundleID,
            kindLabel: kind,
            kindSymbol: item.category.symbolName,
            timeLabel: time,
            detailLabel: hidden ? nil : Self.detailLabel(for: item),
            isPinned: item.isPinned,
            isSelected: isSelected,
            stackPosition: stackPosition,
            accessibilityLabel: ([
                item.pinnedMetadata.note, Self.accessibilityLabel(source: source, kind: kind, preview: cardPreview),
            ]).filter { !$0.isEmpty }.joined(separator: ", "),
            accessibilityValue: Self.accessibilityValue(of: item, stackPosition: stackPosition, time: time),
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
            rtf: {
                if !hidden, case .text = item.payload { return item.rtf }; return nil
            }(),
            pinnedMetadata: item.pinnedMetadata, splitCount: item.splitGroup?.parts.count ?? 0
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

    /// Matching runs on the visible cards only and never on more than the
    /// preview can show; the cost is the filter's own, once more, per word.
    private static let matchScanLimit = 4000

    private static func matchSpans(of words: [String], in item: ClipboardItem) -> [MatchSpan] {
        guard !words.isEmpty, case .text(let value) = item.payload else { return [] }
        let scanned = String(value.prefix(matchScanLimit))
        var hits: Set<Int> = []
        for word in words {
            if let positions = FuzzyMatch.match(pattern: word, in: scanned)?.positions {
                hits.formUnion(positions)
            }
        }
        guard !hits.isEmpty else { return [] }
        // Character offsets to UTF-16 ones: one running offset per character.
        var utf16Offsets = [0]
        utf16Offsets.reserveCapacity(scanned.count + 1)
        for character in scanned {
            utf16Offsets.append(utf16Offsets[utf16Offsets.count - 1] + character.utf16.count)
        }
        var spans: [MatchSpan] = []
        var runStart: Int?
        var previous = -2
        for offset in hits.sorted() where offset + 1 < utf16Offsets.count {
            if offset != previous + 1 {
                if let start = runStart {
                    spans.append(
                        MatchSpan(start: utf16Offsets[start], length: utf16Offsets[previous + 1] - utf16Offsets[start]))
                }
                runStart = offset
            }
            previous = offset
        }
        if let start = runStart {
            spans.append(
                MatchSpan(start: utf16Offsets[start], length: utf16Offsets[previous + 1] - utf16Offsets[start]))
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
        case .image:
            return nil
        case .files(let names, let overflow, _):
            return (names + (overflow > 0 ? [localized("+ \(overflow) more")] : [])).joined(separator: ", ")
        }
    }

    private static func accessibilityValue(of item: ClipboardItem, stackPosition: Int?, time: String) -> String {
        var parts: [String] = []
        if item.isPinned {
            parts.append(localized("Pinned card"))
        }
        parts.append(contentsOf: PinTagColor.allCases.filter(item.pinnedMetadata.tags.contains).map(tagLabel))
        if let stackPosition {
            parts.append(localized("Paste stack position \(stackPosition)"))
        }
        parts.append(time)
        return parts.joined(separator: ", ")
    }

    /// Textual payloads carry their size in the footer, whether or not the
    /// preview had to fade out.
    private static func detailLabel(for item: ClipboardItem) -> String? {
        guard case .text(let value) = item.payload,
            item.category == .text || item.category == .code
        else { return nil }
        return localized("\(value.count) characters")
    }

    private static func kindLabel(_ category: ContentCategory) -> String {
        switch category {
        case .text: localized("text")
        case .code: localized("code")
        case .color: localized("color")
        case .link: localized("link")
        case .image: localized("image")
        case .files: localized("files")
        }
    }

    private static func chipIcon(_ category: ContentCategory) -> ChipIcon {
        switch category {
        case .text: .symbol("text.alignleft")
        // The code chip wears the Neovim mark when the bundle ships it.
        case .code: .resource("nvim", fallback: "chevron.left.forwardslash.chevron.right")
        case .color: .symbol("paintpalette")
        case .link: .symbol("link")
        case .image: .symbol("photo")
        case .files: .symbol("folder")
        }
    }

    private func preview(for item: ClipboardItem) -> CardPreview {
        if let cached = previewCache[item.id], cached.text == item.payload.transformableText {
            return cached.preview
        }
        let preview = computePreview(for: item)
        if previewCache.count >= cacheLimit {
            previewCache = previewCache.filter { presentedIDs.contains($0.key) }
        }
        previewCache[item.id] = CachedPreview(text: item.payload.transformableText, preview: preview)
        return preview
    }

    private func computePreview(for item: ClipboardItem) -> CardPreview {
        switch item.payload {
        case .text(let value):
            switch item.category {
            case .color:
                return colorSwatch(for: item.payload) ?? .text(value)
            case .code:
                return .code(text: value, tokens: CodeHighlighter.tokens(in: value))
            default:
                return .text(value)
            }
        case .link(let url):
            return .link(url.absoluteString)
        case .image(let data):
            return .image(data)
        case .fileReferences(let paths):
            let names = paths.map { ($0 as NSString).lastPathComponent }
            return .files(
                names: Array(names.prefix(4)),
                overflow: max(0, names.count - 4),
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
    private func filterBar(from context: FilterContext) -> FilterBarViewState {
        var all: [FilterChip] = []
        var pinned: [FilterChip] = []
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
                            && !context.pinnedOnly && context.activeTags.isEmpty,
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
            case .app(let source):
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
        return FilterBarViewState(all: all, pinned: pinned, apps: apps, kinds: kinds, tags: tags)
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
    private func timeLabel(for item: ClipboardItem, now: Date) -> String {
        let age = now.timeIntervalSince(item.copiedAt)
        guard age >= 60 else { return localized("now") }
        let bucket = Int(age / 60)
        if let cached = timeCache[item.id], cached.bucket == bucket {
            return cached.label
        }
        let label = Self.relativeFormatter.localizedString(for: item.copiedAt, relativeTo: now)
        if timeCache.count >= cacheLimit {
            timeCache = timeCache.filter { presentedIDs.contains($0.key) }
        }
        timeCache[item.id] = (bucket, label)
        return label
    }

    private func countLabel(_ count: Int) -> String {
        localized("\(count) items")
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

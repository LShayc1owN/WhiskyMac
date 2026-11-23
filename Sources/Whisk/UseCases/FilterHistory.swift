import Foundation

/// Criteria narrowing the history; empty criteria match everything.
/// Several sources or categories may be selected at once — an item
/// matches when it belongs to any of them (OR within a facet, AND
/// across facets).
struct HistoryFilter: Equatable {
    var query: String
    var searchMatchMode: SearchMatchMode
    var sources: [SourceApp]
    var categories: Set<ContentCategory>
    var pinnedOnly: Bool
    var tags: Set<PinTagColor>
    var handoffOnly: Bool

    init(
        query: String = "",
        searchMatchMode: SearchMatchMode = .fuzzy,
        sources: [SourceApp] = [],
        categories: Set<ContentCategory> = [],
        pinnedOnly: Bool = false,
        tags: Set<PinTagColor> = [],
        handoffOnly: Bool = false
    ) {
        self.query = query
        self.searchMatchMode = searchMatchMode
        self.sources = sources
        self.categories = categories
        self.pinnedOnly = pinnedOnly
        self.tags = tags
        self.handoffOnly = handoffOnly
    }

    /// The selected facets, independent of the text query and its ranking.
    func includes(_ item: ClipboardItem) -> Bool {
        if handoffOnly, item.source?.origin != .handoffMarker { return false }
        if !tags.isEmpty, !item.isPinned || item.pinnedMetadata.tags.isDisjoint(with: tags) { return false }
        if pinnedOnly, !item.isPinned { return false }
        if !sources.isEmpty, !sources.contains(where: { item.source?.matches($0) ?? false }) { return false }
        return categories.isEmpty || categories.contains(item.category)
    }
}

/// Narrows the history by query, source applications, and content
/// categories. The query understands the `app:` and `type:` operators
/// and the `pinned` word; free words fuzzy-match the content or the
/// source application name — every word must land somewhere (AND) — and
/// a live query ranks by match quality, recency breaking the ties.
struct FilterHistory {
    init() {}

    func callAsFunction(_ history: History, filter: HistoryFilter) -> [ClipboardItem] {
        guard filter != HistoryFilter() else { return history.items }
        let query = ParsedQuery(filter.query, mode: filter.searchMatchMode)
        if !query.ranksMatches {
            return history.items.filter { filter.includes($0) && query.score($0) != nil }
        }
        var scored: [(item: ClipboardItem, score: Int, recency: Int)] = []
        for (recency, item) in history.items.enumerated() where filter.includes(item) {
            guard let score = query.score(item) else { continue }
            scored.append((item, score, recency))
        }
        scored.sort {
            $0.score == $1.score ? $0.recency < $1.recency : $0.score > $1.score
        }
        return scored.map(\.item)
    }
}

/// `app:slack type:code pinned keyboard` → app terms, type terms, the
/// pinned gate, free words.
struct ParsedQuery {
    private(set) var appTerms: [String] = []
    private(set) var typeTerms: [String] = []
    private(set) var pinnedOnly = false
    private(set) var words: [FuzzyMatch.Pattern] = []
    let phrase: LiteralSearch?

    var ranksMatches: Bool { !words.isEmpty }
    var hasText: Bool { ranksMatches || phrase != nil }

    init(_ raw: String, mode: SearchMatchMode = .fuzzy) {
        var literalTerms: [Substring] = []
        for token in raw.split(separator: " ", omittingEmptySubsequences: mode == .fuzzy) {
            let lowered = token.lowercased()
            if lowered.hasPrefix("app:") {
                let term = String(lowered.dropFirst(4))
                if !term.isEmpty { appTerms.append(term) }
            } else if lowered.hasPrefix("type:") || lowered.hasPrefix("kind:") {
                let term = String(lowered.drop(while: { $0 != ":" }).dropFirst())
                if !term.isEmpty { typeTerms.append(term) }
            } else if lowered == "pinned" {
                pinnedOnly = true
            } else if mode == .fuzzy {
                words.append(FuzzyMatch.Pattern(String(token)))
            } else {
                literalTerms.append(token)
            }
        }
        let text = literalTerms.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        phrase = text.isEmpty ? nil : LiteralSearch(text, mode: mode)
    }

    func matchesText(_ value: String) -> Bool {
        if let phrase { return phrase.firstMatch(in: value) != nil }
        return ranksMatches && words.allSatisfy { $0.score(in: value) != nil }
    }

    /// nil means no match; a larger score ranks earlier. Operators are
    /// gates; each free word contributes its best fuzzy score across the
    /// content and the source application.
    func score(_ item: ClipboardItem) -> Int? {
        if pinnedOnly, !item.isPinned { return nil }
        for term in appTerms where !sourceMatches(item, term) {
            return nil
        }
        for term in typeTerms where !item.category.rawValue.hasPrefix(term) {
            return nil
        }
        guard hasText else { return 0 }
        let source = sourceText(item)
        if let phrase {
            if phrase.firstMatch(in: item.pinnedMetadata.note) != nil
                || source.flatMap({ phrase.firstMatch(in: $0) }) != nil
            {
                return 0
            }
            guard !item.pinnedMetadata.hidesContent else { return nil }
            if item.payload.searchableText.flatMap({ phrase.firstMatch(in: $0) }) != nil
                || item.splitGroup?.parts.contains(where: { phrase.firstMatch(in: $0.text) != nil }) == true
            {
                return 0
            }
            return nil
        }
        var text = item.pinnedMetadata.hidesContent ? nil : item.payload.searchableText
        if !item.pinnedMetadata.hidesContent, let group = item.splitGroup {
            text = ([text].compactMap { $0 } + group.parts.map(\.text)).joined(separator: "\n")
        }
        var total = 0
        for word in words {
            let content = text.flatMap { word.score(in: $0) }
            let note = word.score(in: item.pinnedMetadata.note)
            let sourceScore = source.flatMap { word.score(in: $0) }
            guard let best = [content, note, sourceScore].compactMap({ $0 }).max() else { return nil }
            total += best
        }
        return total
    }

    private func sourceText(_ item: ClipboardItem) -> String? {
        guard let source = item.source else { return nil }
        if let name = source.name, let bundleID = source.bundleID { return name + " " + bundleID }
        return source.name ?? source.bundleID
    }

    private func sourceMatches(_ item: ClipboardItem, _ term: String) -> Bool {
        guard let source = item.source else { return false }
        if let name = source.name, name.localizedCaseInsensitiveContains(term) { return true }
        if let bundleID = source.bundleID, bundleID.localizedCaseInsensitiveContains(term) { return true }
        return false
    }
}

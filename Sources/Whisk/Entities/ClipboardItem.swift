import Foundation

/// A single captured pasteboard entry. The category is classified once at
/// creation — the payload is immutable and classification runs regexes.
struct ClipboardItem: Equatable, Hashable, Identifiable {
    let id: UUID
    let payload: Payload
    let source: SourceApp?
    let copiedAt: Date
    let isPinned: Bool
    let category: ContentCategory
    let secretMatch: SecretMatch?
    let richText: BinaryContent?
    var hasRichText: Bool { richText != nil }
    /// Explicit detail access; exports use materialized() so read errors propagate.
    var rtf: Data? { try? richText?.read() }
    let pinnedMetadata: PinnedMetadata
    let splitGroup: SplitGroup?
    let splitSourceID: UUID?

    init(
        id: UUID, payload: Payload, source: SourceApp?, copiedAt: Date, isPinned: Bool, rtf: Data? = nil,
        pinnedMetadata: PinnedMetadata = PinnedMetadata(), splitGroup: SplitGroup? = nil, splitSourceID: UUID? = nil,
        richText: BinaryContent? = nil
    ) {
        self.init(
            id: id, payload: payload, source: source, copiedAt: copiedAt, isPinned: isPinned,
            category: payload.category, secretMatch: SecretMatch.detect(payload, group: splitGroup),
            richText: richText ?? rtf.map(BinaryContent.inline),
            pinnedMetadata: pinnedMetadata.normalized, splitGroup: splitGroup,
            splitSourceID: splitSourceID)
    }

    private init(
        id: UUID, payload: Payload, source: SourceApp?, copiedAt: Date, isPinned: Bool,
        category: ContentCategory, secretMatch: SecretMatch?, richText: BinaryContent?, pinnedMetadata: PinnedMetadata,
        splitGroup: SplitGroup?,
        splitSourceID: UUID?
    ) {
        self.id = id
        self.payload = payload
        self.source = source
        self.copiedAt = copiedAt
        self.isPinned = isPinned
        self.category = category
        self.secretMatch = secretMatch
        self.richText = richText
        self.pinnedMetadata = pinnedMetadata
        self.splitGroup = splitGroup
        self.splitSourceID = splitSourceID
    }

    func materialized() throws -> ClipboardItem {
        try withContentRepresentation(
            payload: payload.materialized(), richText: richText.map { .inline(try $0.read()) },
            splitGroup: splitGroup?.materialized())
    }

    func withContentRepresentation(payload: Payload, richText: BinaryContent?, splitGroup: SplitGroup?) -> ClipboardItem
    {
        ClipboardItem(
            id: id, payload: payload, source: source, copiedAt: copiedAt, isPinned: isPinned,
            category: category, secretMatch: secretMatch, richText: richText, pinnedMetadata: pinnedMetadata,
            splitGroup: splitGroup, splitSourceID: splitSourceID)
    }

    func copied(at date: Date) -> ClipboardItem {
        ClipboardItem(
            id: id, payload: payload, source: source, copiedAt: date, isPinned: isPinned,
            category: category, secretMatch: secretMatch, richText: richText, pinnedMetadata: pinnedMetadata,
            splitGroup: splitGroup,
            splitSourceID: splitSourceID)
    }

    /// Called only after the payload and RTF matcher accepted this revision.
    func recopied(payload incoming: Payload, from newSource: SourceApp?, at date: Date) -> ClipboardItem {
        let nextSource = source?.origin == newSource?.origin ? source : newSource
        // Swift strings compare canonically. Keep the actual latest text and
        // recompute its classification if an equivalent spelling uses different bytes.
        if let old = payload.transformableText, let new = incoming.transformableText,
            !old.utf8.elementsEqual(new.utf8)
        {
            return ClipboardItem(
                id: id, payload: incoming, source: nextSource, copiedAt: date, isPinned: isPinned,
                pinnedMetadata: pinnedMetadata, splitSourceID: splitSourceID, richText: richText)
        }
        let representation: Payload
        if case .storedImage = payload { representation = payload } else { representation = incoming }
        return ClipboardItem(
            id: id, payload: representation, source: nextSource, copiedAt: date, isPinned: isPinned,
            category: category, secretMatch: secretMatch, richText: richText, pinnedMetadata: pinnedMetadata,
            splitGroup: nil, splitSourceID: splitSourceID)
    }

    /// The same card holding something else: identity, source, date and
    /// pin stay; the kind is classified anew and the formatting, which
    /// described the old words, goes.
    func replacing(payload: Payload) -> ClipboardItem {
        ClipboardItem(
            id: id, payload: payload, source: source, copiedAt: copiedAt, isPinned: isPinned,
            pinnedMetadata: pinnedMetadata, splitGroup: splitGroup, splitSourceID: splitSourceID)
    }

    func withPinnedMetadata(_ value: PinnedMetadata) -> ClipboardItem {
        ClipboardItem(
            id: id, payload: payload, source: source, copiedAt: copiedAt, isPinned: isPinned,
            category: category, secretMatch: secretMatch, richText: richText, pinnedMetadata: value.normalized,
            splitGroup: splitGroup,
            splitSourceID: splitSourceID)
    }

    func withSplitGroup(_ group: SplitGroup?) -> ClipboardItem {
        ClipboardItem(
            id: id, payload: payload, source: source, copiedAt: copiedAt, isPinned: isPinned,
            pinnedMetadata: pinnedMetadata, splitGroup: group, splitSourceID: splitSourceID, richText: richText)
    }

    func pinToggled() -> ClipboardItem {
        ClipboardItem(
            id: id, payload: payload, source: source, copiedAt: copiedAt, isPinned: !isPinned,
            category: category, secretMatch: secretMatch, richText: richText, pinnedMetadata: pinnedMetadata,
            splitGroup: splitGroup,
            splitSourceID: splitSourceID)
    }
}

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
            category: payload.category, richText: richText ?? rtf.map(BinaryContent.inline),
            pinnedMetadata: pinnedMetadata, splitGroup: splitGroup,
            splitSourceID: splitSourceID)
    }

    private init(
        id: UUID, payload: Payload, source: SourceApp?, copiedAt: Date, isPinned: Bool,
        category: ContentCategory, richText: BinaryContent?, pinnedMetadata: PinnedMetadata, splitGroup: SplitGroup?,
        splitSourceID: UUID?
    ) {
        self.id = id
        self.payload = payload
        self.source = source
        self.copiedAt = copiedAt
        self.isPinned = isPinned
        self.category = category
        self.richText = richText
        self.pinnedMetadata = pinnedMetadata.normalized
        self.splitGroup = splitGroup
        self.splitSourceID = splitSourceID
    }

    func materialized() throws -> ClipboardItem {
        ClipboardItem(
            id: id, payload: try payload.materialized(), source: source, copiedAt: copiedAt, isPinned: isPinned,
            rtf: try richText?.read(), pinnedMetadata: pinnedMetadata, splitGroup: try splitGroup?.materialized(),
            splitSourceID: splitSourceID)
    }

    func withStoredContent(payload: Payload, richText: BinaryContent?, splitGroup: SplitGroup?) -> ClipboardItem {
        ClipboardItem(
            id: id, payload: payload, source: source, copiedAt: copiedAt, isPinned: isPinned,
            category: category, richText: richText, pinnedMetadata: pinnedMetadata,
            splitGroup: splitGroup, splitSourceID: splitSourceID)
    }

    func copied(at date: Date) -> ClipboardItem {
        ClipboardItem(
            id: id, payload: payload, source: source, copiedAt: date, isPinned: isPinned,
            category: category, richText: richText, pinnedMetadata: pinnedMetadata, splitGroup: splitGroup,
            splitSourceID: splitSourceID)
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
            category: category, richText: richText, pinnedMetadata: value, splitGroup: splitGroup,
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
            category: category, richText: richText, pinnedMetadata: pinnedMetadata, splitGroup: splitGroup,
            splitSourceID: splitSourceID)
    }
}

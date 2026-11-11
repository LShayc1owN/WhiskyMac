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
    let rtf: Data?
    let pinnedMetadata: PinnedMetadata
    let splitGroup: SplitGroup?
    let splitSourceID: UUID?

    init(
        id: UUID, payload: Payload, source: SourceApp?, copiedAt: Date, isPinned: Bool, rtf: Data? = nil,
        pinnedMetadata: PinnedMetadata = PinnedMetadata(), splitGroup: SplitGroup? = nil, splitSourceID: UUID? = nil
    ) {
        self.init(
            id: id, payload: payload, source: source, copiedAt: copiedAt, isPinned: isPinned,
            category: payload.category, rtf: rtf, pinnedMetadata: pinnedMetadata, splitGroup: splitGroup,
            splitSourceID: splitSourceID)
    }

    private init(
        id: UUID, payload: Payload, source: SourceApp?, copiedAt: Date, isPinned: Bool,
        category: ContentCategory, rtf: Data?, pinnedMetadata: PinnedMetadata, splitGroup: SplitGroup?,
        splitSourceID: UUID?
    ) {
        self.id = id
        self.payload = payload
        self.source = source
        self.copiedAt = copiedAt
        self.isPinned = isPinned
        self.category = category
        self.rtf = rtf
        self.pinnedMetadata = pinnedMetadata.normalized
        self.splitGroup = splitGroup
        self.splitSourceID = splitSourceID
    }

    func copied(at date: Date) -> ClipboardItem {
        ClipboardItem(
            id: id, payload: payload, source: source, copiedAt: date, isPinned: isPinned,
            category: category, rtf: rtf, pinnedMetadata: pinnedMetadata, splitGroup: splitGroup,
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
            category: category, rtf: rtf, pinnedMetadata: value, splitGroup: splitGroup, splitSourceID: splitSourceID)
    }

    func withSplitGroup(_ group: SplitGroup?) -> ClipboardItem {
        ClipboardItem(
            id: id, payload: payload, source: source, copiedAt: copiedAt, isPinned: isPinned,
            rtf: rtf, pinnedMetadata: pinnedMetadata, splitGroup: group, splitSourceID: splitSourceID)
    }

    func pinToggled() -> ClipboardItem {
        ClipboardItem(
            id: id, payload: payload, source: source, copiedAt: copiedAt, isPinned: !isPinned,
            category: category, rtf: rtf, pinnedMetadata: pinnedMetadata, splitGroup: splitGroup,
            splitSourceID: splitSourceID)
    }
}

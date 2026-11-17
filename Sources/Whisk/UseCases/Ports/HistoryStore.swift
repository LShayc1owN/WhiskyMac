import Foundation

/// Failure surfaced by a history store adapter.
enum HistoryStoreError: Error, Equatable {
    case unreadable(String)
    case unwritable(String)
}

/// Persistence boundary for clipboard items, newest first.
protocol HistoryStore {
    func load() throws -> [ClipboardItem]
    /// A list snapshot contains handles to heavy content, never hydrated bytes.
    func loadList() throws -> [ClipboardItem]
    func compact(_ items: [ClipboardItem]) throws -> [ClipboardItem]
    func releaseContentCache()
    func setContentCacheEnabled(_ enabled: Bool)
    func duplicateMatcher(payload: Payload, rtf: Data?) -> (ClipboardItem) -> Bool
    /// Persists the ordering and any content that changed since the last
    /// save. A nil set means every item's content is in doubt and must be
    /// written — the full-save behaviour callers get by default.
    func save(_ items: [ClipboardItem], changedContentIDs: Set<UUID>?) throws
}

extension HistoryStore {
    func loadList() throws -> [ClipboardItem] { try load() }
    func compact(_ items: [ClipboardItem]) throws -> [ClipboardItem] { items }
    func releaseContentCache() {}
    func setContentCacheEnabled(_ enabled: Bool) {}
    func duplicateMatcher(payload: Payload, rtf: Data?) -> (ClipboardItem) -> Bool {
        { $0.payload == payload && $0.richText == rtf.map(BinaryContent.inline) }
    }

    func save(_ items: [ClipboardItem]) throws {
        try save(items, changedContentIDs: nil)
    }
}

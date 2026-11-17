import Foundation

/// Puts a remembered history back and persists it — the undo of a
/// deletion, a clear or an edit.
struct RestoreHistory<Store: HistoryStore> {
    private let store: Store

    init(store: Store) {
        self.store = store
    }

    /// `changedContentIDs` names the entries whose content may have left
    /// the store while the snapshot was away — a nil set rewrites all.
    func callAsFunction(_ history: History, changedContentIDs: Set<UUID>? = nil) throws -> History {
        try store.save(history.items, changedContentIDs: changedContentIDs)
        return History(items: try store.compact(history.items), capacity: history.capacity)
    }
}

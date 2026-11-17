import Foundation

/// Flips an item's pin and persists the result.
struct TogglePin<Store: HistoryStore> {
    private let store: Store

    init(store: Store) {
        self.store = store
    }

    func callAsFunction(_ id: UUID, in history: History) throws -> History {
        let next = history.togglingPin(id)
        try store.save(next.items, changedContentIDs: [])
        return History(items: try store.compact(next.items), capacity: next.capacity)
    }
}

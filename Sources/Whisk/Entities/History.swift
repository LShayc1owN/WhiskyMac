// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

/// Ordered clipboard history, newest first. Pinned items are exempt from
/// eviction and do not count toward capacity.
struct History: Equatable {
    private(set) var items: [ClipboardItem]
    let capacity: HistoryCapacity

    init(items: [ClipboardItem] = [], capacity: HistoryCapacity = .standard) {
        self.items = items
        self.capacity = capacity
        evictOverflow()
    }

    /// Records a captured payload and its original formatting. Only an
    /// exact payload + RTF match reuses an entry's identity and pin.
    func recording(
        _ payload: Payload, from source: SourceApp?, rtf: Data? = nil, at date: Date, id: UUID = UUID()
    ) -> History {
        var next = self
        if let index = next.items.firstIndex(where: { $0.payload == payload && $0.rtf == rtf }) {
            let previous = next.items.remove(at: index)
            let refreshed = ClipboardItem(
                id: previous.id, payload: payload,
                source: previous.source?.origin == source?.origin ? previous.source : source,
                copiedAt: date, isPinned: previous.isPinned, rtf: rtf)
            next.items.insert(refreshed, at: 0)
            return next
        }
        let item = ClipboardItem(id: id, payload: payload, source: source, copiedAt: date, isPinned: false, rtf: rtf)
        next.items.insert(item, at: 0)
        next.evictOverflow()
        return next
    }

    /// Moves an item to the front with a refreshed date.
    func selecting(_ id: UUID, at date: Date) -> History {
        var next = self
        guard let index = next.items.firstIndex(where: { $0.id == id }) else { return self }
        let refreshed = next.items.remove(at: index).copied(at: date)
        next.items.insert(refreshed, at: 0)
        return next
    }

    /// Replaces what an item holds, in place; an unknown id changes nothing.
    func replacingPayload(of id: UUID, with payload: Payload) -> History {
        var next = self
        guard let index = next.items.firstIndex(where: { $0.id == id }) else { return self }
        next.items[index] = next.items[index].replacing(payload: payload)
        return next
    }

    /// Flips an item's pin. Unpinning may evict it if the history overflows.
    func togglingPin(_ id: UUID) -> History {
        var next = self
        guard let index = next.items.firstIndex(where: { $0.id == id }) else { return self }
        next.items[index] = next.items[index].pinToggled()
        next.evictOverflow()
        return next
    }

    /// Removes an item regardless of its pin.
    func deleting(_ id: UUID) -> History {
        var next = self
        next.items.removeAll { $0.id == id }
        return next
    }

    /// Removes unpinned items older than the cutoff.
    func removingUnpinned(olderThan cutoff: Date) -> History {
        var next = self
        next.items.removeAll { !$0.isPinned && $0.copiedAt < cutoff }
        return next
    }

    /// Removes the unpinned items a predicate selects.
    func deletingUnpinned(where matches: (ClipboardItem) -> Bool) -> History {
        var next = self
        next.items.removeAll { !$0.isPinned && matches($0) }
        return next
    }

    /// Removes every unpinned item.
    func clearingUnpinned() -> History {
        var next = self
        next.items.removeAll { !$0.isPinned }
        return next
    }

    private mutating func evictOverflow() {
        var overflow = items.filter { !$0.isPinned }.count - capacity.value
        guard overflow > 0 else { return }
        var evicted: Set<UUID> = []
        for item in items.reversed() where !item.isPinned {
            guard overflow > 0 else { break }
            evicted.insert(item.id)
            overflow -= 1
        }
        items.removeAll { evicted.contains($0.id) }
    }
}

// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

/// Puts an item back on the pasteboard and refreshes its position.
struct SelectItem<Board: Pasteboard, Time: Clock, Store: HistoryStore> {
    private let pasteboard: Board
    private let clock: Time
    private let store: Store

    init(pasteboard: Board, clock: Time, store: Store) {
        self.pasteboard = pasteboard
        self.clock = clock
        self.store = store
    }

    /// Puts the item back on the pasteboard — rich text included unless a
    /// plain paste was asked for — or a rewritten stand-in for it, which
    /// travels without formatting and leaves the item as it was.
    func callAsFunction(
        _ id: UUID, in history: History, plain: Bool = false, writing replacement: Payload? = nil,
        forPaste: Bool = false
    ) throws -> History {
        guard let item = history.items.first(where: { $0.id == id }), item.splitGroup == nil else { return history }
        let payload = replacement ?? item.payload
        let rtf = replacement != nil || plain ? nil : item.rtf
        if forPaste {
            pasteboard.writeForPaste(payload, rtf: rtf)
        } else {
            pasteboard.write(payload, rtf: rtf)
        }
        let next = history.selecting(id, at: clock.now())
        try store.save(next.items)
        return next
    }
}

// WhiskyMac: modified or added 2026-11-10 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

struct SplitSaveRequest {
    let source: ClipboardItem
    let parts: [SplitPart]
    let mode: SplitSaveMode
    let plainText: Bool
}
struct SplitSaveAssessment {
    let history: History
    let evictedCount: Int
}

enum SaveSplit {
    static func prepare(_ request: SplitSaveRequest, in history: History, policy: RetentionPolicy, now: Date) throws
        -> SplitSaveAssessment
    {
        let source = request.source
        guard history.items.first(where: { $0.id == source.id }) == source else { throw SplitFailure.stale }
        guard source.splitGroup == nil, !source.pinnedMetadata.hidesContent,
            source.payload.transformableText != nil
        else { throw SplitFailure.unavailable }
        guard !request.parts.isEmpty else { throw SplitFailure.noSelection }
        guard SplitGroup(parts: request.parts, plainText: request.plainText).isValid else {
            throw SplitFailure.tooManyParts
        }
        let additions: [ClipboardItem]
        var remaining = history.items
        switch request.mode {
        case .group:
            let root = source.withSplitGroup(SplitGroup(parts: request.parts, plainText: request.plainText)).copied(
                at: now)
            additions = [root]
            remaining.removeAll { $0.id == source.id }
        case .keepOriginal, .replace:
            additions = request.parts.enumerated().map { index, part in
                var metadata = source.pinnedMetadata
                if !metadata.note.isEmpty { metadata.note += " · \(index + 1)" }
                return ClipboardItem(
                    id: part.id, payload: part.payload, source: source.source, copiedAt: now,
                    isPinned: source.isPinned, rtf: request.plainText ? nil : part.rtf, pinnedMetadata: metadata,
                    splitSourceID: source.id)
            }
            if request.mode == .replace { remaining.removeAll { $0.id == source.id } }
        }
        let ids = Set(additions.map(\.id))
        guard ids.count == additions.count, remaining.allSatisfy({ !ids.contains($0.id) }) else {
            throw SplitFailure.stale
        }
        let next = History(items: additions + remaining, capacity: policy.capacity)
        guard ids.isSubset(of: Set(next.items.map(\.id))) else { throw SplitFailure.capacity }
        if request.mode == .keepOriginal, !next.items.contains(where: { $0.id == source.id }) {
            throw SplitFailure.capacity
        }
        return SplitSaveAssessment(
            history: next,
            evictedCount: remaining.filter { previous in !next.items.contains(where: { $0.id == previous.id }) }.count)
    }
}

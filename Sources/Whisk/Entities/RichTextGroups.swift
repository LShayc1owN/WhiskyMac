// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

/// Plain copies stay independent; only formatted copies share a module.
enum RichTextGroups {
    static func groupingKey(for item: ClipboardItem) -> String? {
        guard case .text(let text) = item.payload, item.hasRichText, !item.isPinned, item.splitGroup == nil,
            item.splitSourceID == nil, item.pinnedMetadata == PinnedMetadata()
        else { return nil }
        return text
    }

    /// Singleton rows borrow their item from the input. Only formatted
    /// variants need a separate list of indices.
    struct Rows {
        let items: [ClipboardItem]
        fileprivate var representatives: [Int]?
        fileprivate var variants: [Int: [Int]] = [:]
        var count: Int { representatives?.count ?? items.count }
        var indices: Range<Int> { 0..<count }
        func item(at row: Int) -> ClipboardItem { items[representatives?[row] ?? row] }
        func groupedIDs(at row: Int) -> [UUID] {
            variants[row]?.map { items[$0].id } ?? []
        }
    }

    static func groups(_ items: [ClipboardItem]) -> Rows {
        var result = Rows(items: items)
        var byText: [String: Int] = [:]
        for i in items.indices {
            let row = result.representatives?.count ?? i
            if let text = groupingKey(for: items[i]) {
                if let existing = byText[text] {
                    if result.representatives == nil { result.representatives = Array(0..<i) }
                    let first = result.representatives?[existing] ?? existing
                    result.variants[existing, default: [first]].append(i)
                    continue
                }
                byText[text] = row
            }
            result.representatives?.append(i)
        }
        for row in result.variants.keys {
            result.variants[row]?.sort { items[$0].copiedAt > items[$1].copiedAt }
            if let first = result.variants[row]?.first { result.representatives?[row] = first }
        }
        return result
    }
}

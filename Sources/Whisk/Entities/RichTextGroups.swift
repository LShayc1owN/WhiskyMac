// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

/// Plain copies stay independent; only formatted copies share a module.
enum RichTextGroups {
    static func groups(_ items: [ClipboardItem]) -> [[ClipboardItem]] {
        var result: [[ClipboardItem]] = []
        var indices: [String: Int] = [:]
        for item in items {
            if case .text(let text) = item.payload, item.rtf != nil, !item.isPinned, item.splitGroup == nil,
                item.splitSourceID == nil,
                item.pinnedMetadata == PinnedMetadata()
            {
                if let index = indices[text] {
                    result[index].append(item)
                } else {
                    indices[text] = result.count
                    result.append([item])
                }
            } else {
                result.append([item])
            }
        }
        return result.map { $0.sorted { $0.copiedAt > $1.copiedAt } }
    }
}

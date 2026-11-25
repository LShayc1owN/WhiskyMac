// WhiskyMac: added 2026-11-25 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

struct FilterCategoryOrder: Equatable {
    static let standard = FilterCategoryOrder()
    private(set) var categories: [ContentCategory]

    init(savedIDs: [String] = []) {
        var seen = Set<ContentCategory>()
        let saved = savedIDs.compactMap(ContentCategory.init(rawValue:))
        // Preserve known preferences and append categories introduced by future versions.
        categories = (saved + ContentCategory.allCases).filter { seen.insert($0).inserted }
    }

    var savedIDs: [String] { categories.map(\.rawValue) }

    func moving(_ source: ContentCategory, to target: ContentCategory) -> Self {
        guard source != target,
            let sourceIndex = categories.firstIndex(of: source),
            let targetIndex = categories.firstIndex(of: target)
        else { return self }
        var next = self
        next.categories.remove(at: sourceIndex)
        next.categories.insert(source, at: targetIndex)
        return next
    }
}

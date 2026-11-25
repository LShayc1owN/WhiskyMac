// WhiskyMac: added 2026-11-25 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import CoreTransferable
import UniformTypeIdentifiers

struct FilterCategoryDrag: Codable, Transferable {
    private let categoryID: String

    init(_ category: ContentCategory) {
        categoryID = category.rawValue
    }

    var category: ContentCategory? { ContentCategory(rawValue: categoryID) }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(
            contentType: UTType(
                exportedAs: AppIdentity.bundleIdentifier + ".filter-category-order", conformingTo: .data)
        )
        .visibility(.ownProcess)
    }
}

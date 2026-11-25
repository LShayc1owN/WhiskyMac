// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

extension ContentCategory {
    var hidingTitle: String {
        switch self {
        case .text: localized("text").capitalized
        case .code: localized("code").capitalized
        case .color: localized("color").capitalized
        case .link: localized("link").capitalized
        case .path: localized("path").capitalized
        case .secret: localized("secret").capitalized
        case .image: localized("image").capitalized
        case .files: localized("files").capitalized
        }
    }
}

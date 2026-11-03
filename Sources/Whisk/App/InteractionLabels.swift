// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

extension CardAction {
    var label: String {
        switch self {
        case .paste: localized("Paste to previous app")
        case .copy: localized("Copy")
        case .preview: localized("Preview")
        case .edit: localized("Edit…")
        case .menu: localized("Actions")
        case .none: localized("Do nothing")
        }
    }
}

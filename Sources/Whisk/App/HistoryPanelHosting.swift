// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

enum HistoryPanelHosting {
    static func make(store: HistoryViewStateStore, actions: PanelActions) -> NSHostingView<HistoryPanelView> {
        let host = NSHostingView(rootView: HistoryPanelView(store: store, actions: actions))
        if store.isProtected, !store.privacyAllowsSearch, !store.privacyShowsSourceApps {
            // The AppKit boundary also suppresses stale SwiftUI AX descendants.
            host.setAccessibilityElement(true)
            host.setAccessibilityRole(.group)
            host.setAccessibilityLabel(localized("Content hidden by Privacy Mode"))
            host.setAccessibilityChildren([])
        }
        return host
    }
}

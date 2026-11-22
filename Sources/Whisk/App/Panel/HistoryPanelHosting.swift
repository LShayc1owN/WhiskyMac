// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

enum HistoryPanelHosting {
    static func make(
        store: HistoryViewStateStore, actions: PanelActions, keyBindings: KeyBindingsStore? = nil,
        popoverCoordinator: CardPopoverCoordinator? = nil
    ) -> NSHostingView<HistoryPanelView> {
        let host = NSHostingView(
            rootView: HistoryPanelView(
                store: store, actions: actions, keyBindings: keyBindings, popoverCoordinator: popoverCoordinator))
        // The panel frame is authoritative; do not measure a full scroll
        // document as an intrinsic window size before the viewport exists.
        host.sizingOptions = []
        if store.isProtected {
            host.setAccessibilityLabel(localized("Content hidden by Privacy Mode"))
            if store.protectedCardCount == 0, !store.privacyAllowsSearch,
                !store.privacyShowsSourceApps, !store.privacyAllowsFiltering, !store.privacyAllowsAppFiltering,
                !store.privacyAllowsHandoffFiltering, !store.canToggleHistoryVisibility
            {
                host.setAccessibilityElement(true)
                host.setAccessibilityRole(.group)
                host.setAccessibilityChildren([])
            }
        }
        return host
    }
}

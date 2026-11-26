// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

/// AppKit can retain an old hosting view in its keyboard focus table.
@MainActor
protocol HistoryContentOwner {
    func discardHistoryContent()
}

@MainActor
enum HistoryPanelHosting {
    static func make(
        uiFactory: any AppUIFactory,
        store: HistoryViewStateStore, actions: PanelActions, keyBindings: KeyBindingsStore? = nil,
        popoverCoordinator: CardPopoverCoordinator? = nil,
        presentation: HistoryUIPresentation = .history
    ) -> NSView {
        let host = uiFactory.makeHistoryContent(
            context: HistoryUIContext(
                store: store, actions: actions, keyBindings: keyBindings,
                popoverCoordinator: popoverCoordinator), presentation: presentation)
        if presentation == .history, store.isProtected {
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

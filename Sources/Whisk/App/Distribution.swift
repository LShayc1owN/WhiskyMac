// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

/// How this build reaches the user, decided at compile time. The
/// Developer ID build from GitHub and Homebrew looks after its own
/// updates; the App Store build leaves that to the store, whose rules
/// forbid an updater of its own.
enum Distribution: Equatable {
    case developerID
    case mayDevelopment
    case appStore

    /// Whether the app may look for a newer version and point to it.
    var checksForUpdates: Bool {
        switch self {
        case .developerID: true
        case .appStore, .mayDevelopment: false
        }
    }

    static var current: Distribution {
        #if APP_STORE
            .appStore
        #elseif WHISK_MAY_DEV
            .mayDevelopment
        #else
            .developerID
        #endif
    }
}

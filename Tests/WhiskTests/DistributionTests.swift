// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Testing

@testable import Whisk

@Suite struct DistributionRules {
    @Test func only_builds_outside_the_app_store_check_for_updates() {
        #expect(Distribution.developerID.checksForUpdates)
        #expect(!Distribution.appStore.checksForUpdates)
        #expect(Distribution.development.checksForUpdates)
    }

    @Test func the_test_build_uses_the_development_distribution() {
        #expect(Distribution.current == .development)
    }
}

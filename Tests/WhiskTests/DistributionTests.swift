// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Testing

@testable import Whisk

@Suite struct DistributionRules {
    @Test func only_the_developer_id_build_checks_for_updates() {
        #expect(Distribution.developerID.checksForUpdates)
        #expect(!Distribution.appStore.checksForUpdates)
        #expect(Distribution.mayDevelopment.checksForUpdates)
    }

    @Test func the_test_build_is_the_may_development_one() {
        #expect(Distribution.current == .mayDevelopment)
    }
}

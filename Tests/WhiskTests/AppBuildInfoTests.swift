// WhiskyMac: modified or added 2026-11-17 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Testing

@testable import Whisk

@Suite struct AppBuildInfoTests {
    @Test func stable_and_future_beta_versions_are_independent() {
        for version in ["1.0.0", "1.0.1", "v1.1.0"] {
            #expect(AppBuildInfo(version: version, isDebug: false).channel == .release)
        }
        for version in ["1.1.0beta1", "1.1.0beta2", "1.1.0-beta.2", "v1.1.0Beta3"] {
            let info = AppBuildInfo(version: version, isDebug: false)
            #expect(info.channel == .beta)
            #expect(info.version == version)
        }
        #expect(AppBuildInfo(version: "1.1.0beta1", isDebug: true).channel == .debug)
        #expect(AppBuildInfo(version: "1.0.1", isDebug: true).channel == .debug)
        #expect(AppBuildInfo(version: nil, isDebug: true).channel == .debug)
        #expect(AppBuildInfo(version: "not-a-beta-version", isDebug: false).channel == .release)
    }
}

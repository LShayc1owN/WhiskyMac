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

    @Test func version_number_and_channel_label_are_available_separately() {
        let release = AppBuildInfo(version: "0.1.14", isDebug: false)
        #expect(release.versionNumber == "0.1.14" && release.channelLabel == "Release")
        let beta = AppBuildInfo(version: "0.9.0-beta.2", isDebug: false)
        #expect(beta.versionNumber == "0.9.0" && beta.channelLabel == "Beta 2")
        let debug = AppBuildInfo(version: "0.9.0-beta.2", isDebug: true)
        #expect(debug.versionNumber == "0.9.0" && debug.channelLabel == "Debug")
        #expect(AppBuildInfo(version: "", isDebug: false).versionNumber == nil)
    }

    @Test func version_badges_append_the_channel_once_and_keep_beta_numbers() {
        #expect(AppBuildInfo(version: "0.9.0", isDebug: false).versionWithChannel == "0.9.0 Release")
        #expect(AppBuildInfo(version: "0.9.0-beta", isDebug: false).versionWithChannel == "0.9.0 Beta")
        #expect(AppBuildInfo(version: "V0.9.0-BETA.2", isDebug: false).versionWithChannel == "V0.9.0 Beta 2")
        #expect(AppBuildInfo(version: "0.9.0beta2", isDebug: true).versionWithChannel == "0.9.0 Debug")
        #expect(AppBuildInfo(version: nil, isDebug: true).versionWithChannel == nil)
        #expect(AppBuildInfo(version: "", isDebug: false).versionWithChannel == nil)
    }
}

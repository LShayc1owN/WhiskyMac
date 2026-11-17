// WhiskyMac: modified or added 2026-11-17 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

struct AppBuildInfo: Equatable {
    enum Channel: String {
        case debug = "Debug"
        case release = "Release"
        case beta = "Beta"
    }

    let version: String?
    let channel: Channel

    static var current: AppBuildInfo {
        #if DEBUG
            let isDebug = true
        #else
            let isDebug = false
        #endif
        return AppBuildInfo(
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            isDebug: isDebug)
    }

    init(version: String?, isDebug: Bool) {
        self.version = version
        if isDebug {
            channel = .debug
        } else if let version,
            version.range(
                of: #"^v?[0-9]+(?:\.[0-9]+){1,3}-?beta(?:[.-]?[0-9]+)?$"#,
                options: [.regularExpression, .caseInsensitive]) != nil
        {
            channel = .beta
        } else {
            channel = .release
        }
    }
}

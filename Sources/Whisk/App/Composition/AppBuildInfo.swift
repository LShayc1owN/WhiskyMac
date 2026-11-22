// WhiskyMac: modified or added 2026-11-17 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

struct AppBuildInfo: Equatable {
    enum Channel: String, Codable, Sendable {
        case debug = "Debug"
        case release = "Release"
        case beta = "Beta"
    }

    let version: String?
    let channel: Channel
    let versionWithChannel: String?

    static let betaVersion = #/(?i)(v?[0-9]+(?:\.[0-9]+){1,3})-?beta(?:[.-]?([0-9]+))?/#

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
        let beta = version?.wholeMatch(of: Self.betaVersion)
        if isDebug {
            channel = .debug
        } else if beta != nil {
            channel = .beta
        } else {
            channel = .release
        }

        if let version, !version.isEmpty {
            let versionNumber = beta.map { String($0.1) } ?? version
            let label = "\(versionNumber) \(channel.rawValue)"
            if channel == .beta, let number = beta?.2 {
                versionWithChannel = "\(label) \(number)"
            } else {
                versionWithChannel = label
            }
        } else {
            versionWithChannel = nil
        }
    }
}

// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

/// A separate identity for local WhiskyMac development builds. Keep this
/// explicit: SwiftPM's bare executable has no application bundle identifier.
enum AppIdentity {
    static let bundleIdentifier = "dev.whisky.maclx"
    static let displayName = "WhiskyMac"
    static let dataDirectoryName = "WhiskMay-Dev"
    static let dataDirectoryOverride = "WHISK_MAY_DATA_DIR"

    static let smokeDefaultsDomain = bundleIdentifier + ".smoke." + UUID().uuidString

    static var defaults: UserDefaults {
        // Smoke launches use fresh preferences as well as temporary history.
        // They must not inherit the live app's language, Dock or capture policy.
        if CommandLine.arguments.contains("--smoke-test"),
            let isolated = UserDefaults(
                suiteName: smokeDefaultsDomain)
        {
            return isolated
        }
        // A packaged app already owns this domain. Foundation rejects
        // init(suiteName:) when its name is the app's own bundle identifier.
        if Bundle.main.bundleIdentifier == bundleIdentifier {
            return .standard
        }
        // The bare SwiftPM executable has no app identity; address the
        // same domain explicitly without falling back to Whisk's defaults.
        guard let defaults = UserDefaults(suiteName: bundleIdentifier) else {
            preconditionFailure("WhiskyMac settings domain is unavailable")
        }
        return defaults
    }

    static func dataDirectory(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        if let override = environment[dataDirectoryOverride], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent(dataDirectoryName, isDirectory: true)
    }

    static func importedIconsDirectory(in dataDirectory: URL) -> URL {
        dataDirectory.appendingPathComponent("ImportedIcons", isDirectory: true)
    }

    static func previewCacheDirectory(in dataDirectory: URL) -> URL {
        dataDirectory.appendingPathComponent("PreviewCache", isDirectory: true)
    }
}

// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

/// The Xcode string catalog is compiled into the module's localized resources.
func localized(_ key: String.LocalizationValue, bundle: Bundle = AppResources.bundle) -> String {
    let bundle = AppLocalization.selectedBundle(in: bundle, language: AppLocalization.language)
    // Plural rules belong to the translated language. A Chinese system
    // locale, for example, has no singular category even when this bundle
    // falls back to English. Using it would produce "1 items".
    let language =
        bundle.bundleURL.pathExtension == "lproj"
        ? bundle.bundleURL.deletingPathExtension().lastPathComponent
        : bundle.preferredLocalizations.first ?? bundle.developmentLocalization ?? "en"
    return String(localized: key, bundle: bundle, locale: Locale(identifier: language))
}

/// Resolve shipped resources without SwiftPM's build-machine absolute path.
enum AppResources {
    static let name = "Whisk_Whisk.bundle"
    private final class Token: NSObject {}

    static let bundle: Bundle =
        locate(
            in: [
                Bundle.main.resourceURL,
                Bundle.main.bundleURL,
                Bundle.main.executableURL?.deletingLastPathComponent(),
                Bundle(for: Token.self).bundleURL.deletingLastPathComponent(),
            ].compactMap { $0 }) ?? .main

    static func locate(in directories: [URL]) -> Bundle? {
        for directory in directories {
            if let bundle = Bundle(url: directory.appendingPathComponent(name)),
                bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "en")
                    != nil
            {
                return bundle
            }
        }
        return nil
    }
}

/// The app explicitly applies its preference at the composition root.
/// Explicit lproj bundles, such as translation fixtures, keep their language.
enum AppLocalization {
    private static let lock = NSLock()
    private static var selection: String?
    static var language: String? {
        get { lock.lock(); defer { lock.unlock() }; return selection }
        set { lock.lock(); selection = newValue; lock.unlock() }
    }
    static func selectedBundle(in bundle: Bundle, language: String?) -> Bundle {
        guard bundle.bundleURL.pathExtension != "lproj", let language,
            ["en", "fr", "de", "zh-Hans"].contains(language),
            let resource = bundle.url(
                forResource: "Localizable", withExtension: "strings",
                subdirectory: nil, localization: language),
            let selected = Bundle(url: resource.deletingLastPathComponent())
        else { return bundle }
        return selected
    }
}

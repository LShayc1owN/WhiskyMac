// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

/// The Xcode string catalog is compiled into the module's localized resources.
func localized(_ key: String.LocalizationValue, bundle: Bundle = AppResources.bundle) -> String {
    let resource = AppLocalization.resource(in: bundle)
    return String(localized: key, bundle: resource.bundle, locale: resource.locale)
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
    private static var appResource: (bundle: Bundle, locale: Locale)?
    private static let localeObserver = NotificationCenter.default.addObserver(
        forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: nil
    ) { _ in lock.withLock { appResource = nil } }

    static var language: String? {
        get { lock.withLock { selection } }
        set {
            lock.withLock {
                guard selection != newValue else { return }
                selection = newValue
                appResource = nil
            }
        }
    }

    fileprivate static func resource(in bundle: Bundle) -> (bundle: Bundle, locale: Locale) {
        _ = localeObserver
        return lock.withLock {
            let isAppBundle = bundle === AppResources.bundle
            if isAppBundle, let appResource { return appResource }
            let selected = selectedBundle(in: bundle, language: selection)
            let resource = (selected, locale(in: selected))
            if isAppBundle { appResource = resource }
            return resource
        }
    }
    static func locale(in bundle: Bundle) -> Locale {
        // Use the loaded translation's plural rules, including when falling back to English.
        let identifier =
            bundle.bundleURL.pathExtension == "lproj"
            ? bundle.bundleURL.deletingPathExtension().lastPathComponent
            : bundle.preferredLocalizations.first ?? bundle.developmentLocalization ?? "en"
        return Locale(identifier: identifier)
    }

    static var interfaceLocale: Locale {
        resource(in: AppResources.bundle).locale
    }

    static func selectedBundle(in bundle: Bundle, language: String?) -> Bundle {
        guard bundle.bundleURL.pathExtension != "lproj", let language,
            ["en", "fr", "de", "it", "zh-Hans", "zh-Hant", "ja"].contains(language),
            let resource = bundle.url(
                forResource: "Localizable", withExtension: "strings",
                subdirectory: nil, localization: language),
            let selected = Bundle(url: resource.deletingLastPathComponent())
        else { return bundle }
        return selected
    }
}

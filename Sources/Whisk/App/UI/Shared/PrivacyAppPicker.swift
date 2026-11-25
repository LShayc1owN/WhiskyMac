// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import UniformTypeIdentifiers

@MainActor
enum PrivacyAppPicker {
    static func present(_ didChoose: @escaping ([ExcludedApp]) -> Void) {
        // Let macOS localize the entire panel, including its title and buttons.
        // WhiskyMac's in-app language only applies to its own views.
        let panel = NSOpenPanel()
        panel.directoryURL = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true

        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            let apps = panel.urls.compactMap { url -> ExcludedApp? in
                guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { return nil }
                let name =
                    bundle.infoDictionary?["CFBundleName"] as? String ?? url.deletingPathExtension().lastPathComponent
                return ExcludedApp(bundleID: bundleID, name: name)
            }
            guard !apps.isEmpty else { return }
            didChoose(apps)
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }
}

// WhiskyMac: modified or added 2026-11-05 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

enum LegalDocument: String, CaseIterable, Identifiable {
    case license, notice, thirdParty, appStoreException, whiskyMacException, kenneyLicense, kenneySource
    case sfxKitLicense, sfxKitSource

    var id: String { rawValue }

    var title: String {
        switch self {
        case .license: localized("GNU General Public License")
        case .notice: localized("Project notice")
        case .thirdParty: localized("Third-party notices")
        case .appStoreException: localized("App Store exception")
        case .whiskyMacException: localized("WhiskyMac exception")
        case .kenneyLicense: localized("Kenney UI Audio license")
        case .kenneySource: localized("Kenney UI Audio source")
        case .sfxKitLicense: localized("SFX Kit license")
        case .sfxKitSource: localized("SFX Kit source")
        }
    }

    var overview: String {
        switch self {
        case .license:
            localized(
                "WhiskyMac uses the GNU GPL version 3 or later. Read the original for the complete terms.")
        case .notice:
            localized(
                "This notice names the original authors, WhiskyMac modifications and third-party materials.")
        case .thirdParty:
            localized(
                "This document lists third-party artwork and sounds, their licenses and sources.")
        case .appStoreException:
            localized(
                "The Whisk author grants additional App Store and TestFlight distribution permission.")
        case .whiskyMacException:
            localized(
                "The WhiskyMac author grants additional App Store and TestFlight permission for their work.")
        case .kenneyLicense:
            localized("Kenney UI Audio is provided under CC0. Open the original license for its full text.")
        case .kenneySource:
            localized("This document records the source and conversion details for the bundled Kenney UI sounds.")
        case .sfxKitLicense:
            localized("SFX Kit is provided under CC0. Open the original license for its full text.")
        case .sfxKitSource:
            localized("This document records the source and selected files for the bundled SFX Kit sounds.")
        }
    }

    var relativePath: String {
        switch self {
        case .license: "LICENSE"
        case .notice: "NOTICE"
        case .thirdParty: "THIRD_PARTY_NOTICES.md"
        case .appStoreException: "LICENSE-EXCEPTION-APP-STORE.md"
        case .whiskyMacException: "LICENSE-EXCEPTION-WHISKYMAC.md"
        case .kenneyLicense: "docs/licenses/Kenney-UI-Audio.txt"
        case .kenneySource: "docs/licenses/Kenney-UI-Audio-source.md"
        case .sfxKitLicense: "docs/licenses/SFX-Kit-CC0.txt"
        case .sfxKitSource: "docs/licenses/SFX-Kit-source.md"
        }
    }
}

enum LegalDocuments {
    static func directory(
        resourcesURL: URL? = Bundle.main.resourceURL,
        developmentRoot: URL? = Bundle.main.bundleURL.pathExtension == "app" ? nil : sourceRoot
    ) -> URL? {
        if let resourcesURL {
            let packaged = resourcesURL.appendingPathComponent("Legal", isDirectory: true)
            if FileManager.default.fileExists(atPath: packaged.path) { return packaged }
        }
        if let developmentRoot,
            FileManager.default.fileExists(atPath: developmentRoot.appendingPathComponent("LICENSE").path)
        {
            return developmentRoot
        }
        return nil
    }

    static func url(for document: LegalDocument, in directory: URL? = directory()) -> URL? {
        guard let directory else { return nil }
        let url = directory.appendingPathComponent(document.relativePath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static var sourceRoot: URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        return directory
    }
}

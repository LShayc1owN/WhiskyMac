// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation
import Testing

@testable import Whisk

@Suite struct PackagedResources {
    @Test(arguments: ["en", "fr", "de", "zh-Hans"])
    func localization_loads_from_a_relocated_app_contents_resources_directory(language: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("whisky-resource-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("original/WhiskyMac.app")
        let resources = original.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: Bundle.module.bundleURL, to: resources.appendingPathComponent(AppResources.name))
        let relocated = root.appendingPathComponent("relocated/WhiskyMac.app")
        try FileManager.default.createDirectory(
            at: relocated.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: original, to: relocated)

        let runtimeResources = relocated.appendingPathComponent("Contents/Resources")
        let bundle = try #require(AppResources.locate(in: [runtimeResources, relocated]))
        #expect(bundle.bundleURL == runtimeResources.appendingPathComponent(AppResources.name))
        let resource = try #require(
            bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: language))
        let translation = try #require(Bundle(url: resource.deletingLastPathComponent()))
        let expected = [
            "en": ["Copy", "1 item"], "fr": ["Copier", "1 élément"],
            "de": ["Kopieren", "1 Eintrag"], "zh-Hans": ["拷贝", "1 项"],
        ]
        #expect(localized("Copy", bundle: translation) == expected[language]?[0])
        #expect(localized("\(1) items", bundle: translation) == expected[language]?[1])
    }

    @Test func an_absent_resource_bundle_is_not_a_fatal_initialization() {
        #expect(AppResources.locate(in: [URL(fileURLWithPath: "/nonexistent/whisky-resource-test")]) == nil)
    }

    @Test func the_runtime_resolver_finds_the_catalogs_without_a_build_path() throws {
        #expect(AppResources.bundle.bundleURL.lastPathComponent == AppResources.name)
        for language in ["en", "fr", "de", "zh-Hans"] {
            #expect(
                AppResources.bundle.url(
                    forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: language)
                    != nil)
        }
        #expect(AppResources.bundle.url(forResource: "Localizable", withExtension: "xcstrings") == nil)
    }
}

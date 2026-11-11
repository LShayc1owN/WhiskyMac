// WhiskyMac: modified or added 2026-11-05 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation
import Testing

@testable import Whisk

@Suite struct LegalDocumentsTests {
    @Test func every_preview_document_has_a_source_file() throws {
        let directory = try #require(LegalDocuments.directory(resourcesURL: nil))
        for document in LegalDocument.allCases {
            let url = try #require(LegalDocuments.url(for: document, in: directory))
            #expect(!(try String(contentsOf: url, encoding: .utf8)).isEmpty)
        }
    }

    @Test func packaged_legal_files_take_priority_over_the_development_tree() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("whisky-legal-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = root.appendingPathComponent("WhiskyMac.app/Contents/Resources")
        let packaged = resources.appendingPathComponent("Legal")
        let development = root.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: packaged, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: development, withIntermediateDirectories: true)
        try "Packaged license".write(to: packaged.appendingPathComponent("LICENSE"), atomically: true, encoding: .utf8)
        try "Source license".write(to: development.appendingPathComponent("LICENSE"), atomically: true, encoding: .utf8)

        let directory = try #require(
            LegalDocuments.directory(resourcesURL: resources, developmentRoot: development))
        let url = try #require(LegalDocuments.url(for: .license, in: directory))
        #expect(url == packaged.appendingPathComponent("LICENSE"))
        #expect(try String(contentsOf: url, encoding: .utf8) == "Packaged license")
    }
}

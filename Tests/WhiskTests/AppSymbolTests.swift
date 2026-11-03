// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Testing

@testable import Whisk

@Suite @MainActor struct AppSymbolTests {
    @Test func custom_symbol_loads_from_the_resource_bundle() throws {
        let bundle = try #require(AppSymbol.bundle)
        let symbol = try #require(
            NSImage(symbolName: "WhiskyMac", bundle: bundle, variableValue: 0))
        #expect(symbol.size.width > 0 && symbol.size.height > 0)
        let image = try #require(AppSymbol.image())
        #expect(image.isTemplate)
        #expect(image.size.width > 0 && image.size.width <= 22)
        #expect(image.size.height > 0 && image.size.height <= 22)
    }

    @Test func custom_symbol_loads_after_the_bundle_is_relocated() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = root.appendingPathComponent("WhiskyMac.app/Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: AppResources.bundle.bundleURL, to: resources.appendingPathComponent(AppResources.name))
        let bundle = try #require(AppResources.locate(in: [resources]))
        let symbolsURL = try #require(bundle.url(forResource: "WhiskyMacSymbols", withExtension: "bundle"))
        let symbols = try #require(Bundle(url: symbolsURL))
        #expect(NSImage(symbolName: "WhiskyMac", bundle: symbols, variableValue: 0) != nil)
    }
}

// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Carbon.HIToolbox
import Foundation
import Testing

@testable import Whisk

@Suite struct MayIsolation {
    @Test func original_environment_and_files_are_untouched_by_may_launch() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("may-isolation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("Whisk", isDirectory: true)
        let may = root.appendingPathComponent("WhiskMay-Dev", isDirectory: true)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)

        let originalItem = anItem(.text("original"))
        try HistoryStorage.open(in: original, log: { _ in }).save([originalItem])
        let originalDatabase = original.appendingPathComponent(HistoryStorage.databaseName)
        let originalJSON = original.appendingPathComponent(HistoryStorage.legacyIndexName)
        try Data("original legacy JSON".utf8).write(to: originalJSON)
        let originalWAL = URL(fileURLWithPath: originalDatabase.path + "-wal")
        try Data("synthetic WAL sentinel".utf8).write(to: originalWAL)
        let before = try [originalDatabase, originalJSON, originalWAL].map { try Data(contentsOf: $0) }

        let selected = try HistoryStorage.defaultDirectory(environment: [
            "WHISK_DATA_DIR": original.path,
            "WHISK_MAY_DATA_DIR": may.path,
        ])
        #expect(selected == may)
        let mayItem = anItem(.text("may"))
        try HistoryStorage.open(in: selected, log: { _ in }).save([mayItem])
        #expect(try HistoryStorage.open(in: selected, log: { _ in }).load() == [mayItem])
        #expect(try [originalDatabase, originalJSON, originalWAL].map { try Data(contentsOf: $0) } == before)
        #expect(!FileManager.default.fileExists(atPath: may.appendingPathComponent("history.json").path))
        #expect(AppIdentity.importedIconsDirectory(in: may).deletingLastPathComponent() == may)
        #expect(AppIdentity.previewCacheDirectory(in: may).deletingLastPathComponent() == may)
    }

    @Test func original_settings_domain_does_not_seed_may_settings() throws {
        let original = try IsolatedDefaults()
        let may = try IsolatedDefaults()
        original.defaults.set(true, forKey: "checkForUpdates")
        original.defaults.set(true, forKey: "linkPreviews")
        original.defaults.set(true, forKey: "didShowOnboarding")
        original.defaults.set([KeyAction.togglePanel.rawValue], forKey: "enabledGlobalShortcuts")

        let settings = GeneralSettingsStore(defaults: may.defaults)
        let keys = KeyBindingsStore(defaults: may.defaults)
        #expect(!settings.checkForUpdates)
        #expect(!settings.linkPreviews)
        #expect(!may.defaults.bool(forKey: "didShowOnboarding"))
        #expect(keys.enabledGlobalActions.isEmpty)

        settings.capacity = 250
        keys.setGlobalEnabled(true, for: .togglePanel)
        #expect(GeneralSettingsStore(defaults: may.defaults).capacity == 250)
        #expect(KeyBindingsStore(defaults: may.defaults).isGlobalEnabled(.togglePanel))
        #expect(original.defaults.integer(forKey: "historyCapacity") == 0)
        #expect(original.defaults.stringArray(forKey: "enabledGlobalShortcuts") == ["togglePanel"])
    }

    @Test func recording_enables_only_the_recorded_global_shortcut() throws {
        let sandbox = try IsolatedDefaults()
        let keys = KeyBindingsStore(defaults: sandbox.defaults)
        #expect(!keys.isGlobalEnabled(.togglePanel))
        #expect(!keys.isGlobalEnabled(.pasteNextFromStack))

        keys.set(KeyBinding(keyCode: UInt16(kVK_ANSI_K), modifiers: [.command]), for: .togglePanel)
        #expect(keys.isGlobalEnabled(.togglePanel))
        #expect(!keys.isGlobalEnabled(.pasteNextFromStack))
        keys.setGlobalEnabled(false, for: .togglePanel)
        #expect(!KeyBindingsStore(defaults: sandbox.defaults).isGlobalEnabled(.togglePanel))
        keys.resetAll()
        #expect(KeyBindingsStore(defaults: sandbox.defaults).enabledGlobalActions.isEmpty)
    }
}

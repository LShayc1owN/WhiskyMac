import AppKit
import SwiftUI
import Testing

@testable import Whisk

@Suite @MainActor struct StatusSymbolSettingsTests {
    @Test func both_modes_have_independent_defaults_and_persist_changes() throws {
        let isolated = try IsolatedDefaults()
        let settings = AppearanceSettingsStore(defaults: isolated.defaults)
        #expect(settings.statusSymbolName(protected: false, paused: false) == "WhiskyMac")
        #expect(settings.statusSymbolName(protected: true, paused: false) == "LemonSlice")
        var changes = 0
        settings.changed = { changes += 1 }
        settings.defaultStatusSymbol = "star.fill"
        settings.privacyStatusSymbol = "lock.shield"
        #expect(changes == 2)
        let restored = AppearanceSettingsStore(defaults: isolated.defaults)
        #expect(restored.statusSymbolName(protected: false, paused: false) == "star.fill")
        #expect(restored.statusSymbolName(protected: true, paused: true) == "lock.shield")
        #expect(restored.statusSymbolName(protected: false, paused: true) == "pause.circle")
    }

    @Test func invalid_saved_symbols_fall_back_independently() throws {
        let isolated = try IsolatedDefaults()
        isolated.defaults.set("nonexistent.whisky.symbol", forKey: "defaultStatusSymbol")
        isolated.defaults.set("moon.fill", forKey: "privacyStatusSymbol")
        let settings = AppearanceSettingsStore(defaults: isolated.defaults)
        #expect(settings.defaultStatusSymbol == "WhiskyMac")
        #expect(settings.privacyStatusSymbol == "moon.fill")
    }

    @Test(arguments: AppSymbol.customNames)
    func custom_symbols_load_as_templates_at_status_bar_size(name: String) throws {
        let source = try #require(AppSymbol.sourceImage(named: name))
        #expect(source.size.width > 0)
        let image = try #require(AppSymbol.image(named: name))
        #expect(image.isTemplate)
        #expect(image.size.height > 0 && image.size.height <= 22)
    }

    @Test func library_includes_custom_and_system_symbols_and_searches_all_terms() {
        let names = SymbolCatalog.availableNames
        #expect(names.count > 5000)
        #expect(names.contains("WhiskyMac"))
        #expect(names.contains("LemonSlice"))
        #expect(names.contains("star.fill"))
        #expect(Set(names).count == names.count)
        #expect(SymbolCatalog.matching(names, query: " STAR FILL ").contains("star.fill"))
        #expect(SymbolCatalog.matching(names, query: "lemonslice") == ["LemonSlice"])
    }

    @Test func picker_renders_custom_and_system_selections() throws {
        _ = NSApplication.shared
        for name in ["WhiskyMac", "LemonSlice", "star.fill"] {
            let view = StatusSymbolPicker(title: "Menu bar icons", selection: .constant(name), defaultName: name)
            let renderer = ImageRenderer(content: view)
            #expect(renderer.nsImage != nil)
        }
    }
}

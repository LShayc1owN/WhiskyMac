import AppKit
import SwiftUI
import Testing

@testable import Whisk

@Suite @MainActor struct StatusSymbolSettingsTests {
    @Test func settings_brand_stays_whiskymac_when_status_icons_change() throws {
        _ = NSApplication.shared
        let isolated = try IsolatedDefaults()
        let settings = AppearanceSettingsStore(defaults: isolated.defaults)
        let host = NSHostingView(rootView: MacOS15SettingsBrandView(appearance: settings))
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 80)

        func imageViews(in view: NSView) -> [NSImageView] {
            (view as? NSImageView).map { [$0] } ?? view.subviews.flatMap { imageViews(in: $0) }
        }

        let brand = try #require(AppSymbol.image(named: "WhiskyMac", pointSize: 32))
        for name in ["LemonOpenSlice", "star.fill", "LemonFruit"] {
            settings.defaultStatusSymbol = name
            settings.privacyStatusSymbol = "CitrusLeaf"
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            let image = try #require(imageViews(in: host).first?.image)
            #expect(image.tiffRepresentation == brand.tiffRepresentation)
            #expect(settings.statusSymbolName(protected: false, paused: false) == name)
        }
    }

    @Test func both_modes_have_independent_defaults_and_persist_changes() throws {
        let isolated = try IsolatedDefaults()
        let settings = AppearanceSettingsStore(defaults: isolated.defaults)
        #expect(settings.statusSymbolName(protected: false, paused: false) == "LemonOpenSlice")
        #expect(settings.statusSymbolName(protected: true, paused: false) == "CitrusLeaf")
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
        #expect(settings.defaultStatusSymbol == "LemonOpenSlice")
        #expect(settings.privacyStatusSymbol == "moon.fill")
    }

    @Test(arguments: AppSymbol.customNames)
    func existing_custom_selections_remain_available_after_defaults_change(name: String) throws {
        let isolated = try IsolatedDefaults()
        isolated.defaults.set(name, forKey: "defaultStatusSymbol")
        isolated.defaults.set(name, forKey: "privacyStatusSymbol")
        let settings = AppearanceSettingsStore(defaults: isolated.defaults)
        #expect(settings.defaultStatusSymbol == name)
        #expect(settings.privacyStatusSymbol == name)
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
        #expect(names.contains("LemonOpenSlice"))
        #expect(names.contains("CitrusLeaf"))
        #expect(names.contains("LemonLeaf"))
        #expect(names.contains("LemonFruit"))
        #expect(names.contains("star.fill"))
        #expect(Set(names).count == names.count)
        #expect(SymbolCatalog.matching(names, query: " STAR FILL ").contains("star.fill"))
        #expect(SymbolCatalog.matching(names, query: "lemonslice") == ["LemonSlice"])
    }

    @Test func picker_renders_custom_and_system_selections() throws {
        _ = NSApplication.shared
        for name in AppSymbol.customNames + ["star.fill"] {
            let view = MacOS15StatusSymbolPicker(title: "Menu bar icons", selection: .constant(name), defaultName: name)
            let renderer = ImageRenderer(content: view)
            #expect(renderer.nsImage != nil)
        }
    }
}

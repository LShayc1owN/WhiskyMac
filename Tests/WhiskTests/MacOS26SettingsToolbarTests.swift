// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Testing

@testable import Whisk

@MainActor
@Suite(.serialized)
struct MacOS26SettingsToolbarTests {
    @Test(.enabled(if: ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26))
    func search_uses_a_native_toolbar_item_and_nonactivating_glass_results() async throws {
        guard #available(macOS 26, *) else { return }
        let fixture = try Fixture()
        let window = fixture.window
        defer { window.close() }

        let item = try #require(window.toolbar?.items.first { $0.itemIdentifier == MacOS26SettingsToolbar.itemID })
        #expect(item is NSSearchToolbarItem)
        #expect(fixture.toolbar.searchField.window === window)

        fixture.edit("shortcut")
        await settle(window)
        let panel = try #require(fixture.toolbar.resultsPanel)
        #expect(panel.parent === window)
        #expect(panel.isVisible)
        #expect(!panel.canBecomeKey && !panel.canBecomeMain)
        #expect(panel.contentView is NSGlassEffectView)
        let fieldFrame = window.convertToScreen(
            fixture.toolbar.searchField.convert(fixture.toolbar.searchField.bounds, to: nil))
        #expect(abs(panel.frame.minX - fieldFrame.minX) < 1)
        #expect(panel.frame.height == 480)

        let editor = NSTextView()
        #expect(fixture.command(#selector(NSResponder.moveDown(_:)), editor: editor))
        #expect(fixture.search.selectedIndex == 1)
        #expect(fixture.command(#selector(NSResponder.moveUp(_:)), editor: editor))
        #expect(fixture.search.selectedIndex == 0)
        let destination = try #require(fixture.search.results.first?.destination)
        #expect(fixture.command(#selector(NSResponder.insertNewline(_:)), editor: editor))
        await settle(window)
        #expect(fixture.search.destination == destination)
        #expect(fixture.toolbar.searchField.stringValue.isEmpty)
        #expect(!panel.isVisible)
        #expect(panel.parent == nil)

        fixture.edit("NONEXISTENTSEARCH123")
        await settle(window)
        #expect(panel.isVisible && fixture.search.results.isEmpty)
        #expect(panel.frame.height == 64)
        NotificationCenter.default.post(name: NSWindow.willBeginSheetNotification, object: window)
        #expect(!panel.isVisible)

        fixture.edit("card size")
        await settle(window)
        #expect(panel.isVisible)
        window.close()
        #expect(!panel.isVisible && fixture.search.query.isEmpty)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26))
    func layout_controls_stay_at_the_leading_edge_and_top_brand_stays_trailing() async throws {
        guard #available(macOS 26, *) else { return }
        let fixture = try Fixture()
        defer { fixture.window.close() }
        let toolbar = try #require(fixture.window.toolbar)
        let closeButton = try #require(fixture.window.standardWindowButton(.closeButton))
        let closeFrame = closeButton.convert(closeButton.bounds, to: nil)
        for navigation in SettingsNavigation.allCases {
            fixture.appearance.navigation = navigation
            await settle(fixture.window)
            #expect(
                toolbar.items.prefix(2).map(\.itemIdentifier) == [
                    MacOS26SettingsToolbar.navigationID, MacOS26SettingsToolbar.itemID,
                ])
            let field = fixture.toolbar.searchField
            let fieldFrame = field.convert(field.bounds, to: nil)
            #expect(fieldFrame.minX > closeFrame.maxX)
            #expect(fieldFrame.minX < 260)

            let brand = toolbar.items.first { $0.itemIdentifier == MacOS26SettingsToolbar.brandID }
            if navigation == .top {
                let host = try #require(brand?.view)
                let frame = host.convert(host.bounds, to: nil)
                #expect(frame.minX > fieldFrame.maxX)
                #expect(frame.maxX > fixture.window.frame.width - 90)
            } else {
                #expect(brand == nil)
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26))
    func native_search_field_fits_the_localized_prompt_at_maximum_size() async throws {
        guard #available(macOS 26, *) else { return }
        let original = AppLocalization.language
        defer { AppLocalization.language = original }
        let fixture = try Fixture()
        defer { fixture.window.close() }
        fixture.appearance.setInterfaceFontPercent(300)
        for language in AppLanguage.allCases {
            AppLocalization.language = language.code
            fixture.search.refresh(context: fixture.search.context)
            await settle(fixture.window)
            let field = fixture.toolbar.searchField
            let cell = try #require(field.cell as? NSSearchFieldCell)
            let font = try #require(field.font)
            let prompt = try #require(field.placeholderString) as NSString
            let rect = cell.searchTextRect(forBounds: field.bounds).intersection(field.visibleRect)
            #expect(prompt as String == localized("Search settings"))
            #expect(rect.width + 1 >= prompt.size(withAttributes: [.font: font]).width)
            #expect(rect.height + 2 >= font.ascender - font.descender)
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26))
    func layout_toggle_honors_the_recorder_and_search_commands_pass_through_to_ime() async throws {
        guard #available(macOS 26, *) else { return }
        let fixture = try Fixture()
        defer { fixture.window.close() }
        let item = try #require(
            fixture.window.toolbar?.items.first { $0.itemIdentifier == MacOS26SettingsToolbar.navigationID })
        let action = try #require(item.action)
        let original = fixture.appearance.navigation
        fixture.canFocus = false
        #expect(!fixture.toolbar.control(fixture.toolbar.searchField, textShouldBeginEditing: NSTextView()))
        #expect(NSApp.sendAction(action, to: item.target, from: item))
        #expect(fixture.appearance.navigation == original)
        fixture.canFocus = true
        #expect(fixture.toolbar.control(fixture.toolbar.searchField, textShouldBeginEditing: NSTextView()))
        #expect(NSApp.sendAction(action, to: item.target, from: item))
        #expect(fixture.appearance.navigation != original)

        fixture.edit("shortcuts")
        let composingEditor = ComposingEditor()
        #expect(!fixture.command(#selector(NSResponder.moveDown(_:)), editor: composingEditor))
        #expect(!fixture.command(#selector(NSResponder.insertNewline(_:)), editor: composingEditor))
        #expect(!fixture.command(#selector(NSResponder.cancelOperation(_:)), editor: composingEditor))
        #expect(fixture.search.isPresented && fixture.search.selectedIndex == 0)
        #expect(fixture.command(#selector(NSResponder.cancelOperation(_:)), editor: NSTextView()))
        #expect(!fixture.search.isPresented)
        #expect(fixture.search.query == "shortcuts")
    }

    private func settle(_ window: NSWindow) async {
        // Allow published changes and AppKit's toolbar updates to reach the window.
        window.displayIfNeeded()
        for _ in 0..<3 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    @available(macOS 26, *)
    @MainActor
    private final class Fixture {
        let window: NSWindow
        let search = SettingsSearchModel()
        private let sandbox: IsolatedDefaults
        let appearance: AppearanceSettingsStore
        lazy var toolbar = MacOS26SettingsToolbar(window: window, search: search, appearance: appearance) {
            [weak self] in self?.canFocus == true
        }
        var canFocus = true

        init() throws {
            _ = NSApplication.shared
            sandbox = try IsolatedDefaults()
            appearance = AppearanceSettingsStore(defaults: sandbox.defaults)
            window = NSWindow(
                contentRect: NSRect(x: -10_000, y: -10_000, width: 840, height: 520),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.titleVisibility = .hidden
            window.contentView = NSView()
            _ = toolbar
            window.orderFront(nil)
        }

        func edit(_ query: String) {
            toolbar.searchField.stringValue = query
            toolbar.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        }

        func command(_ selector: Selector, editor: NSTextView) -> Bool {
            toolbar.control(toolbar.searchField, textView: editor, doCommandBy: selector)
        }
    }

    private final class ComposingEditor: NSTextView {
        override func hasMarkedText() -> Bool { true }
    }
}

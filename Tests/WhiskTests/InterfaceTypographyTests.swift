// WhiskyMac: added 2026-11-25 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI
import Testing

@testable import Whisk

@MainActor
@Suite(.serialized) struct InterfaceTypographyTests {
    @Test func scale_persists_and_bounds_the_setting() throws {
        let fixture = try IsolatedDefaults()
        let settings = AppearanceSettingsStore(defaults: fixture.defaults)
        #expect(settings.interfaceTypography == .standard)
        settings.setInterfaceFontPercent(300)
        #expect(AppearanceSettingsStore(defaults: fixture.defaults).interfaceTypography.scale == 3)
        settings.setInterfaceFontPercent(10)
        #expect(settings.interfaceTypography.percent == InterfaceTypography.percentRange.lowerBound)
        settings.setInterfaceFontPercent(800)
        #expect(settings.interfaceTypography.percent == 300)
        settings.setInterfaceFontPercent(100)
        #expect(AppearanceSettingsStore(defaults: fixture.defaults).interfaceTypography == .standard)

        let entries = SettingsSearchIndex.entries(context: SettingsSearchContext())
        for id in ["interfaceFontSize", "interfaceFontPlainText"] {
            let entry = try #require(entries.first { $0.id == id })
            #expect(entry.destination == SettingsDestination(section: .colors, anchor: id))
        }
    }

    @Test func plain_text_preference_persists_independently_of_font_size() throws {
        let fixture = try IsolatedDefaults()
        let settings = AppearanceSettingsStore(defaults: fixture.defaults)
        #expect(settings.interfaceTypography.appliesToPlainText)
        settings.setInterfaceFontPercent(300)
        settings.setPlainTextFollowsInterface(false)
        let restored = AppearanceSettingsStore(defaults: fixture.defaults)
        #expect(restored.interfaceTypography.scale == 3)
        #expect(restored.interfaceTypography.plainText.scale == 1)
        restored.setInterfaceFontPercent(100)
        #expect(restored.interfaceTypography.isStandard)
        #expect(!restored.interfaceTypography.appliesToPlainText)
    }

    @Test func search_and_panel_reserve_room_for_the_enlarged_controls() {
        let larger = InterfaceTypography(percent: 300)
        #expect(larger.usesLargeLayout && InterfaceTypography.percentRange.upperBound == 300)
        let search = MacOS15ClipboardSearchMetrics(prompt: ClipboardSearchPrompt(count: 12_345), expanded: false)
        let scaled = MacOS15ClipboardSearchMetrics(
            prompt: ClipboardSearchPrompt(count: 12_345, typography: larger), expanded: false)
        #expect(scaled.minimumWidth > search.minimumWidth)
        let tags = MacOS15FilterTagMetrics(scale: 1, typography: larger)
        #expect(tags.rowHeight >= larger.lineHeight(tags.fontSize) + 2 * tags.verticalPadding)
        #expect(tags.rowHeight < larger.scale * MacOS15FilterTagMetrics(scale: 1).rowHeight)
        let normalHeight = MacOS15PanelLayout.panelHeight(forCardSide: 260)
        #expect(MacOS15PanelLayout.panelHeight(forCardSide: 260, typography: larger) > normalHeight)
        #expect(InterfaceTypography(percent: 85).room(28) == 28)
    }

    @Test func localized_fractional_card_sizes_fit_the_editable_field() async throws {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 120), styleMask: .borderless, backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        func textField(in view: NSView) -> NSTextField? {
            (view as? NSTextField) ?? view.subviews.lazy.compactMap(textField(in:)).first
        }
        for language in AppLanguage.allCases {
            let input = CardSizeInput(locale: language.code.map(Locale.init(identifier:)) ?? .current)
            let value = 499.875
            let field: AnyView
            if #available(macOS 26, *) {
                field = AnyView(
                    MacOS26NumericField(title: "pt", value: .constant(value), format: input.format, parse: input.parse))
            } else {
                field = AnyView(
                    MacOS15NumericField(title: "pt", value: .constant(value), format: input.format, parse: input.parse))
            }
            let host = NSHostingView(rootView: field.interfaceType(.standard))
            window.contentView = host
            for percent in [85, 100, 150, 151, 200, 250, 300] {
                let typography = InterfaceTypography(percent: percent)
                host.rootView = field.interfaceType(typography)
                await Task.yield()
                host.layoutSubtreeIfNeeded()
                let native = try #require(textField(in: host))
                let font = try #require(native.font)
                let context = Comment(rawValue: "\(language)-\(percent)")
                #expect(native.stringValue == input.format(value), context)
                #expect(font.pointSize >= typography.points(13) - 1, context)
                #expect(native.bounds.height >= typography.lineHeight(13) - 2, context)
                #expect(
                    native.bounds.width >= (native.stringValue as NSString).size(withAttributes: [.font: font]).width,
                    context)
            }
        }
    }

    @Test func plain_preview_updates_its_native_font_without_rewriting_the_text() throws {
        _ = NSApplication.shared
        let preview = MacOS15TextPreviewView.Surface(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let text = "Synthetic preview"
        preview.update(text: text, tokens: [], monospaced: false)
        let fontBefore = try #require(
            preview.textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        preview.update(text: text, tokens: [], monospaced: false, typography: InterfaceTypography(percent: 300))
        let fontAfter = try #require(
            preview.textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(fontAfter.pointSize == fontBefore.pointSize * 3)
        #expect(preview.textView.string == text)
        preview.update(
            text: text, tokens: [], monospaced: false,
            typography: InterfaceTypography(percent: 300, appliesToPlainText: false))
        let restoredFont = try #require(
            preview.textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(restoredFont.pointSize == fontBefore.pointSize)
        #expect(preview.textView.string == text)
    }

    @Test func rich_text_keeps_its_original_display_size_and_font_in_the_editor() throws {
        _ = NSApplication.shared
        let font = NSFont.boldSystemFont(ofSize: 17)
        let text = NSAttributedString(string: "Attributed fixture", attributes: [.font: font])
        let view = NSHostingView(
            rootView: MacOS15RichTextView(text: text, editable: true)
                .frame(width: 320, height: 200)
                .interfaceType(InterfaceTypography(percent: 300)))
        view.frame.size = CGSize(width: 320, height: 200)
        view.layoutSubtreeIfNeeded()
        func scrollView(in view: NSView) -> NSScrollView? {
            (view as? NSScrollView) ?? view.subviews.lazy.compactMap(scrollView).first
        }
        let scroll = try #require(scrollView(in: view))
        let editor = try #require(scroll.documentView as? NSTextView)
        #expect(scroll.magnification == 1)
        #expect(editor.attributedString().isEqual(to: text))
    }

    @Test func the_hiding_options_stay_within_the_screen_at_maximum_size() {
        _ = NSApplication.shared
        let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 680, height: 720)
        let host = NSHostingView(
            rootView: MacOS15HistoryHidingOptions(includesTypes: true, confirm: { _ in }, cancel: {})
                .interfaceType(InterfaceTypography(percent: 300)))
        let size = host.fittingSize
        #expect(size.width > 0 && size.width <= screen.width)
        #expect(size.height > 0 && size.height <= screen.height)
    }

    @Test func menu_status_message_uses_the_selected_font_size() throws {
        _ = NSApplication.shared
        let text = "WhiskyMac"
        let standard = try #require(MacOS15StatusMenuMessage.item(for: text).view)
        let enlarged = try #require(
            MacOS15StatusMenuMessage.item(for: text, typography: InterfaceTypography(percent: 300)).view)
        #expect(enlarged.frame.height > standard.frame.height)
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI
import Testing

@testable import Whisk

@MainActor
@Suite(.serialized) struct SettingsTypographyLayoutTests {
    @Test func compact_settings_keep_a_scrollable_detail_at_large_text_sizes() async throws {
        _ = NSApplication.shared
        let originalLanguage = AppLocalization.language
        defer { AppLocalization.language = originalLanguage }
        let sandbox = try IsolatedDefaults()
        let defaults = sandbox.defaults
        let appearance = AppearanceSettingsStore(defaults: defaults)
        let search = SettingsSearchModel()
        let size = NSSize(width: MacOS15SettingsWindowSize.width, height: MacOS15SettingsWindowSize.minimumHeight)
        let sampleSizes = [85, 100, 150, 151, 200, 250, 300]
        let exhaustive = ProcessInfo.processInfo.environment["WHISK_EXHAUSTIVE_TYPOGRAPHY"] == "1"
        let sizes = exhaustive ? Array(InterfaceTypography.percentRange) : sampleSizes
        let directory = ProcessInfo.processInfo.environment["WHISK_SETTINGS_TYPOGRAPHY_ARTIFACTS"]
            .map { URL(fileURLWithPath: $0) }
        if let directory { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        let context = SettingsUIContext(
            bindings: KeyBindingsStore(defaults: defaults), general: GeneralSettingsStore(defaults: defaults),
            loginItem: LoginItemManager(), vimBindings: VimBindingsStore(defaults: defaults),
            privacy: PrivacyController(defaults: defaults), appearance: appearance,
            updateChecker: UpdateChecker(defaults: defaults),
            search: search, developerMode: DeveloperModeStore(defaults: defaults, channel: .debug))
        let handle = AppUISelector.make().makeSettingsWindow(context: context, initialPage: .appearance)
        let surface = try #require(handle.window.contentView as? TestHostingSurface)
        let root = surface.renderedRoot
            .environment(\.settingsAccessibilityOverride, SettingsAccessibilityValues(reduceMotion: true))
        handle.release()
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: root)
        window.contentView = host
        host.frame.size = size

        let requestedLanguage = ProcessInfo.processInfo.environment["WHISK_TYPOGRAPHY_LANGUAGE"]
        let languages = AppLanguage.allCases.filter { requestedLanguage == nil || $0.rawValue == requestedLanguage }
        try #require(!languages.isEmpty)
        let requestedSection = ProcessInfo.processInfo.environment["WHISK_TYPOGRAPHY_SECTION"]
        let sections: [SettingsSectionID] =
            requestedSection != nil || exhaustive || directory != nil
            ? SettingsSectionID.allCases.filter { requestedSection == nil || $0.rawValue == requestedSection }
            : [.colors]
        try #require(!sections.isEmpty)
        for language in languages {
            AppLocalization.language = language.code
            appearance.language = language
            for navigation in SettingsNavigation.allCases {
                appearance.navigation = navigation
                for section in sections {
                    let anchor = section == .colors ? "interfaceFontSize" : nil
                    search.navigate(to: SettingsDestination(section: section, anchor: anchor))
                    await Task.yield()
                    for percent in sizes where exhaustive || section == .colors || percent == 300 {
                        appearance.setInterfaceFontPercent(percent)
                        host.layoutSubtreeIfNeeded()
                        await Task.yield()
                        host.layoutSubtreeIfNeeded()
                        let context = "\(language.rawValue)-\(navigation.rawValue)-\(percent)-\(section.rawValue)"
                        let scroll = try #require(detailScroll(in: host), Comment(rawValue: context))
                        #expect(scroll.contentView.bounds.height >= 130, Comment(rawValue: context))
                        #expect(
                            scroll.contentView.documentRect.width <= scroll.contentView.bounds.width + 1,
                            Comment(rawValue: context))
                        if let directory, sampleSizes.contains(percent) {
                            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                            host.cacheDisplay(in: host.bounds, to: bitmap)
                            let png = try #require(
                                bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:]))
                            try png.write(to: directory.appendingPathComponent(context + ".png"))
                            if percent == 300,
                                [.aboutApp, .cards, .sensitiveAccess, .screenSharingProtection].contains(section)
                            {
                                let clip = scroll.contentView
                                let original = clip.bounds.origin
                                for page in 1...3 {
                                    clip.scroll(to: NSPoint(x: 0, y: clip.bounds.height * CGFloat(page)))
                                    scroll.reflectScrolledClipView(clip)
                                    host.layoutSubtreeIfNeeded()
                                    host.cacheDisplay(in: host.bounds, to: bitmap)
                                    let image = try #require(bitmap.representation(using: .png, properties: [:]))
                                    try image.write(
                                        to: directory.appendingPathComponent("\(context)-scroll-\(page).png"))
                                }
                                clip.scroll(to: original)
                                scroll.reflectScrolledClipView(clip)
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func translation_credits_keep_contributors_with_their_languages() {
        let groups = TranslationCredits.byLanguage
        #expect(groups.map(\.language) == AppLanguage.allCases.filter { $0 != .system })
        for group in groups {
            #expect(group.products.contains { $0.product.title == "ChatGPT" && $0.provider.title == "OpenAI" })
            #expect(group.humans.contains { $0.name == "LinShay 琳曦" } == (group.language == .simplifiedChinese))
        }
    }

    @Test func symbol_picker_keeps_the_catalog_search_and_actions_reachable() async throws {
        _ = NSApplication.shared
        let original = AppLocalization.language
        defer { AppLocalization.language = original }
        let name = "rectangle.and.hand.point.up.left.filled"
        let environment = ProcessInfo.processInfo.environment
        let directory = environment["WHISK_SYMBOL_TYPOGRAPHY_ARTIFACTS"].map { URL(fileURLWithPath: $0) }
        if let directory { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        let percentages =
            environment["WHISK_EXHAUSTIVE_TYPOGRAPHY"] == "1"
            ? Array(InterfaceTypography.percentRange) : [85, 100, 150, 151, 200, 250, 300]
        for language in AppLanguage.allCases {
            AppLocalization.language = language.code
            let title = localized("Privacy mode icon")
            let picker: AnyView
            if #available(macOS 26, *) {
                picker = AnyView(MacOS26StatusSymbolPicker(title: title, selection: .constant(name), defaultName: name))
            } else {
                picker = AnyView(MacOS15StatusSymbolPicker(title: title, selection: .constant(name), defaultName: name))
            }
            let host = NSHostingView(rootView: picker.interfaceType(.standard))
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: host.fittingSize),
                styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.close() }
            for percent in percentages {
                let typography = InterfaceTypography(percent: percent)
                host.rootView = picker.interfaceType(typography)
                await Task.yield()
                host.layoutSubtreeIfNeeded()
                let context = "\(language.rawValue)-\(percent)"
                let comment = Comment(rawValue: context)
                let scroll = try #require(detailScroll(in: host), comment)
                let frame = host.convert(scroll.bounds, from: scroll)
                #expect(host.bounds.insetBy(dx: -1, dy: -1).contains(frame), comment)
                #expect(scroll.contentSize.height >= 2 * typography.lineHeight(13), comment)
                #expect(scroll.contentView.documentRect.width <= scroll.contentSize.width + 1, comment)
                #expect(host.bounds.height - frame.height >= typography.lineHeight(13) * 3, comment)
                if let directory, [100, 300].contains(percent) {
                    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    let png = try #require(bitmap.representation(using: .png, properties: [:]))
                    try png.write(to: directory.appendingPathComponent(context + ".png"))
                }
            }
        }
    }

    @Test func pending_size_actions_fit_native_buttons_and_reflow_together() async throws {
        _ = NSApplication.shared
        let previous = AppLocalization.language
        defer { AppLocalization.language = previous }
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }

        func editor(changed: Bool, width: CGFloat, type: InterfaceTypography) -> NSView {
            let draft = Binding.constant(SizeSettingDraft(proposedValue: changed ? 240 : nil))
            let saved: Double = changed ? 260 : 240
            let content = Group {
                if #available(macOS 26, *) {
                    MacOS26SizeSettingEditor(
                        title: localized("Card size"), savedValue: saved, defaultValue: 240,
                        range: 180...320, draft: draft, save: { _ in }, previewOnScreen: {}
                    ) { EmptyView() }
                } else {
                    MacOS15SizeSettingEditor(
                        title: localized("Card size"), savedValue: saved, defaultValue: 240,
                        range: 180...320, draft: draft, save: { _ in }, previewOnScreen: {}
                    ) { EmptyView() }
                }
            }
            .interfaceType(type)
            .padding(16)
            .frame(width: width)
            .background(Color(nsColor: .windowBackgroundColor))
            return NSHostingView(rootView: content)
        }
        for language in ["zh-Hans", "de"] {
            AppLocalization.language = language
            for percent in [85, 100, 150, 300] {
                let type = InterfaceTypography(percent: percent)
                func actionHeight(at width: CGFloat) -> CGFloat {
                    let clean = editor(changed: false, width: width, type: type)
                    let changed = editor(changed: true, width: width, type: type)
                    return changed.fittingSize.height - clean.fittingSize.height - 16
                }
                let row = actionHeight(at: 1800)
                let compact = actionHeight(at: 468)
                #expect(row >= type.lineHeight(13) + type.points(4) - 1)
                if language == "zh-Hans", percent <= 100 { #expect(abs(compact - row) <= 1) }
                if percent == 300 || (language == "de" && percent == 100) { #expect(compact >= 2 * row + 7) }

                if let path = ProcessInfo.processInfo.environment["WHISK_SIZE_ACTION_ARTIFACTS"] {
                    let host = editor(changed: true, width: 468, type: type)
                    window.contentView = host
                    window.setContentSize(host.fittingSize)
                    host.layoutSubtreeIfNeeded()
                    await Task.yield()
                    let image = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: image)
                    let url = URL(fileURLWithPath: path).appendingPathComponent("\(language)-\(percent).png")
                    try image.representation(using: .png, properties: [:])?.write(to: url)
                }
            }
        }
    }

    @Test func long_action_titles_gain_a_second_line_when_width_is_limited() {
        let button = Button("Auf dem Bildschirm ansehen", systemImage: "macwindow") {}
        let typography = InterfaceTypography(percent: 300)
        let wide = NSHostingView(rootView: button.macOS15SettingsAction().interfaceType(typography).frame(width: 800))
        let narrow = NSHostingView(rootView: button.macOS15SettingsAction().interfaceType(typography).frame(width: 440))
        #expect(narrow.fittingSize.height >= wide.fittingSize.height + typography.lineHeight(13) * 0.7)
    }

    @Test func scaled_settings_menus_keep_the_selection_and_native_actions() async throws {
        _ = NSApplication.shared
        var selected = 1
        let typography = InterfaceTypography(percent: 300)
        let options = Picker("Mode", selection: Binding(get: { selected }, set: { selected = $0 })) {
            Section("Modes") {
                Text("First").tag(1)
                Text("Second").tag(2)
            }
        }
        .pickerStyle(.inline)
        let menu = SettingsMenuPresenter.menu(options, typography: typography)
        menu.update()
        await Task.yield()
        #expect(menu.font?.pointSize == typography.menuFont.pointSize)
        let titles = menu.items.map(\.title)
        #expect(titles.contains("First"))
        let second = try #require(titles.firstIndex(of: "Second"))
        menu.performActionForItem(at: second)
        #expect(selected == 2)
    }

    private func detailScroll(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView, scroll.bounds.width > 400, scroll.bounds.height > 110 {
            return scroll
        }
        return view.subviews.lazy.compactMap(detailScroll(in:)).first
    }
}

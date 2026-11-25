// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI
import Testing

@testable import Whisk

@MainActor
@Suite(.serialized) struct HistoryPanelTypographyTests {
    @Test func small_screen_keeps_the_editor_rail_and_permission_actions_reachable() async throws {
        _ = NSApplication.shared
        let saved = AppLocalization.language
        defer { AppLocalization.language = saved }
        let environment = ProcessInfo.processInfo.environment
        let sizes =
            environment["WHISK_EXHAUSTIVE_TYPOGRAPHY"] == "1"
            ? Array(InterfaceTypography.percentRange) : [85, 100, 150, 151, 200, 250, 300]
        let directory = environment["WHISK_PANEL_TYPOGRAPHY_ARTIFACTS"].map { URL(fileURLWithPath: $0) }
        if let directory { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }

        let factory = AppUISelector.make()
        let frame = NSRect(x: 0, y: 0, width: 1024, height: 640)
        let screen = PanelLayout.Screen(frame: frame, visibleFrame: frame.insetBy(dx: 0, dy: 24), notchHeight: 0)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let item = anItem(.text("Sample text for the document area."))
        let filters = FilterContext(chips: ViewFixtures.chipRow())

        for language in AppLanguage.allCases {
            AppLocalization.language = language.code
            let store = HistoryViewStateStore()
            store.configureCards(side: 160)
            store.configureFilterTags(scale: 2)
            store.setPanelVisible(true)
            let session = store.sensitiveSession
            session.setRetention(minutes: 60)
            session.setPanelVisible(true)
            session.receive(PasteboardSnapshot(payload: .image(Data([0])), source: nil))
            session.receive(PasteboardSnapshot(payload: .text("Synthetic sample"), source: nil))
            let host = factory.makeHistoryContent(
                context: HistoryUIContext(store: store, actions: PanelActionSpy().actions), presentation: .history)
            window.contentView = host
            defer { window.contentView = nil }
            let presenter = HistoryPresenter()

            store.setPrivacyPermissions(
                allowSearch: true, showSourceApps: true, allowFiltering: true, allowAppFiltering: true)
            for mode in ["rail", "editor", "hidden-history", "requires-consent", "denied", "protected"] {
                store.setPrivacy(mode == "protected")
                store.endEditing()
                let access: PasteboardAccess =
                    mode == "denied" ? .denied : mode == "requires-consent" ? .requiresConsent : .granted
                let hasCards = ["rail", "editor", "protected"].contains(mode)
                store.update(
                    presenter.present(
                        items: hasCards ? [item] : [], query: "", now: .now, filters: filters,
                        clipboardAccess: access, isHistoryHidden: mode == "hidden-history"))
                if mode == "editor" { store.beginEditing(try #require(store.state.cards.first)) }

                for percent in sizes {
                    let typography = InterfaceTypography(percent: percent)
                    store.interfaceTypography = typography
                    let layout = factory.panelLayout(
                        screen: screen, cardSide: store.cardSide, tagScale: store.filterTagScale,
                        typography: typography, showsSensitiveCopies: mode != "protected")
                    window.setContentSize(layout.panel.size)
                    await Task.yield()
                    host.layoutSubtreeIfNeeded()
                    host.displayIfNeeded()
                    let context = "\(language.rawValue)-\(percent)-\(mode)"
                    let comment = Comment(rawValue: context)
                    let scrolls = descendants(host).compactMap { $0 as? NSScrollView }
                    let field = try #require(descendants(host).compactMap { $0 as? NSTextField }.first, comment)
                    let header = try #require(scrolls.first { field.isDescendant(of: $0) }, comment)
                    let headerFrame = host.convert(header.bounds, from: header)
                    #expect(host.bounds.insetBy(dx: -1, dy: -1).contains(headerFrame), comment)
                    #expect(header.contentSize.height >= typography.lineHeight(14) * 2, comment)
                    #expect(header.contentView.documentRect.width <= header.contentSize.width + 1, comment)

                    if mode == "editor" {
                        let editor = try #require(scrolls.first { $0.documentView is NSTextView }, comment)
                        let editorFrame = host.convert(editor.bounds, from: editor)
                        #expect(!editorFrame.intersects(headerFrame), comment)
                        #expect(host.bounds.insetBy(dx: -1, dy: -1).contains(editorFrame), comment)
                        #expect(editor.contentSize.height >= typography.lineHeight(13) * 2, comment)
                    } else if mode == "rail" || mode == "protected" {
                        let rail = try #require(
                            scrolls.first { $0 !== header && !$0.isDescendant(of: header) }, comment)
                        let railFrame = host.convert(rail.bounds, from: rail)
                        #expect(!railFrame.intersects(headerFrame), comment)
                        #expect(host.bounds.insetBy(dx: -1, dy: -1).contains(railFrame), comment)
                        #expect(rail.contentSize.height >= min(store.cardSide, typography.room(100)) - 2, comment)
                    } else if let prompt = store.state.accessPrompt {
                        let font = NSFont.systemFont(ofSize: typography.points(13), weight: .semibold)
                        let labelWidth = min(layout.panel.width, 680) - 96 - font.pointSize
                        let title = (prompt.buttonTitle as NSString).boundingRect(
                            with: CGSize(width: labelWidth, height: .greatestFiniteMagnitude),
                            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
                        let remaining = host.bounds.height - headerFrame.height - 66
                        #expect(remaining >= ceil(title.height) + typography.lineHeight(13) + 34, comment)
                    }

                    if let directory, [100, 300].contains(percent) {
                        try snapshot(host, to: directory.appendingPathComponent(context + ".png"))
                        if percent == 300, mode == "editor" {
                            let clip = header.contentView
                            clip.scroll(to: NSPoint(x: 0, y: clip.documentRect.maxY - clip.bounds.height))
                            header.reflectScrolledClipView(clip)
                            host.layoutSubtreeIfNeeded()
                            try snapshot(host, to: directory.appendingPathComponent(context + "-scrolled.png"))
                            clip.scroll(to: .zero)
                            header.reflectScrolledClipView(clip)
                        }
                    }
                }
            }
        }
    }

    @Test func temporary_previews_wrap_and_disappear_when_the_reveal_ends() async throws {
        _ = NSApplication.shared
        let original = AppLocalization.language
        defer { AppLocalization.language = original }
        let directory = ProcessInfo.processInfo.environment["WHISK_PANEL_TYPOGRAPHY_ARTIFACTS"]
            .map { URL(fileURLWithPath: $0) }
        if let directory { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        let window = NSWindow(
            contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        var now: TimeInterval = 0
        let session = SensitiveSessionStore(now: { now }, schedulesTimer: false)
        session.setPanelVisible(true)
        let word = String(repeating: "Example ", count: 65)
        let link = try #require(URL(string: "https://example.invalid/" + String(repeating: "example-path/", count: 55)))
        let samples: [(String, Payload)] = [
            ("text", .text(word)), ("link", .link(link)),
            ("files", .fileReferences((1...16).map { "/sample/folder/document-\($0).txt" })), ("image", .image(Data())),
        ]

        for language in AppLanguage.allCases {
            AppLocalization.language = language.code
            for percent in [85, 151, 300] {
                let typography = InterfaceTypography(percent: percent)
                let root: AnyView
                if #available(macOS 26, *) {
                    root = AnyView(MacOS26SensitiveSessionView(session: session).interfaceType(typography))
                } else {
                    root = AnyView(MacOS15SensitiveSessionView(session: session).interfaceType(typography))
                }
                let host = NSHostingView(rootView: root)
                host.sizingOptions = []
                window.contentView = host
                window.setContentSize(CGSize(width: 480, height: 190))
                for (kind, payload) in samples {
                    session.clear()
                    session.receive(PasteboardSnapshot(payload: payload, source: nil))
                    let id = try #require(session.ids.first)
                    func scrolls() async throws -> [NSScrollView] {
                        try await Task.sleep(for: .milliseconds(16))
                        host.layoutSubtreeIfNeeded()
                        host.displayIfNeeded()
                        return descendants(host).compactMap { $0 as? NSScrollView }
                    }
                    let context = "\(language.rawValue)-\(percent)-sensitive-\(kind)"
                    let comment = Comment(rawValue: context)
                    #expect(try await scrolls().count == 1, comment)
                    session.reveal(id)
                    let visible = try await scrolls()
                    let body = try #require(visible.last, comment)
                    #expect(visible.count == 2, comment)
                    #expect(body.contentSize.height >= typography.lineHeight(13) * 1.5, comment)
                    #expect(body.contentView.documentRect.width <= body.contentSize.width + 1, comment)
                    #expect(
                        host.bounds.insetBy(dx: -1, dy: -1).contains(host.convert(body.bounds, from: body)), comment)
                    if kind != "image" {
                        #expect(body.contentView.documentRect.height > body.contentSize.height, comment)
                    }
                    #expect(!descendants(host).contains { $0 is NSTextView }, comment)
                    if let directory, percent == 300 {
                        try snapshot(host, to: directory.appendingPathComponent(context + ".png"))
                    }
                    now += SensitiveSessionStore.revealDuration
                    session.sweep()
                    #expect(session.revealedPayload(id) == nil, comment)
                    #expect(try await scrolls().count == 1, comment)
                    session.setProtected(true)
                    #expect(try await scrolls().isEmpty, comment)
                    session.setProtected(false)
                }
            }
        }
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func snapshot(_ host: NSView, to url: URL) throws {
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }
}

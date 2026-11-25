// WhiskyMac: modified or added 2026-11-05 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI
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

    @MainActor @Test func original_scrolls_inside_the_reader_and_reopens_at_the_top() async throws {
        _ = NSApplication.shared
        let search = SettingsSearchModel()
        let window = NSWindow(
            contentRect: CGRect(x: -10000, y: 0, width: 540, height: 560),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let pageContent = MacOS15SettingsSearchScrollView(search: search, section: .licenses) {
            MacOS15LegalSettingsView()
        }
        let host = NSHostingView(rootView: pageContent.interfaceType(.standard))
        host.sizingOptions = []
        window.contentView = host

        func settle() async throws {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(60))
            host.layoutSubtreeIfNeeded()
        }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func reader() throws -> NSScrollView {
            try #require(descendants(host).compactMap { $0 as? NSScrollView }.first { $0.enclosingScrollView != nil })
        }
        try await settle()
        let overview = try reader()
        #expect(overview.contentSize.height > 300)
        let modes = try #require(descendants(host).compactMap { $0 as? NSSegmentedControl }.first)
        func selectMode(_ index: Int) async throws {
            modes.selectedSegment = index
            let action = try #require(modes.action)
            #expect(modes.sendAction(action, to: modes.target))
            try await settle()
        }
        try await selectMode(1)
        let original = try reader()
        let page = try #require(original.enclosingScrollView)
        #expect(page.contentView.documentRect.height <= page.contentSize.height + 1)
        let clip = original.contentView
        let originalHeight = clip.documentRect.height
        #expect(originalHeight > 3 * clip.bounds.height)
        clip.scroll(to: NSPoint(x: 0, y: clip.documentRect.maxY - clip.bounds.height))
        original.reflectScrolledClipView(clip)
        #expect(clip.bounds.minY > clip.bounds.height)
        #expect(abs(page.contentView.bounds.minY) < 1)
        let documents = try #require(descendants(host).compactMap { $0 as? NSPopUpButton }.first)
        let menu = try #require(documents.menu)
        let notice = try #require(menu.items.firstIndex { $0.title == LegalDocument.notice.title })
        menu.performActionForItem(at: notice)
        try await settle()
        let shorter = try reader()
        #expect(abs(shorter.contentView.bounds.minY) < 1)
        #expect(shorter.contentView.documentRect.height < originalHeight)
        try await selectMode(0)
        try await selectMode(1)
        #expect(abs(try reader().contentView.bounds.minY) < 1)

        host.rootView = pageContent.interfaceType(InterfaceTypography(percent: 300))
        window.setContentSize(CGSize(width: 500, height: 360))
        try await settle()
        let enlarged = try reader()
        let compactPage = try #require(enlarged.enclosingScrollView)
        #expect(enlarged.contentSize.height >= InterfaceTypography(percent: 300).lineHeight(13) * 4)
        #expect(enlarged.contentView.documentRect.height > enlarged.contentSize.height)
        #expect(compactPage.contentView.documentRect.height > compactPage.contentSize.height)
        #expect(compactPage.contentView.documentRect.width <= compactPage.contentSize.width + 1)
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

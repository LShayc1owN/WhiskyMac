// WhiskyMac: modified or added 2026-11-17 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI
import Testing

@testable import Whisk

@MainActor
@Suite(.serialized) struct FilterAppCollapseTests {
    private final class Model: ObservableObject {
        let scope = FilterAppScope(visibleSourceKeys: ["app-0", "app-1"])
        @Published var visible = true
        @Published var focus: String?
        let apps = (0..<50).map { "app-\($0)" }
        var filters: FilterBarViewState {
            func chip(_ id: String, label: String? = nil) -> FilterChip {
                FilterChip(
                    id: id, label: label ?? id, sourceBundleID: nil, accessibilityLabel: id,
                    isActive: false, isFocused: focus == id)
            }
            return FilterBarViewState(
                all: [chip("all", label: "全部")],
                apps: apps.map { chip($0) }, kinds: [chip("text", label: "文本"), chip("image", label: "图像")])
        }
    }

    private struct Row: View {
        @ObservedObject var model: Model
        var body: some View {
            FilterBarView(
                filters: model.filters, appScope: model.scope, isPanelVisible: model.visible,
                onToggleApp: { _ in }, onToggleKind: { _ in }, onFocusApp: { _ in }, onFocusKind: { _ in }
            )
            .transaction { $0.disablesAnimations = true }
        }
    }

    @Test func default_is_collapsed_expand_keeps_types_and_reopen_returns_to_the_start() throws {
        _ = NSApplication.shared
        let model = Model()
        let host = NSHostingView(rootView: Row(model: model))
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: 0, width: 600, height: 60), styleMask: .borderless,
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        func settle() {
            for _ in 0..<8 {
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.025))
            }
        }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        settle()
        let scroll = try #require(descendants(host).compactMap { $0 as? NSScrollView }.first)
        let document = try #require(scroll.documentView)
        let collapsedWidth = document.frame.width
        let initialOffset = scroll.contentView.bounds.minX
        #expect(!model.scope.isExpanded)
        #expect(initialOffset < 1)
        #expect(collapsedWidth < 1000)
        #expect(descendants(scroll).filter { $0 is BackdropView }.count == 5)

        model.scope.isExpanded = true
        settle()
        #expect(document.frame.width > collapsedWidth * 5)
        model.focus = "image"
        settle()
        #expect(scroll.contentView.bounds.minX > 3000, "The uncollapsed type chip must remain keyboard-reachable")
        model.visible = false
        settle()
        model.visible = true
        settle()
        #expect(!model.scope.isExpanded)
        #expect(abs(scroll.contentView.bounds.minX - initialOffset) < 1)
        #expect(document.frame.width == collapsedWidth)
        #expect(descendants(scroll).filter { $0 is BackdropView }.count == 5)

        model.scope.update(["app-5"])
        settle()
        #expect(document.frame.width <= collapsedWidth)
        #expect(descendants(scroll).filter { $0 is BackdropView }.count == 4)
        if let output = ProcessInfo.processInfo.environment["WHISK_UI_ARTIFACTS"] {
            let directory = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(
                to: directory.appendingPathComponent("collapsed-filter-apps.png"))
        }
    }
}

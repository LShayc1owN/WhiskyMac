// WhiskyMac: modified or added 2026-11-10 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI
import Testing

@testable import Whisk

@MainActor
@Suite struct CardActionMenuTests {
    private func card(
        pinned: Bool = false, hidden: Bool = false, splitCount: Int = 0,
        transformable: Bool = true, variants: Bool = false
    ) -> CardViewState {
        var card = CardViewState(
            id: UUID(), sourceLabel: "接力内容（系统标记）", sourceBundleID: "com.example.app",
            kindLabel: "文本", timeLabel: "刚刚", isPinned: pinned, isSelected: true,
            accessibilityLabel: "合成内容", accessibilityValue: "", dragPayload: .text("Synthetic"),
            transformable: transformable, saveable: true, sourceKey: "source:example",
            preview: .text("Synthetic"),
            pinnedMetadata: PinnedMetadata(hidesContent: hidden), splitCount: splitCount)
        if variants { card.variantIDs = [UUID(), UUID()] }
        return card
    }

    @Test func menu_keeps_split_available_but_respects_hidden_groups_and_pinned_scope() {
        func commands(_ card: CardViewState, pinnedWorkspace: Bool = false) -> [CardMenuCommand] {
            CardActionMenu.sections(for: card, pinnedWorkspace: pinnedWorkspace).flatMap { $0 }
        }
        let plain = commands(card())
        #expect(plain.prefix(3) == [.copy, .paste, .preview])
        #expect(plain.contains(.split) && plain.contains(.pasteAs))
        #expect(plain.last == .delete)
        #expect(commands(card(transformable: false, variants: true)).contains(.split))
        let hidden = commands(card(pinned: true, hidden: true))
        #expect(hidden.contains(.copy) && hidden.contains(.paste) && hidden.contains(.pinDetails))
        #expect(!hidden.contains(.split) && !hidden.contains(.preview) && !hidden.contains(.edit))
        let group = commands(card(splitCount: 3))
        #expect(!group.contains(.split) && !group.contains(.edit) && !group.contains(.stack))
        #expect(!group.contains(.save))
        #expect(!commands(card(pinned: true), pinnedWorkspace: true).contains(.deleteSource))
    }

    @Test func menu_fits_a_real_popover_width_with_long_source_text() throws {
        _ = NSApplication.shared
        let item = card()
        let spy = PanelActionSpy()
        let sandbox = try IsolatedDefaults()
        let view = CardActionMenu(
            card: item, actions: spy.actions, keyBindings: KeyBindingsStore(defaults: sandbox.defaults),
            perform: { _ in }, editPinnedItem: {}, dismiss: {}
        )
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 312, height: 550),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: view)
        host.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 312, height: 550)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.displayIfNeeded()
        #expect(host.fittingSize.width <= 312)
        #expect(host.fittingSize.height < 480, "Menu should hug its rows instead of keeping empty bottom space")
        if let output = ProcessInfo.processInfo.environment["WHISK_UI_ARTIFACTS"] {
            let target = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(
                to: target.appendingPathComponent("card-action-menu.png"))
        }
    }
}

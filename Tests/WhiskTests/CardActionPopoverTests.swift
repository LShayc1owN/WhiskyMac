// WhiskyMac: modified or added 2026-11-19 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import CoreGraphics
import SwiftUI
import Testing

@testable import Whisk

@MainActor
@Suite(.serialized) struct CardActionPopoverTests {
    private final class Model: ObservableObject {
        @Published var presented = true
        @Published var mounted = true
        @Published var detailed = false
        var builds = 0
    }

    private struct Bridge: View {
        @ObservedObject var model: Model
        let ordering: CardPopoverCoordinator
        var body: some View {
            Group {
                if model.mounted {
                    Color.clear.frame(width: 200, height: 100)
                        .macOS15CardActionPopover(isPresented: $model.presented) {
                            let _ = model.builds += 1
                            VStack {
                                Text("Synthetic editor")
                                if model.detailed { Text("Additional controls").frame(height: 120) }
                                Button("Done") { model.presented = false }
                            }.padding().frame(width: 304)
                        }
                }
            }
            .environment(\.cardPopoverCoordinator, ordering)
        }
    }

    @Test func swiftui_bridge_resizes_handles_escape_and_cleans_up_removed_anchors() async throws {
        _ = NSApplication.shared
        let model = Model()
        model.presented = false
        let ordering = CardPopoverCoordinator()
        let owner = FloatingPanel()
        MacOS15UIFactory().configure(window: owner, for: .history)
        owner.appearance = AppearanceMode.dark.nsAppearance
        owner.keepsOpenOnResignKey = { ordering.presentationID != nil }
        owner.setFrame(NSRect(x: -10000, y: -10000, width: 500, height: 300), display: false)
        let host = NSHostingView(rootView: Bridge(model: model, ordering: ordering))
        host.sizingOptions = []
        owner.contentView = host
        owner.keyHandler = { ordering.handleKey($0) }
        owner.orderFront(nil)
        defer { ordering.dismiss(); owner.contentView = nil; owner.close() }
        await settle(host)
        model.detailed = true
        await settle(host)
        #expect(model.builds == 0 && ordering.menuWindow == nil)
        model.detailed = false
        model.presented = true
        await settle(host)
        let menu = try #require(ordering.menuWindow)
        #expect(model.builds > 0)
        #expect(menu.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        owner.appearance = AppearanceMode.light.nsAppearance
        await settle(host)
        #expect(menu.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua)
        let initialHeight = menu.frame.height
        model.detailed = true
        await settle(host)
        #expect(ordering.menuWindow === menu && menu.frame.height > initialHeight + 100)
        owner.sendEvent(try key(53, "\u{1b}", window: owner))
        #expect(!model.presented)
        await settle(host)
        #expect(!model.presented)
        #expect(ordering.menuWindow == nil)
        #expect(owner.isVisible)

        model.presented = true
        await settle(host)
        let replacement = try #require(ordering.menuWindow)
        model.mounted = false
        await settle(host)
        #expect(!replacement.isVisible && !model.presented && ordering.presentationID == nil)
        model.mounted = true
        model.presented = true
        await settle(host)
        #expect(ordering.menuWindow?.isVisible == true)
        owner.close()
        #expect(!model.presented && ordering.presentationID == nil)
    }

    @Test func real_popovers_stay_above_a_reordered_preview_and_close_with_the_owner() async throws {
        _ = NSApplication.shared
        let state = HistoryViewStateStore()
        let ordering = CardPopoverCoordinator()
        ordering.presentationChanged = { state.cardMenuOpen = $0 }
        let owner = FloatingPanel()
        MacOS15UIFactory().configure(window: owner, for: .history)
        owner.keyHandler = { ordering.handleKey($0) }
        owner.keepsOpenOnResignKey = { state.cardMenuOpen }
        // Normal regression runs use offscreen windows. A local WindowServer
        // probe also verifies occlusion where the user could actually see it.
        let checksOcclusion = ProcessInfo.processInfo.environment["WHISK_CHECK_VISIBLE_WINDOW_ORDER"] == "1"
        var ownerFrame = NSRect(x: -10000, y: -10000, width: 500, height: 300)
        if checksOcclusion {
            let screen = try #require(NSScreen.main).visibleFrame
            ownerFrame.origin = NSPoint(x: screen.midX - 250, y: screen.midY - 150)
        }
        owner.setFrame(ownerFrame, display: false)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        owner.contentView = root
        let anchor = NSView(frame: NSRect(x: 100, y: 30, width: 200, height: 100))
        root.addSubview(anchor)
        let preview = NSPanel(
            contentRect: ownerFrame,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        preview.isReleasedWhenClosed = false
        preview.level = .statusBar
        preview.contentView = NSHostingView(rootView: Text("Synthetic preview").frame(width: 500, height: 300))
        let item = anItem(.text("Synthetic menu content"))
        let card = try #require(HistoryPresenter().present(items: [item], query: "", now: Date()).cards.first)
        let spy = PanelActionSpy()
        var performed: [CardAction] = []
        let coordinator = MacOS15CardActionPopover<AnyView>.Coordinator()
        coordinator.anchor = anchor
        coordinator.ordering = ordering
        coordinator.reduceMotion = true
        var presented = false
        coordinator.binding = Binding(get: { presented }, set: { presented = $0 })
        owner.onClose = {
            coordinator.close(restoreFocus: false); preview.orderOut(nil)
        }
        defer {
            coordinator.close(restoreFocus: false)
            owner.onClose = nil
            owner.close(); preview.close()
        }

        var previousPopover: NSPopover?
        for previewFirst in [true, false, true] {
            owner.orderFront(nil)
            if previewFirst { preview.orderFront(nil) }
            ordering.previewWindow = preview
            coordinator.content = AnyView(
                MacOS15CardActionMenu(
                    card: card, actions: spy.actions, perform: { performed.append($0) }, editPinnedItem: {},
                    dismiss: { coordinator.close() }
                ).environment(\.cardPopoverCoordinator, ordering))
            presented = true
            coordinator.synchronize()
            try await Task.sleep(for: .milliseconds(200))
            let menu = try #require(ordering.menuWindow)
            if let previousPopover {
                coordinator.popoverDidClose(Notification(name: NSPopover.didCloseNotification, object: previousPopover))
            }
            previousPopover = coordinator.popover
            #expect(coordinator.popover?.isShown == true && menu.isVisible && state.cardMenuOpen)
            #expect(owner.isVisible && menu.frame.width >= 304 && menu.frame.height > 100)
            preview.setFrame(menu.frame, display: true)
            preview.orderFront(nil)
            ordering.previewWindow = preview
            #expect(menu.level.rawValue > preview.level.rawValue)
            #expect(menu.frame.intersects(preview.frame))
            try await expectMenu(menu, above: preview, checkingOcclusion: checksOcclusion)
            #expect(menu.contentView?.hitTest(NSPoint(x: 30, y: 30)) != nil)
            if !previewFirst {
                owner.sendEvent(try key(125, "\u{f701}", window: owner))
                try await Task.sleep(for: .milliseconds(80))
                owner.sendEvent(try key(36, "\r", window: owner))
                try await Task.sleep(for: .milliseconds(80))
                #expect(
                    performed == [.paste],
                    "key=\(menu.isKeyWindow), responder=\(String(describing: menu.firstResponder))")
            } else {
                for _ in 0..<6 {
                    owner.sendEvent(try key(125, "\u{f701}", window: owner))
                    try await Task.sleep(for: .milliseconds(30))
                }
                owner.sendEvent(try key(36, "\r", window: owner))
                try await Task.sleep(for: .milliseconds(100))
                #expect(presented && state.cardMenuOpen, "The format submenu must keep the popover open")
                owner.sendEvent(try key(53, "\u{1b}", window: owner))
                try await Task.sleep(for: .milliseconds(100))
                #expect(presented && state.cardMenuOpen, "Escape must return from formats before closing")
                coordinator.outsideInteraction(in: preview)
            }
            #expect(!presented && !state.cardMenuOpen && coordinator.popover == nil)
            #expect(owner.isVisible && preview.isVisible)
        }
        presented = true
        coordinator.content = AnyView(Text("Synthetic menu").padding())
        coordinator.synchronize()
        try await Task.sleep(for: .milliseconds(100))
        coordinator.outsideInteraction(in: nil)
        #expect(!owner.isVisible && !preview.isVisible && !state.cardMenuOpen && !presented)
    }

    private func expectMenu(_ menu: NSWindow, above preview: NSWindow, checkingOcclusion: Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(2)
        let options: CGWindowListOption = checkingOcclusion ? .optionOnScreenOnly : .optionAll
        let ids = [menu.windowNumber, preview.windowNumber]
        var order: [Int] = []
        var levels: [Int: Int] = [:]
        repeat {
            let snapshot = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
            levels.removeAll(keepingCapacity: true)
            order.removeAll(keepingCapacity: true)
            for row in snapshot ?? [] {
                guard let number = row[kCGWindowNumber as String] as? Int, ids.contains(number),
                    let layer = row[kCGWindowLayer as String] as? Int
                else { continue }
                levels[number] = layer
                order.append(number)
            }
            if let front = levels[menu.windowNumber], let back = levels[preview.windowNumber], front > back,
                !checkingOcclusion || order == ids
            {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        } while clock.now < deadline
        Issue.record("WindowServer layers \(levels), order \(order), expected menu above preview \(ids)")
    }

    private func settle(_ host: NSView) async {
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        try? await Task.sleep(for: .milliseconds(350))
        host.layoutSubtreeIfNeeded()
    }

    private func key(_ code: UInt16, _ characters: String, window: NSWindow) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
    }
}

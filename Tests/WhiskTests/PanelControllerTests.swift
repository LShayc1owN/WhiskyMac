// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Carbon.HIToolbox
import Testing

@testable import Whisk

/// The panel's windows, created but never ordered in: nothing here puts
/// anything on screen.
@MainActor
@Suite struct PanelWindowing {
    @Test func action_popover_stays_above_preview_when_attached_or_reused_without_taking_focus() {
        _ = NSApplication.shared
        let layer = CardActionPopoverLayer.LayerView()
        let first = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 300),
            styleMask: .borderless, backing: .buffered, defer: false)
        let second = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 300),
            styleMask: .borderless, backing: .buffered, defer: false)
        first.isReleasedWhenClosed = false
        second.isReleasedWhenClosed = false
        defer { first.close(); second.close() }

        first.contentView = layer
        #expect(first.level.rawValue > NSWindow.Level.statusBar.rawValue)
        #expect(!first.isVisible && !first.isKeyWindow)
        #expect(layer.hitTest(.zero) == nil)

        // Moving between popover windows must apply the same policy again.
        first.contentView = nil
        layer.updateWindowLevel()
        second.contentView = layer
        #expect(second.level.rawValue > NSWindow.Level.statusBar.rawValue)

        second.level = .popUpMenu
        layer.updateWindowLevel()
        #expect(second.level == .popUpMenu)
        #expect(!second.isVisible && !second.isKeyWindow)
    }

    @Test func the_floating_panel_hands_keys_to_its_handler_and_closes_on_the_second_cancel() throws {
        _ = NSApplication.shared
        let panel = FloatingPanel()
        var handled: [UInt16] = []
        var cancels = 0
        var closes = 0
        panel.keyHandler = { event in
            handled.append(event.keyCode)
            return true
        }
        panel.onCancel = {
            cancels += 1
            return cancels == 1
        }
        panel.onClose = { closes += 1 }
        let press = try #require(aKeyEvent(kVK_ANSI_H, typing: "h"))

        panel.sendEvent(press)
        panel.cancelOperation(nil)
        panel.cancelOperation(nil)
        panel.resignKey()

        #expect(handled == [UInt16(kVK_ANSI_H)])
        #expect(panel.canBecomeKey)
        #expect(cancels == 2)
        #expect(closes == 0)
        #expect(!panel.isVisible)
    }

    @Test func the_panel_rises_on_the_screen_under_the_pointer_or_the_primary_one() {
        let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let secondary = CGRect(x: 1920, y: 200, width: 1440, height: 900)

        #expect(PanelController.screenIndex(under: CGPoint(x: 100, y: 100), frames: [primary, secondary]) == 0)
        #expect(PanelController.screenIndex(under: CGPoint(x: 2500, y: 600), frames: [primary, secondary]) == 1)
        #expect(PanelController.screenIndex(under: CGPoint(x: -50, y: 5000), frames: [primary, secondary]) == 0)
        #expect(PanelController.screenIndex(under: .zero, frames: []) == nil)
    }

    @Test func the_panel_controller_hides_idempotently_and_ignores_drags_while_hidden() throws {
        _ = NSApplication.shared
        let sandbox = try IsolatedDefaults()
        let store = HistoryViewStateStore()
        let spy = PanelActionSpy()
        let controller = PanelController(
            stateStore: store, actions: spy.actions, keyBindings: KeyBindingsStore(defaults: sandbox.defaults),
            vimBindings: VimBindingsStore(defaults: sandbox.defaults), vimMode: { false })

        controller.hide()
        controller.dragDidBegin()
        controller.hide()

        #expect(spy.calls.isEmpty)
        #expect(store.closeRevision == 0)
    }

    @Test func a_display_change_while_the_panel_is_hidden_touches_nothing() throws {
        _ = NSApplication.shared
        let sandbox = try IsolatedDefaults()
        let store = HistoryViewStateStore()
        let spy = PanelActionSpy()
        let controller = PanelController(
            stateStore: store, actions: spy.actions, keyBindings: KeyBindingsStore(defaults: sandbox.defaults),
            vimBindings: VimBindingsStore(defaults: sandbox.defaults), vimMode: { false })

        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)

        #expect(spy.calls.isEmpty)
        #expect(store.closeRevision == 0)
        #expect(store.focusRevision == 0)
        withExtendedLifetime(controller) {}
    }
}

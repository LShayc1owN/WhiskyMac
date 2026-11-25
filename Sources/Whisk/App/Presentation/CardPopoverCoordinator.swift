// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

final class CardPopoverCoordinator {
    private(set) var presentationID: UUID?
    private(set) weak var menuWindow: NSWindow?
    private(set) weak var ownerWindow: NSWindow?
    private weak var keyboard: CardPopoverKeyboard?
    weak var previewWindow: NSWindow? { didSet { maintainOrder() } }
    var presentationChanged: (Bool) -> Void = { _ in }
    private var closePresentation: ((Bool) -> Void)?

    func begin(_ id: UUID, owner: NSWindow, keyboard: CardPopoverKeyboard, close: @escaping (Bool) -> Void) {
        if presentationID != id { dismiss() }
        presentationID = id
        ownerWindow = owner
        self.keyboard = keyboard
        closePresentation = close
        presentationChanged(true)
    }

    func didShow(_ window: NSWindow, id: UUID) {
        guard presentationID == id else { return }
        menuWindow = window
        window.appearance = ownerWindow?.appearance
        maintainOrder()
    }

    func maintainOrder() {
        guard let menuWindow, menuWindow.isVisible else { return }
        let highestContentLevel = max(
            ownerWindow?.level.rawValue ?? NSWindow.Level.statusBar.rawValue,
            previewWindow?.level.rawValue ?? NSWindow.Level.statusBar.rawValue)
        menuWindow.level = NSWindow.Level(rawValue: max(menuWindow.level.rawValue, highestContentLevel + 1))
        menuWindow.orderFront(nil)
    }

    func end(_ id: UUID) {
        guard presentationID == id else { return }
        presentationID = nil
        menuWindow = nil
        ownerWindow = nil
        keyboard = nil
        closePresentation = nil
        presentationChanged(false)
    }

    func dismiss(restoreFocus: Bool = false) { closePresentation?(restoreFocus) }

    func handleKey(_ event: NSEvent) -> Bool {
        guard presentationID != nil,
            event.modifierFlags.intersection([.command, .control, .option]).isEmpty
        else { return false }
        if keyboard?.handle(event.keyCode) == true { return true }
        if event.keyCode == 53 { dismiss(restoreFocus: true); return true }
        return false
    }

    func contains(_ window: NSWindow?) -> Bool {
        var candidate = window
        while let current = candidate {
            if current === ownerWindow || current === menuWindow || current === previewWindow { return true }
            candidate = current.parent
        }
        return false
    }
}

final class CardPopoverKeyboard {
    private var registration: UUID?
    private var handler: ((UInt16) -> Bool)?
    func install(_ id: UUID, handler: @escaping (UInt16) -> Bool) {
        registration = id
        self.handler = handler
    }
    func remove(_ id: UUID) {
        guard registration == id else { return }
        registration = nil
        handler = nil
    }
    func handle(_ keyCode: UInt16) -> Bool { handler?(keyCode) ?? false }
    func reset() { registration = nil; handler = nil }
}

extension EnvironmentValues {
    @Entry var cardPopoverCoordinator: CardPopoverCoordinator? = nil
    @Entry var cardPopoverKeyboard: CardPopoverKeyboard? = nil
}

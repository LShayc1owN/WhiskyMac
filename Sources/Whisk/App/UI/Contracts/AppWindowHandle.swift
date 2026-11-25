// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

/// Toolbar delegates and observers live exactly as long as their window owner.
@MainActor
final class AppWindowHandle {
    let window: NSWindow
    private var retainedObjects: [AnyObject]
    private var prepare: (() -> Void)?

    init(
        window: NSWindow, retaining objects: [AnyObject] = [],
        prepare: @escaping () -> Void = {}
    ) {
        self.window = window
        retainedObjects = objects
        self.prepare = prepare
    }

    func prepareForPresentation() { prepare?() }

    func release() {
        guard prepare != nil else { return }
        prepare = nil
        window.close()
        window.toolbar?.delegate = nil
        window.toolbar = nil
        window.contentViewController = nil
        window.contentView = nil
        retainedObjects.removeAll()
    }
}

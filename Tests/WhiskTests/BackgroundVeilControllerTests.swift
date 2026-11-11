// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Testing

@testable import Whisk

@MainActor
@Suite struct BackgroundVeilLifecycle {
    @MainActor
    private final class Fixture {
        struct Animation {
            let alpha: CGFloat
            let duration: TimeInterval
            let complete: () -> Void
        }

        var creations = 0
        var orderedBelow: [Int] = []
        var animations: [Animation] = []
        var reduceTransparency = false
        var reduceMotion = false
        weak var lastWindow: NSPanel?
        weak var lastContent: NSView?
        var controller: BackgroundVeilController?
        let frame = NSRect(x: 100, y: 50, width: 1512, height: 430)

        init() {
            _ = NSApplication.shared
            controller = BackgroundVeilController(
                makeWindow: { [weak self] in
                    let window = BackgroundVeilController.makeWindow()
                    self?.creations += 1
                    self?.lastWindow = window
                    self?.lastContent = window.contentView
                    return window
                },
                orderBelow: { [weak self] _, number in self?.orderedBelow.append(number) },
                animateAlpha: { [weak self] window, alpha, duration, complete in
                    window.alphaValue = alpha
                    self?.animations.append(Animation(alpha: alpha, duration: duration, complete: complete))
                },
                reduceTransparency: { [weak self] in self?.reduceTransparency ?? false },
                reduceMotion: { [weak self] in self?.reduceMotion ?? false }
            )
        }

        func show() {
            controller?.show(frame: frame, belowWindowNumber: 42)
        }
    }

    @Test func hidden_operations_never_create_a_background() {
        let f = Fixture()
        f.controller?.updateFrame(f.frame)
        f.controller?.hide()
        f.controller?.fadeForDrag()
        f.controller?.accessibilityDidChange()

        #expect(f.creations == 0)
        #expect(f.controller?.window == nil)
        #expect(f.animations.isEmpty && f.orderedBelow.isEmpty)
    }

    @Test func showing_creates_one_background_with_the_existing_visual_configuration() throws {
        let f = Fixture()
        f.show()
        let window = try #require(f.controller?.window)

        #expect(window.frame == f.frame)
        #expect(window.level == .statusBar && window.isFloatingPanel)
        #expect(window.collectionBehavior == [.canJoinAllSpaces, .fullScreenAuxiliary])
        #expect(window.ignoresMouseEvents && !window.isOpaque && !window.hasShadow)
        #expect(!window.isReleasedWhenClosed && !window.isVisible)
        #expect(f.animations.last?.alpha == 1 && f.animations.last?.duration == 0.22)
        #expect(f.orderedBelow == [42])
        f.show()
        #expect(f.creations == 1 && f.controller?.window === window)
    }

    @Test func closing_waits_for_the_fade_then_releases_window_and_content() throws {
        let f = Fixture()
        var complete: (() -> Void)?
        try autoreleasepool {
            f.show()
            f.controller?.hide()
            #expect(f.controller?.window != nil && f.lastContent != nil)
            #expect(f.animations.last?.alpha == 0 && f.animations.last?.duration == 0.22)
            let count = f.animations.count
            f.controller?.hide()
            #expect(f.animations.count == count)
            complete = try #require(f.animations.last?.complete)
            complete?()
        }

        #expect(f.controller?.window == nil)
        #expect(f.lastWindow == nil && f.lastContent == nil)
        complete?()
        #expect(f.controller?.window == nil)
    }

    @Test func a_stale_close_cannot_dispose_a_reopened_or_new_background() throws {
        let f = Fixture()
        f.show()
        let original = try #require(f.controller?.window)
        f.controller?.hide()
        let oldClose = try #require(f.animations.last?.complete)
        f.show()
        #expect(f.creations == 1 && f.controller?.window === original)
        oldClose()
        #expect(f.controller?.window === original)

        f.controller?.hide()
        let currentClose = try #require(f.animations.last?.complete)
        oldClose()
        #expect(f.controller?.window != nil)
        currentClose()
        #expect(f.controller?.window == nil)
        f.show()
        #expect(f.creations == 2)
        currentClose()
        oldClose()
        #expect(f.controller?.window != nil)
    }

    @Test func a_finished_drag_fade_keeps_the_window_until_drag_end_then_releases_immediately() throws {
        let f = Fixture()
        f.show()
        f.controller?.fadeForDrag()
        #expect(f.animations.last?.duration == 0.18 && f.animations.last?.alpha == 0)
        #expect(f.controller?.window != nil)
        let dragComplete = try #require(f.animations.last?.complete)
        dragComplete()
        #expect(f.controller?.window != nil)
        let count = f.animations.count
        f.controller?.hide()
        #expect(f.controller?.window == nil && f.animations.count == count)
    }

    @Test func a_drag_target_alpha_of_zero_does_not_mean_its_fade_has_finished() throws {
        let f = Fixture()
        f.show()
        f.controller?.fadeForDrag()
        let dragComplete = try #require(f.animations.last?.complete)
        #expect(f.controller?.window?.alphaValue == 0)
        f.controller?.hide()
        let closeComplete = try #require(f.animations.last?.complete)
        #expect(f.animations.last?.duration == 0.22 && f.controller?.window != nil)
        dragComplete()
        #expect(f.controller?.window != nil)
        closeComplete()
        #expect(f.controller?.window == nil)
    }

    @Test func a_stale_drag_completion_cannot_make_a_reopened_background_disappear() throws {
        let f = Fixture()
        f.show()
        f.controller?.fadeForDrag()
        let dragComplete = try #require(f.animations.last?.complete)
        f.show()
        dragComplete()
        f.controller?.hide()
        #expect(f.controller?.window != nil && f.animations.last?.duration == 0.22)
        let closeComplete = try #require(f.animations.last?.complete)
        closeComplete()
        #expect(f.controller?.window == nil)
    }

    @Test func display_changes_only_resize_an_existing_background() {
        let f = Fixture()
        let moved = NSRect(x: 1800, y: 100, width: 1920, height: 480)
        f.controller?.updateFrame(moved)
        #expect(f.creations == 0)
        f.show()
        f.controller?.updateFrame(moved)
        #expect(f.controller?.window?.frame == moved)
        #expect(f.creations == 1 && f.orderedBelow == [42])
    }

    @Test func reducing_transparency_skips_creation_and_disposes_a_pending_fade() throws {
        let f = Fixture()
        f.reduceTransparency = true
        f.show()
        #expect(f.creations == 0)
        f.reduceTransparency = false
        f.show()
        f.controller?.hide()
        let oldClose = try #require(f.animations.last?.complete)
        f.reduceTransparency = true
        f.controller?.accessibilityDidChange()
        #expect(f.controller?.window == nil)
        f.reduceTransparency = false
        f.show()
        oldClose()
        #expect(f.creations == 2 && f.controller?.window != nil)
    }

    @Test func reducing_motion_shows_and_releases_without_animation() {
        let f = Fixture()
        f.reduceMotion = true
        f.show()
        #expect(f.controller?.window?.alphaValue == 1 && f.animations.isEmpty)
        f.controller?.hide()
        #expect(f.controller?.window == nil && f.animations.isEmpty)
    }

    @Test func reducing_motion_during_a_drag_or_close_finishes_the_pending_transition() throws {
        let f = Fixture()
        f.show()
        f.controller?.fadeForDrag()
        let dragComplete = try #require(f.animations.last?.complete)
        f.reduceMotion = true
        f.controller?.accessibilityDidChange()
        #expect(f.controller?.window?.alphaValue == 0)
        f.controller?.hide()
        #expect(f.controller?.window == nil)
        f.reduceMotion = false
        f.show()
        f.controller?.hide()
        let closeComplete = try #require(f.animations.last?.complete)
        f.reduceMotion = true
        f.controller?.accessibilityDidChange()
        #expect(f.controller?.window == nil)
        dragComplete()
        closeComplete()
        #expect(f.controller?.window == nil)
    }

    @Test func destroying_the_owner_releases_its_window_even_with_a_pending_animation() throws {
        let f = Fixture()
        var complete: (() -> Void)?
        try autoreleasepool {
            f.show()
            f.controller?.hide()
            complete = try #require(f.animations.last?.complete)
            f.controller = nil
        }
        #expect(f.lastWindow == nil && f.lastContent == nil)
        complete?()
    }

    @Test func repeated_open_close_cycles_leave_no_window_or_content_owned() {
        let f = Fixture()
        f.reduceMotion = true
        for _ in 0..<30 {
            autoreleasepool {
                f.show()
                f.controller?.hide()
            }
            #expect(f.controller?.window == nil)
            #expect(f.lastWindow == nil && f.lastContent == nil)
        }
        #expect(f.creations == 30)
    }
}

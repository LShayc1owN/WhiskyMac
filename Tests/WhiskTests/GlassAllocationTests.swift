// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI
import Testing

@testable import Whisk

@Suite struct CardRailBounds {
    @Test func a_seven_card_viewport_keeps_twelve_slots_instead_of_twenty_four() {
        let window = CardRailWindow(leading: 50, capacity: 7)
        #expect((0..<1000).filter { window.contains($0, selectedIndex: nil) } == Array(48...59))
        #expect((0..<1000).filter { window.contains($0, selectedIndex: 0) }.count == 13)
        #expect(CardRailWindow(leading: 0, capacity: 7).contains(0, selectedIndex: nil))
    }

    @Test func fast_jumps_resize_the_window_and_keep_a_distant_keyboard_target() {
        for capacity in [1, 7, 20] {
            for leading in [0, 50, 500, 999] {
                let window = CardRailWindow(leading: leading, capacity: capacity)
                #expect(window.contains(leading, selectedIndex: nil))
                #expect(window.contains(3, selectedIndex: 3))
                #expect((0..<1000).filter { window.contains($0, selectedIndex: 3) }.count <= capacity + 6)
            }
        }
    }
}

@MainActor
@Suite struct StretchableGlassMasks {
    private func view(radius: CGFloat?) -> BackdropView {
        _ = NSApplication.shared
        let view = BackdropView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        view.wantsLayer = true
        view.cornerRadius = radius
        view.layout()
        return view
    }

    @Test func sixty_card_zoom_steps_reuse_one_small_mask_and_its_raster() throws {
        let view = view(radius: 18)
        let mask = try #require(view.maskImage)
        let representations = mask.representations.map(ObjectIdentifier.init)
        #expect(mask.size == NSSize(width: 37, height: 37))
        #expect(mask.capInsets.top == 18 && mask.resizingMode == .stretch)
        for step in 1...60 {
            let side = 200 + CGFloat(step) / 6
            view.setFrameSize(NSSize(width: side, height: side))
            view.layout()
            #expect(view.maskImage === mask)
            #expect(mask.representations.map(ObjectIdentifier.init) == representations)
        }
        print("Card zoom: 60 geometry changes, mask replacements=0, raster replacements=0")
    }

    @Test func capsule_zoom_and_search_width_changes_reuse_the_same_raster() throws {
        let view = view(radius: nil)
        view.setFrameSize(NSSize(width: 140, height: 30))
        view.layout()
        let mask = try #require(view.maskImage)
        let representations = mask.representations.map(ObjectIdentifier.init)
        for step in 0...60 {
            let zoom = 1 + CGFloat(step) / 1000
            view.setFrameSize(NSSize(width: 140 * zoom, height: 30 * zoom))
            view.layout()
            #expect(view.maskImage === mask)
            #expect(abs(mask.capInsets.top - 15 * zoom) < 0.0001)
            #expect(mask.representations.map(ObjectIdentifier.init) == representations)
        }
        for width: CGFloat in [480, 500, 600, 680, 480] {
            view.setFrameSize(NSSize(width: width, height: 38))
            view.layout()
            #expect(view.maskImage === mask && mask.capInsets.top == 19)
            #expect(mask.representations.map(ObjectIdentifier.init) == representations)
        }
        print("Capsule zoom: 60 geometry changes, mask replacements=0, raster replacements=0")
    }

    @Test func corner_style_changes_regenerate_once_and_small_or_zero_bounds_are_safe() throws {
        let view = view(radius: 18)
        let first = try #require(view.maskImage)
        view.cornerRadius = 24
        view.layout()
        let second = try #require(view.maskImage)
        #expect(second !== first && second.capInsets.left == 24)
        view.setFrameSize(NSSize(width: 20, height: 10))
        view.layout()
        #expect(view.maskImage === second && second.capInsets.top == 5)
        view.setFrameSize(.zero)
        view.layout()
        #expect(view.maskImage === second)
        view.cornerRadius = nil
        view.setFrameSize(NSSize(width: 10, height: 40))
        view.layout()
        #expect(view.maskImage !== second && view.maskImage?.capInsets.top == 5)
        view.cornerRadius = 0
        view.layout()
        #expect(view.maskImage?.size == NSSize(width: 1, height: 1))
    }

    @Test func masks_keep_transparent_corners_and_an_opaque_center() throws {
        let view = view(radius: 18)
        let mask = try #require(view.maskImage)
        let image = try #require(mask.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bitmap = NSBitmapImageRep(cgImage: image)
        #expect((bitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.05)
        #expect((bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.alphaComponent ?? 0) > 0.95)
    }
}

@MainActor
@Suite struct CardGlassMounting {
    @Test func native_card_glass_stays_bounded_after_large_scroll_jumps() throws {
        _ = NSApplication.shared
        let store = HistoryViewStateStore()
        let items = (0..<200).map { anItem(.text("Plain clipboard item \($0)")) }
        store.update(HistoryPresenter().present(items: items, query: "", now: Date(), selectedID: items[0].id))
        store.setPanelVisible(true)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1512, height: 430),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: HistoryPanelView(store: store, actions: PanelActionSpy().actions))
        host.sizingOptions = []
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
        let scroll = try #require(
            descendants(host).compactMap { $0 as? NSScrollView }.max {
                ($0.documentView?.frame.width ?? 0) < ($1.documentView?.frame.width ?? 0)
            })
        for index in [50, 100, 20, 0] {
            scroll.contentView.scroll(to: NSPoint(x: CGFloat(index) * store.cardStride, y: 0))
            scroll.reflectScrolledClipView(scroll.contentView)
            settle()
            let glass = descendants(scroll).filter { $0 is BackdropView }.count
            #expect(glass > 0 && glass <= 13)
            print("Card rail at \(index): native glass=\(glass)")
        }
        for index in [150, 3, 180, 0] {
            store.update(HistoryPresenter().present(items: items, query: "", now: Date(), selectedID: items[index].id))
            for _ in 0..<8 {
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.025))
                let glass = descendants(scroll).filter { $0 is BackdropView }.count
                #expect(glass > 0 && glass <= 13)
            }
        }
    }
}

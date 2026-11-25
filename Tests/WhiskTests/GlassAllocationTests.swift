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
    @Test func adjacent_cards_share_the_live_mask_and_the_veil_preserves_each_alpha_row() throws {
        let cards = (0..<12).map { _ in view(radius: 18) }
        let masks = cards.compactMap(\.maskImage)
        #expect(masks.count == cards.count && Set(masks.map(ObjectIdentifier.init)).count == 1)
        let veil = MacOS15GradientVeilView()
        let size = NSSize(width: 1512, height: 440)
        veil.setFrameSize(size)
        veil.layout()
        let strip = try #require(veil.maskImage)
        #expect(strip.size == NSSize(width: 3, height: size.height))
        let full = NSImage(size: size)
        full.lockFocus()
        NSGradient(colorsAndLocations: (.white, 0), (.white, 0.75), (.white.withAlphaComponent(0), 1))?
            .draw(in: NSRect(origin: .zero, size: size), angle: 90)
        full.unlockFocus()
        let stretched = NSImage(size: size)
        stretched.lockFocus()
        strip.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        stretched.unlockFocus()
        func bitmap(_ image: NSImage) throws -> NSBitmapImageRep {
            NSBitmapImageRep(cgImage: try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil)))
        }
        let before = try bitmap(full)
        let after = try bitmap(stretched)
        #expect(before.pixelsHigh == after.pixelsHigh && before.pixelsWide == after.pixelsWide)
        var maxDifference: CGFloat = 0
        for x in [0, before.pixelsWide / 2, before.pixelsWide - 1] {
            for y in 0..<before.pixelsHigh {
                let expected = try #require(before.colorAt(x: x, y: y)).alphaComponent
                let actual = try #require(after.colorAt(x: x, y: y)).alphaComponent
                maxDifference = max(maxDifference, abs(expected - actual))
            }
        }
        #expect(maxDifference <= 1.0 / 255 + 0.00001)
        veil.setFrameSize(NSSize(width: 2560, height: size.height))
        veil.layout()
        #expect(veil.maskImage === strip)
        veil.setFrameSize(NSSize(width: 1512, height: 400))
        veil.layout()
        #expect(veil.maskImage !== strip && veil.maskImage?.size.height == 400)
    }

    @Test func native_veil_stretches_the_gradient_to_both_window_edges() async throws {
        _ = NSApplication.shared
        let size = NSSize(width: 520, height: 160)
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: 0, width: size.width, height: size.height),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSView(frame: NSRect(origin: .zero, size: size))
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.white.cgColor
        window.contentView = host
        let veil = MacOS15GradientVeilView(frame: host.bounds)
        veil.state = .active
        veil.blendingMode = .behindWindow
        veil.material = .hudWindow
        veil.appearance = NSAppearance(named: .darkAqua)
        host.addSubview(veil)
        window.orderFront(nil)
        defer { window.contentView = nil; window.close() }
        veil.layout()
        let strip = try #require(veil.maskImage)
        let reference = NSImage(size: size)
        reference.lockFocus()
        NSGradient(colorsAndLocations: (.white, 0), (.white, 0.75), (.white.withAlphaComponent(0), 1))?
            .draw(in: host.bounds, angle: 90)
        reference.unlockFocus()
        func sample(_ mask: NSImage) async throws -> [CGFloat] {
            veil.maskImage = mask
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            var values: [CGFloat] = []
            for x in [1, bitmap.pixelsWide / 2, bitmap.pixelsWide - 2] {
                for step in 0..<32 {
                    let y = step * (bitmap.pixelsHigh - 1) / 31
                    values.append(try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)).redComponent)
                }
            }
            return values
        }
        let expected = try await sample(reference)
        let actual = try await sample(strip)
        #expect((expected.max() ?? 0) - (expected.min() ?? 0) > 0.1)
        let maxDifference = zip(expected, actual).map { abs($0 - $1) }.max() ?? 1
        #expect(maxDifference < 0.025)
    }

    private func view(radius: CGFloat?) -> MacOS15BackdropView {
        _ = NSApplication.shared
        let view = MacOS15BackdropView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
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

    @Test func capsule_width_changes_reuse_the_mask_and_height_changes_update_the_end_caps() throws {
        let view = view(radius: nil)
        view.setFrameSize(NSSize(width: 140, height: 30))
        view.layout()
        let mask = try #require(view.maskImage)
        let representations = mask.representations.map(ObjectIdentifier.init)
        #expect(mask.size == NSSize(width: 31, height: 31))
        for width: CGFloat in [140, 480, 500, 600, 680, 480] {
            view.setFrameSize(NSSize(width: width, height: 30))
            view.layout()
            #expect(view.maskImage === mask)
            #expect(mask.capInsets.top == 15)
            #expect(mask.representations.map(ObjectIdentifier.init) == representations)
        }
        view.setFrameSize(NSSize(width: 140 * 1.06, height: 30 * 1.06))
        view.layout()
        let zoomed = try #require(view.maskImage)
        #expect(zoomed !== mask)
        #expect(abs(zoomed.capInsets.top - 15 * 1.06) < 0.0001)
        #expect(abs(zoomed.size.width - (30 * 1.06 + 1)) < 0.0001)

        view.setFrameSize(NSSize(width: 480, height: 38))
        view.layout()
        let taller = try #require(view.maskImage)
        #expect(taller !== zoomed && taller.size == NSSize(width: 39, height: 39))
        for width: CGFloat in [480, 500, 600, 680, 480] {
            view.setFrameSize(NSSize(width: width, height: 38))
            view.layout()
            #expect(view.maskImage === taller && taller.capInsets.top == 19)
        }
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
        let smaller = try #require(view.maskImage)
        #expect(smaller !== second && smaller.capInsets.top == 5)
        #expect(smaller.size == NSSize(width: 11, height: 11))
        view.setFrameSize(.zero)
        view.layout()
        #expect(view.maskImage === smaller)
        view.cornerRadius = nil
        view.setFrameSize(NSSize(width: 10, height: 40))
        view.layout()
        #expect(view.maskImage === smaller && view.maskImage?.capInsets.top == 5)
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

    @Test func native_capsules_keep_flat_edges_when_the_width_changes() async throws {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: 0, width: 520, height: 76),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 76))
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.white.cgColor
        window.contentView = host
        let backdrop = view(radius: nil)
        backdrop.material = .underWindowBackground
        backdrop.state = .active
        backdrop.appearance = NSAppearance(named: .darkAqua)
        host.addSubview(backdrop)
        window.orderFront(nil)
        defer { window.contentView = nil; window.close() }

        for width: CGFloat in [100, 240, 480] {
            backdrop.frame = NSRect(x: 20, y: 20, width: width, height: 36)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(80))
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
            func brightness(_ x: CGFloat, _ y: CGFloat) throws -> CGFloat {
                let color = try #require(
                    bitmap.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB))
                return (color.redComponent + color.greenComponent + color.blueComponent) / 3
            }
            let center = try brightness(20 + width / 2, 38)
            let topEdge = try brightness(42, 21)
            let bottomEdge = try brightness(42, 55)
            #expect(abs(topEdge - center) < 0.1, "width=\(width): top edge must stay flat")
            #expect(abs(bottomEdge - center) < 0.1, "width=\(width): bottom edge must stay flat")
            #expect(try brightness(20, 20) > center + 0.1, "Capsule corners must stay rounded")
            if let output = ProcessInfo.processInfo.environment["WHISK_UI_ARTIFACTS"] {
                let directory = URL(fileURLWithPath: output)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try bitmap.representation(using: .png, properties: [:])?.write(
                    to: directory.appendingPathComponent("capsule-\(Int(width)).png"))
            }
        }
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
        let host = NSHostingView(rootView: MacOS15HistoryPanelView(store: store, actions: PanelActionSpy().actions))
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
            let glass = descendants(scroll).filter { $0 is MacOS15BackdropView }.count
            #expect(glass > 0 && glass <= 13)
            print("Card rail at \(index): native glass=\(glass)")
        }
        for index in [150, 3, 180, 0] {
            store.update(HistoryPresenter().present(items: items, query: "", now: Date(), selectedID: items[index].id))
            for _ in 0..<8 {
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.025))
                let glass = descendants(scroll).filter { $0 is MacOS15BackdropView }.count
                #expect(glass > 0 && glass <= 13)
            }
        }
    }
}

// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI
import Testing

@testable import Whisk

@MainActor
@Suite struct SpotlightLayout {
    private func render(_ view: some View, name: String) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try #require(renderer.nsImage)
        let data = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: data))
        if let output = ProcessInfo.processInfo.environment["WHISK_UI_ARTIFACTS"] {
            let directory = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name))
        }
        return bitmap
    }

    private func circleImage(width: Int, height: Int) throws -> NSImage {
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let green = NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1)
        let blue = NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)
        for y in 0..<height {
            for x in 0..<width {
                let dx = x - width / 2
                let dy = y - height / 2
                bitmap.setColor(dx * dx + dy * dy <= 400 ? green : blue, atX: x, y: y)
            }
        }
        let cgImage = try #require(bitmap.cgImage)
        return NSImage(cgImage: cgImage, size: CGSize(width: width, height: height))
    }

    @Test func landscape_and_portrait_images_keep_circles_round_in_the_spotlight() throws {
        for (width, height) in [(200, 100), (100, 200)] {
            let image = try circleImage(width: width, height: height)
            let bitmap = try render(
                MacOS15SpotlightCanvas(content: .image, point: CGPoint(x: 110, y: 110), thumbnail: image)
                    .frame(width: 220, height: 220), name: "spotlight-image-\(width)x\(height).png")
            var pixels: [CGPoint] = []
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    if color.greenComponent > 0.8 && color.redComponent < 0.2 && color.blueComponent < 0.2 {
                        pixels.append(CGPoint(x: x, y: y))
                    }
                }
            }
            let minX = try #require(pixels.map(\.x).min())
            let maxX = try #require(pixels.map(\.x).max())
            let minY = try #require(pixels.map(\.y).min())
            let maxY = try #require(pixels.map(\.y).max())
            #expect(abs((maxX - minX) - (maxY - minY)) <= 1)
            #expect(maxX - minX >= 40)
        }
    }

    @Test func image_layout_fits_its_container_and_centers_letterboxing() {
        #expect(
            MacOS15SpotlightGeometry.imageRect(
                imageSize: CGSize(width: 400, height: 200),
                canvasSize: CGSize(width: 200, height: 200)) == CGRect(x: 0, y: 50, width: 200, height: 100))
        #expect(
            MacOS15SpotlightGeometry.imageRect(
                imageSize: CGSize(width: 200, height: 400),
                canvasSize: CGSize(width: 200, height: 200)) == CGRect(x: 50, y: 0, width: 100, height: 200))
        #expect(
            MacOS15SpotlightGeometry.imageRect(imageSize: .zero, canvasSize: CGSize(width: 200, height: 200)) == .zero)
        #expect(
            MacOS15SpotlightGeometry.imageRect(imageSize: CGSize(width: 200, height: 100), canvasSize: .zero) == .zero)
    }

    @Test func card_size_is_identical_before_during_and_after_reveal() throws {
        _ = NSApplication.shared
        let image = try circleImage(width: 200, height: 100)
        for side: CGFloat in [160, 200, 250] {
            let host = NSHostingView(rootView: MacOS15SpotlightCardSurface(side: side))
            #expect(host.fittingSize == CGSize(width: side, height: side))
            host.rootView = MacOS15SpotlightCardSurface(
                side: side, content: .image,
                point: CGPoint(x: side / 2, y: side / 2), thumbnail: image)
            host.layoutSubtreeIfNeeded()
            #expect(host.fittingSize == CGSize(width: side, height: side))
            host.rootView = MacOS15SpotlightCardSurface(
                side: side, content: .text(String(repeating: "long text\n", count: 100)),
                point: CGPoint(x: side / 2, y: side / 2))
            host.layoutSubtreeIfNeeded()
            #expect(host.fittingSize == CGSize(width: side, height: side))
            for settings in [
                SpotlightPreferences(diameter: 40, blurRadius: 20),
                SpotlightPreferences(diameter: 320, blurRadius: 0),
            ] {
                host.rootView = MacOS15SpotlightCardSurface(
                    side: side, content: .text("synthetic"), point: CGPoint(x: side / 2, y: side / 2),
                    spotlight: settings)
                host.layoutSubtreeIfNeeded()
                #expect(host.fittingSize == CGSize(width: side, height: side))
            }
            host.rootView = MacOS15SpotlightCardSurface(side: side)
            #expect(host.fittingSize == CGSize(width: side, height: side))
        }
    }

    @Test func default_reveal_uses_150_point_diameter_and_50_point_soft_edge() throws {
        let bitmap = try render(
            MacOS15SpotlightCanvas(content: .text(""), point: CGPoint(x: 110, y: 110))
                .frame(width: 220, height: 220), name: "spotlight-transition.png")
        let center = try #require(bitmap.colorAt(x: 110, y: 110))
        let inner = try #require(bitmap.colorAt(x: 130, y: 110))
        let transition = try #require(bitmap.colorAt(x: 160, y: 110))
        let outside = try #require(bitmap.colorAt(x: 200, y: 110))
        #expect(center.alphaComponent > 0.99)
        #expect(inner.alphaComponent > 0.99)
        #expect(transition.alphaComponent > 0.1 && transition.alphaComponent < 0.9)
        #expect(outside.alphaComponent == 0)
        #expect(
            MacOS15SpotlightGeometry.revealBounds(around: CGPoint(x: 110, y: 110))
                == CGRect(x: 35, y: 35, width: 150, height: 150))
    }

    @Test func showing_a_card_displays_image_pixels_outside_the_spotlight() throws {
        let image = try circleImage(width: 200, height: 100)
        let settings = SpotlightPreferences(diameter: 40, blurRadius: 20)
        let entire = try render(
            MacOS15SpotlightCardSurface(
                side: 220, content: .image, thumbnail: image,
                spotlight: settings, showsFullCard: true),
            name: "privacy-show-card.png")
        let local = try render(
            MacOS15SpotlightCardSurface(
                side: 220, content: .image, point: CGPoint(x: 110, y: 110),
                thumbnail: image, spotlight: settings),
            name: "privacy-spotlight-card.png")
        #expect(entire.pixelsWide == 220 && entire.pixelsHigh == 220)
        let fullPixel = try #require(entire.colorAt(x: 175, y: 110)?.usingColorSpace(.deviceRGB))
        let localPixel = try #require(local.colorAt(x: 175, y: 110)?.usingColorSpace(.deviceRGB))
        #expect(fullPixel.blueComponent > 0.9 && fullPixel.redComponent < 0.1)
        #expect(localPixel.redComponent > 0.1 || localPixel.blueComponent < 0.9)
    }

    @Test func custom_range_and_blur_change_only_the_bounded_mask() throws {
        func sample(_ settings: SpotlightPreferences, _ suffix: String) throws -> NSBitmapImageRep {
            try render(
                MacOS15SpotlightCanvas(content: .text(""), point: CGPoint(x: 140, y: 140), spotlight: settings)
                    .frame(width: 280, height: 280), name: "spotlight-custom-\(suffix).png")
        }
        let small = try sample(SpotlightPreferences(diameter: 80, blurRadius: 10), "small")
        let large = try sample(SpotlightPreferences(diameter: 200, blurRadius: 10), "large")
        let soft = try sample(SpotlightPreferences(diameter: 200, blurRadius: 80), "soft")
        let hard = try sample(SpotlightPreferences(diameter: 200, blurRadius: 0), "hard")
        #expect(try #require(small.colorAt(x: 200, y: 140)).alphaComponent == 0)
        #expect(try #require(large.colorAt(x: 200, y: 140)).alphaComponent > 0.99)
        let featherAlpha = try #require(soft.colorAt(x: 200, y: 140)).alphaComponent
        #expect(featherAlpha > 0.3 && featherAlpha < 0.7)
        #expect(try #require(hard.colorAt(x: 235, y: 140)).alphaComponent > 0.99)
        for bitmap in [small, large, soft, hard] {
            #expect(try #require(bitmap.colorAt(x: 140, y: 140)).alphaComponent > 0.99)
            #expect(try #require(bitmap.colorAt(x: 245, y: 140)).alphaComponent == 0)
        }
        #expect(
            MacOS15SpotlightGeometry.revealBounds(
                around: CGPoint(x: 140, y: 140), spotlight: .init(diameter: 200, blurRadius: 80))
                == CGRect(x: 40, y: 40, width: 200, height: 200))
    }

    @Test func long_text_keeps_the_first_line_at_its_natural_size() throws {
        let prefix = "MMMMMMMM\nMMMMMMMM\n"
        // Sample both glyph runs in the same render/color environment. Two
        // separate snapshots of even identical input can differ at a feathered pixel.
        let pair = try render(
            HStack(spacing: 0) {
                MacOS15SpotlightCanvas(content: .text(prefix), point: CGPoint(x: 70, y: 45))
                    .frame(width: 220, height: 220)
                MacOS15SpotlightCanvas(
                    content: .text(prefix + String(repeating: "MMMMMMMM\n", count: 100)),
                    point: CGPoint(x: 70, y: 45)
                )
                .frame(width: 220, height: 220)
            }.environment(\.colorScheme, .light), name: "spotlight-text-pair.png")
        #expect(pair.pixelsWide == 440 && pair.pixelsHigh == 220)
        var darkPixels = 0
        for y in 12..<40 {
            for x in 12..<100 {
                let a = try #require(pair.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let b = try #require(pair.colorAt(x: x + 220, y: y)?.usingColorSpace(.deviceRGB))
                if a.alphaComponent > 0.9, a.redComponent < 0.3 { darkPixels += 1 }
                #expect(abs(a.alphaComponent - b.alphaComponent) < 0.01)
                #expect(abs(a.redComponent - b.redComponent) < 0.01)
            }
        }
        #expect(darkPixels > 20)
    }
}

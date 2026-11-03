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
                SpotlightCanvas(payload: .image(Data()), point: CGPoint(x: 110, y: 110), thumbnail: image)
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
            SpotlightGeometry.imageRect(
                imageSize: CGSize(width: 400, height: 200),
                canvasSize: CGSize(width: 200, height: 200)) == CGRect(x: 0, y: 50, width: 200, height: 100))
        #expect(
            SpotlightGeometry.imageRect(
                imageSize: CGSize(width: 200, height: 400),
                canvasSize: CGSize(width: 200, height: 200)) == CGRect(x: 50, y: 0, width: 100, height: 200))
        #expect(SpotlightGeometry.imageRect(imageSize: .zero, canvasSize: CGSize(width: 200, height: 200)) == .zero)
        #expect(SpotlightGeometry.imageRect(imageSize: CGSize(width: 200, height: 100), canvasSize: .zero) == .zero)
    }

    @Test func card_size_is_identical_before_during_and_after_reveal() throws {
        _ = NSApplication.shared
        let image = try circleImage(width: 200, height: 100)
        for side: CGFloat in [160, 200, 250] {
            let host = NSHostingView(rootView: SpotlightCardSurface(side: side))
            #expect(host.fittingSize == CGSize(width: side, height: side))
            host.rootView = SpotlightCardSurface(
                side: side, payload: .image(Data()),
                point: CGPoint(x: side / 2, y: side / 2), thumbnail: image)
            host.layoutSubtreeIfNeeded()
            #expect(host.fittingSize == CGSize(width: side, height: side))
            host.rootView = SpotlightCardSurface(
                side: side, payload: .text(String(repeating: "long text\n", count: 100)),
                point: CGPoint(x: side / 2, y: side / 2))
            host.layoutSubtreeIfNeeded()
            #expect(host.fittingSize == CGSize(width: side, height: side))
            host.rootView = SpotlightCardSurface(side: side)
            #expect(host.fittingSize == CGSize(width: side, height: side))
        }
    }

    @Test func reveal_has_a_wider_soft_edge_but_remains_bounded() throws {
        let bitmap = try render(
            SpotlightCanvas(payload: .text(""), point: CGPoint(x: 110, y: 110))
                .frame(width: 220, height: 220), name: "spotlight-transition.png")
        let center = try #require(bitmap.colorAt(x: 110, y: 110))
        let inner = try #require(bitmap.colorAt(x: 164, y: 110))
        let transition = try #require(bitmap.colorAt(x: 178, y: 110))
        let outside = try #require(bitmap.colorAt(x: 200, y: 110))
        #expect(center.alphaComponent > 0.99)
        #expect(inner.alphaComponent > 0.99)
        #expect(transition.alphaComponent > 0.1 && transition.alphaComponent < 0.9)
        #expect(outside.alphaComponent == 0)
        #expect(
            SpotlightGeometry.revealBounds(around: CGPoint(x: 110, y: 110))
                == CGRect(x: 30, y: 30, width: 160, height: 160))
    }

    @Test func long_text_keeps_the_first_line_at_its_natural_size() throws {
        let prefix = "MMMMMMMM\nMMMMMMMM\n"
        let short = try render(
            SpotlightCanvas(payload: .text(prefix), point: CGPoint(x: 70, y: 45))
                .frame(width: 220, height: 220).environment(\.colorScheme, .light), name: "spotlight-text-short.png")
        let long = try render(
            SpotlightCanvas(
                payload: .text(prefix + String(repeating: "MMMMMMMM\n", count: 100)),
                point: CGPoint(x: 70, y: 45)
            ).frame(width: 220, height: 220).environment(\.colorScheme, .light),
            name: "spotlight-text-long.png")
        var darkPixels = 0
        for y in 12..<40 {
            for x in 12..<100 {
                let a = try #require(short.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let b = try #require(long.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                if a.alphaComponent > 0.9, a.redComponent < 0.3 { darkPixels += 1 }
                #expect(abs(a.redComponent - b.redComponent) < 0.01)
            }
        }
        #expect(darkPixels > 20)
    }
}

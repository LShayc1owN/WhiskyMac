// WhiskyMac: modified or added 2026-11-15 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import ImageIO
import SwiftUI
import Testing

@testable import Whisk

private final class ImageDecodeRecorder {
    private let lock = NSLock()
    private var calls: [Bool] = []
    func record() { lock.lock(); calls.append(Thread.isMainThread); lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return calls.count }
    var usedMainThread: Bool { lock.lock(); defer { lock.unlock() }; return calls.contains(true) }
}

@MainActor
@Suite struct ImageThumbnailBehaviour {
    private func bitmap(_ width: Int = 32, _ height: Int = 32) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 0.5))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    private func encoded(_ image: CGImage, orientation: Int = 1) throws -> Data {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func load(_ request: ImageThumbnailRequest, from store: ImageThumbnailStore) async -> NSImage? {
        await withCheckedContinuation { continuation in
            store.load(request) { continuation.resume(returning: $0) }
        }
    }

    private func drain(_ queue: OperationQueue) async {
        await withCheckedContinuation { continuation in queue.addBarrierBlock { continuation.resume() } }
    }

    @Test func private_preview_keeps_no_entry_even_when_decoding_fails_at_zero_cost() async {
        let store = ImageThumbnailStore(byteLimit: 0) { _, _ in nil }
        let request = ImageThumbnailRequest(id: UUID(), data: Data(), maxPixelSize: 512)
        #expect(await load(request, from: store) == nil)
        #expect(store.cachedCount == 0)
        #expect(store.cachedBytes == 0)
    }

    @Test func thumbnails_bound_pixels_preserve_aspect_and_apply_image_orientation() throws {
        let data = try encoded(bitmap(1200, 800))
        let card = try #require(ImageThumbnailDecoder.decode(data, maxPixelSize: 512))
        #expect(card.width <= 512 && card.height <= 512)
        #expect(abs(Double(card.width) / Double(card.height) - 1.5) < 0.01)
        let rotated = try #require(
            ImageThumbnailDecoder.decode(try encoded(bitmap(400, 200), orientation: 6), maxPixelSize: 256))
        #expect(rotated.height == 256 && rotated.width == 128)
        let bounded = try #require(ImageThumbnailDecoder.decode(data, maxPixelSize: Int.max))
        #expect(max(bounded.width, bounded.height) <= ImageThumbnailDecoder.maximumPixelSize)
        #expect(ImageThumbnailDecoder.decode(Data([0, 1, 2]), maxPixelSize: 512) == nil)
    }

    @Test func identical_pending_requests_share_one_decode_off_the_main_thread() async throws {
        let result = try bitmap()
        let calls = ImageDecodeRecorder()
        let queue = OperationQueue()
        queue.isSuspended = true
        let store = ImageThumbnailStore(queue: queue) { _, _ in
            calls.record(); return result
        }
        let request = ImageThumbnailRequest(id: UUID(), data: Data([1]), maxPixelSize: 512)
        let images: [NSImage?] = await withCheckedContinuation { continuation in
            var received: [NSImage?] = []
            let callback: (NSImage?) -> Void = { image in
                received.append(image)
                if received.count == 2 { continuation.resume(returning: received) }
            }
            store.load(request, completion: callback)
            store.load(request, completion: callback)
            #expect(store.pendingCount == 1)
            queue.isSuspended = false
        }
        #expect(calls.count == 1 && !calls.usedMainThread)
        #expect(images[0] != nil && images[0] === images[1])
        let cached = await load(request, from: store)
        #expect(cached === images[0] && calls.count == 1)
    }

    @Test func cache_counts_source_bytes_and_evicts_the_least_recent_image() async throws {
        let result = try bitmap()
        let store = ImageThumbnailStore(byteLimit: 20_300) { _, _ in result }
        let requests = (0..<3).map { _ in ImageThumbnailRequest(id: UUID(), data: Data(count: 6000), maxPixelSize: 512)
        }
        _ = await load(requests[0], from: store)
        _ = await load(requests[1], from: store)
        #expect(store.cachedImage(for: requests[0]) != nil)
        _ = await load(requests[2], from: store)
        #expect(store.cachedBytes <= 20_300 && store.cachedCount == 2)
        #expect(store.cachedImage(for: requests[0]) != nil)
        #expect(store.cachedImage(for: requests[1]) == nil)
        #expect(store.cachedImage(for: requests[2]) != nil)

        let uncached = ImageThumbnailStore(byteLimit: 100) { _, _ in result }
        #expect(await load(requests[0], from: uncached) != nil)
        #expect(uncached.cachedCount == 0 && uncached.cachedBytes == 0)
    }

    @Test func changed_bytes_under_the_same_identity_do_not_reuse_the_old_image() async throws {
        let first = try bitmap(16, 32)
        let second = try bitmap(32, 16)
        let store = ImageThumbnailStore { data, _ in data.first == 1 ? first : second }
        let id = UUID()
        let before = ImageThumbnailRequest(id: id, data: Data([1]), maxPixelSize: 512)
        let after = ImageThumbnailRequest(id: id, data: Data([2]), maxPixelSize: 512)
        let old = await load(before, from: store)
        let new = await load(after, from: store)
        #expect(old?.size == NSSize(width: 16, height: 32))
        #expect(new?.size == NSSize(width: 32, height: 16))
        #expect(store.cachedImage(for: before) == nil)
    }

    @Test func leaving_before_a_queued_decode_starts_cancels_the_work() async throws {
        let result = try bitmap()
        let calls = ImageDecodeRecorder()
        let queue = OperationQueue()
        queue.isSuspended = true
        let store = ImageThumbnailStore(queue: queue) { _, _ in
            calls.record(); return result
        }
        var delivered = false
        let ticket = try #require(
            store.load(ImageThumbnailRequest(id: UUID(), data: Data([1]), maxPixelSize: 512)) { _ in delivered = true })
        store.cancel(ticket)
        queue.isSuspended = false
        await drain(queue)
        #expect(calls.count == 0 && !delivered)
        #expect(store.pendingCount == 0 && store.cachedCount == 0)
    }

    @Test func releasing_an_isolated_store_cancels_its_queued_decodes() async throws {
        let result = try bitmap()
        let calls = ImageDecodeRecorder()
        let queue = OperationQueue()
        queue.isSuspended = true
        var store: ImageThumbnailStore? = ImageThumbnailStore(queue: queue) { _, _ in
            calls.record(); return result
        }
        store?.load(ImageThumbnailRequest(id: UUID(), data: Data([1]), maxPixelSize: 512)) { _ in }
        store = nil
        queue.isSuspended = false
        await drain(queue)
        #expect(calls.count == 0)
    }

    @Test func privacy_clears_cached_images_and_rejects_a_running_decode_after_unprotecting() async throws {
        let result = try bitmap()
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let queue = OperationQueue()
        let store = ImageThumbnailStore(queue: queue) { _, _ in
            entered.signal(); release.wait(); return result
        }
        let request = ImageThumbnailRequest(id: UUID(), data: Data([1]), maxPixelSize: 512)
        var delivered: [NSImage?] = []
        store.load(request) { delivered.append($0) }
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                entered.wait(); continuation.resume()
            }
        }
        store.setPrivacy(true)
        #expect(delivered.count == 1 && delivered[0] == nil)
        store.setPrivacy(false)
        release.signal()
        await drain(queue)
        #expect(store.pendingCount == 0 && store.cachedCount == 0)
        #expect(store.cachedImage(for: request) == nil)

        let cached = ImageThumbnailStore { _, _ in result }
        _ = await load(request, from: cached)
        cached.setPrivacy(true)
        #expect(cached.cachedBytes == 0 && cached.cachedImage(for: request) == nil)
        #expect(await load(request, from: cached) == nil)
    }

    @Test func replacing_a_view_request_cancels_the_old_load_without_showing_the_wrong_image() async throws {
        let result = try bitmap()
        let calls = ImageDecodeRecorder()
        let queue = OperationQueue()
        queue.isSuspended = true
        let store = ImageThumbnailStore(queue: queue) { _, _ in
            calls.record(); return result
        }
        let loader = ImageThumbnailLoader()
        let first = ImageThumbnailRequest(id: UUID(), data: Data([1]), maxPixelSize: 512)
        let second = ImageThumbnailRequest(id: UUID(), data: Data([2]), maxPixelSize: 512)
        loader.load(first, store: store)
        loader.load(second, store: store)
        #expect(loader.image(for: first) == nil && loader.image(for: second) == nil)
        await withCheckedContinuation { continuation in
            store.load(second) { _ in continuation.resume() }
            queue.isSuspended = false
        }
        #expect(calls.count == 1)
        #expect(loader.image(for: first) == nil && loader.image(for: second) != nil)
        loader.cancel()
        #expect(loader.image(for: second) == nil)
    }

    @Test func rendering_size_is_bounded_and_small_geometry_changes_share_a_size() {
        #expect(ImageThumbnailView.pixelSize(for: CGSize(width: 10000, height: 10000), scale: 2, fills: true) == 512)
        #expect(ImageThumbnailView.pixelSize(for: CGSize(width: 10000, height: 10000), scale: 2, fills: false) == 2048)
        #expect(ImageThumbnailView.pixelSize(for: .zero, scale: 2, fills: true) == 0)
        #expect(
            ImageThumbnailView.pixelSize(for: CGSize(width: 150.1, height: 100), scale: 2, fills: true)
                == ImageThumbnailView.pixelSize(for: CGSize(width: 150.2, height: 100), scale: 2, fills: true))
    }

    @Test func image_preview_keeps_its_source_header_visible_above_the_bitmap() throws {
        _ = NSApplication.shared
        let item = anItem(.image(try encoded(bitmap(1200, 800))), from: "PhotoHeader")
        let state = HistoryViewStateStore()
        state.detailSource = { $0 == item.id ? item : nil }
        state.update(HistoryPresenter().present(items: [item], query: "", now: item.copiedAt, selectedID: item.id))
        state.preparePreview()
        let host = NSHostingView(rootView: PreviewOverlayView(store: state).environment(\.colorScheme, .light))
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 800, height: 620),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFront(nil)
        defer { window.contentView = nil; window.close() }
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scaleX = CGFloat(bitmap.pixelsWide) / host.bounds.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / host.bounds.height
        var headerInk = 0
        for y in 20..<48 {
            for x in 20..<115 {
                let color = try #require(
                    bitmap.colorAt(x: Int(CGFloat(x) * scaleX), y: Int(CGFloat(y) * scaleY))?.usingColorSpace(
                        .deviceRGB))
                if color.alphaComponent > 0.9, color.redComponent < 0.35,
                    color.greenComponent < 0.35, color.blueComponent < 0.35
                {
                    headerInk += 1
                }
            }
        }
        #expect(headerInk > 20)
    }

    @Test func copying_saving_and_dragging_keep_the_original_encoded_image() async throws {
        let original = try encoded(bitmap(1200, 800))
        let item = anItem(.image(original))
        let board = ScriptedPasteboard()
        let storage = InMemoryHistoryStore()
        storage.stored = [item]
        let controller = ClipboardController(pasteboard: board, store: storage, clock: FakeClock(), present: { _ in })
        #expect(controller.select(item.id))
        #expect(board.written == [.image(original)])
        #expect(SaveToDisk.proposal(for: .image(original))?.data == original)
        let provider = ItemCardView.dragProvider(for: .image(original))
        #expect(provider.canLoadObject(ofClass: NSImage.self))
        let exported: Data? = await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: "public.png") { data, _ in
                continuation.resume(returning: data)
            }
        }
        #expect(exported == original)
    }
}

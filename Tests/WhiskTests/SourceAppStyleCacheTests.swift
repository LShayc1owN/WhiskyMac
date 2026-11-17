// WhiskyMac: modified or added 2026-11-17 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Observation
import SwiftUI
import Testing

@testable import Whisk

@MainActor
@Suite struct SourceAppIconResources {
    private func artwork(_ color: NSColor = .red) throws -> SourceAppArtwork {
        let bitmap = try #require(
            CGContext(
                data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.setFillColor(color.cgColor)
        bitmap.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        return SourceAppArtwork(icon: try #require(bitmap.makeImage()), color: color)
    }

    private func drain(_ queue: OperationQueue) async {
        await withCheckedContinuation { continuation in queue.addBarrierBlock { continuation.resume() } }
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    }

    @Test func a_blocked_app_icon_lookup_never_blocks_layout_or_cache_release() async throws {
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let queue = OperationQueue()
        let artwork = try artwork()
        let cache = SourceAppStyleCache(queue: queue) { _ in
            #expect(!Thread.isMainThread)
            entered.signal(); release.wait()
            return artwork
        }
        let placeholder = cache.resolve(bundleID: "blocked.app")
        #expect(placeholder.icon != nil)
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                entered.wait(); continuation.resume()
            }
        }
        // All checks run while the system substitute is still blocked.
        let host = NSHostingView(rootView: IconSurface(cache: cache, bundleID: "blocked.app").equatable())
        host.frame = CGRect(x: 0, y: 0, width: 64, height: 64)
        host.layoutSubtreeIfNeeded()
        #expect(host.bounds.size == CGSize(width: 64, height: 64))
        #expect(cache.pendingCount == 1)
        cache.releaseCache()
        #expect(cache.pendingCount == 0 && cache.cachedBytes == 0 && cache.cachedCount == 0)
        release.signal()
        await drain(queue)
        #expect(cache.cachedCount == 0)
    }

    @Test func shared_requests_update_only_their_observers_and_reuse_the_completed_icon() async throws {
        let queue = OperationQueue()
        queue.isSuspended = true
        let artwork = try artwork()
        let cache = SourceAppStyleCache(queue: queue, load: { _ in artwork })
        let firstChanged = IconChangeFlag()
        let secondChanged = IconChangeFlag()
        withObservationTracking {
            _ = cache.resolve(bundleID: "first.app")
        } onChange: {
            firstChanged.mark()
        }
        _ = cache.resolve(bundleID: "first.app")
        #expect(cache.pendingCount == 1)
        queue.isSuspended = false
        await drain(queue)
        #expect(firstChanged.value)
        let first = cache.resolve(bundleID: "first.app").icon
        withObservationTracking {
            _ = cache.resolve(bundleID: "first.app")
        } onChange: {
            secondChanged.mark()
        }
        _ = cache.resolve(bundleID: "second.app")
        await drain(queue)
        #expect(!secondChanged.value)
        #expect(cache.resolve(bundleID: "first.app").icon === first)
        #expect(cache.pendingCount == 0)
    }

    @Test func count_and_byte_limits_evict_lru_and_oversize_results_are_not_retained() async throws {
        let queue = OperationQueue()
        let artwork = try artwork()
        let cost = artwork.icon.bytesPerRow * artwork.icon.height
        let cache = SourceAppStyleCache(countLimit: 3, byteLimit: cost * 2, queue: queue, load: { _ in artwork })
        _ = cache.resolve(bundleID: "a"); _ = cache.resolve(bundleID: "b")
        await drain(queue)
        let first = cache.resolve(bundleID: "a").icon
        _ = cache.resolve(bundleID: "c")
        await drain(queue)
        #expect(cache.cachedBytes == 2 * cost && cache.cachedCount == 2)
        #expect(cache.resolve(bundleID: "a").icon === first)
        queue.isSuspended = true
        _ = cache.resolve(bundleID: "b")
        #expect(cache.pendingCount == 1)
        _ = cache.resolve(bundleID: "d")
        #expect(cache.cachedCount == 3)
        cache.releaseCache()
        queue.isSuspended = false
        await drain(queue)
        #expect(cache.cachedBytes == 0 && cache.cachedCount == 0)

        let tiny = SourceAppStyleCache(byteLimit: cost - 1, queue: queue, load: { _ in artwork })
        _ = tiny.resolve(bundleID: "oversize")
        await drain(queue)
        #expect(tiny.cachedBytes == 0 && tiny.resolve(bundleID: "oversize").icon == nil)
        #expect(tiny.pendingCount == 0)
    }

    @Test func cancelled_queued_work_does_not_run_and_pending_work_does_not_retain_the_cache() async {
        let queue = OperationQueue()
        queue.isSuspended = true
        var cache: SourceAppStyleCache? = SourceAppStyleCache(queue: queue) { _ in
            Issue.record("Cancelled queued lookup must not call the system")
            return nil
        }
        weak let released = cache
        _ = cache?.resolve(bundleID: "never-started")
        cache = nil
        #expect(released == nil)
        queue.isSuspended = false
        await drain(queue)
    }

    @Test func finished_artwork_repaints_an_equatable_host_without_resizing_the_icon_slot() async throws {
        _ = NSApplication.shared
        let queue = OperationQueue()
        queue.isSuspended = true
        let artwork = try artwork()
        let cache = SourceAppStyleCache(queue: queue, load: { _ in artwork })
        let host = NSHostingView(rootView: IconSurface(cache: cache, bundleID: "red.app").equatable())
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: CGRect(x: -10000, y: 0, width: 64, height: 64),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        let before = host.fittingSize
        queue.isSuspended = false
        await drain(queue)
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(host.fittingSize == before)
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let center = try #require(
            bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB))
        // Compare through the same window color-management path. A raw CG
        // bitmap and an AppKit display capture can have different profiles.
        let reference = NSHostingView(
            rootView: Image(nsImage: NSImage(cgImage: artwork.icon, size: NSSize(width: 32, height: 32)))
                .resizable().frame(width: 64, height: 64))
        reference.sizingOptions = []
        window.contentView = reference
        reference.layoutSubtreeIfNeeded()
        let expectedBitmap = try #require(reference.bitmapImageRepForCachingDisplay(in: reference.bounds))
        reference.cacheDisplay(in: reference.bounds, to: expectedBitmap)
        let expected = try #require(
            expectedBitmap.colorAt(x: expectedBitmap.pixelsWide / 2, y: expectedBitmap.pixelsHigh / 2)?
                .usingColorSpace(.sRGB))
        #expect(abs(center.redComponent - expected.redComponent) < 0.01)
        #expect(abs(center.greenComponent - expected.greenComponent) < 0.01)
        #expect(abs(center.blueComponent - expected.blueComponent) < 0.01)
    }

    @Test func rasterization_keeps_only_a_small_independent_image_and_handles_transparency() throws {
        for transparent in [false, true] {
            var source: NSImage? = NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { rect in
                (transparent ? NSColor.clear : NSColor.red).setFill()
                rect.fill(); return true
            }
            weak let released = source
            let output = try #require(source.flatMap(SourceAppArtwork.rasterize))
            source = nil
            #expect(released == nil)
            #expect(output.icon.width == 64 && output.icon.height == 64)
            #expect(output.icon.bytesPerRow * output.icon.height == 16 * 1024)
            if transparent {
                #expect(output.color == .systemGray)
            } else {
                #expect(output.color.redComponent > output.color.greenComponent)
            }
        }
    }
}

private struct IconSurface: View, Equatable {
    let cache: SourceAppStyleCache
    let bundleID: String
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.cache === rhs.cache && lhs.bundleID == rhs.bundleID }
    var body: some View {
        if let image = cache.resolve(bundleID: bundleID).icon {
            Image(nsImage: image).resizable().frame(width: 64, height: 64)
        }
    }
}

private final class IconChangeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var changed = false
    var value: Bool { lock.lock(); defer { lock.unlock() }; return changed }
    func mark() { lock.lock(); changed = true; lock.unlock() }
}

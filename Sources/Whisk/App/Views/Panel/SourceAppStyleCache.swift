// WhiskyMac: modified or added 2026-11-17 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Observation

/// Observe each application's result, so one icon does not refresh every card.
@MainActor
final class SourceAppStyleCache {
    nonisolated static let maximumCount = 512
    nonisolated static let maximumBytes = 8 * 1024 * 1024
    private static let work: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "dev.whisky.maclx.source-app-icons"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 2
        return queue
    }()

    fileprivate final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
        func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    }

    @Observable fileprivate final class Entry {
        var value: SourceAppStyle.Resolved
        @ObservationIgnored let id = UUID()
        @ObservationIgnored let cancellation = Cancellation()
        @ObservationIgnored var operation: BlockOperation?
        @ObservationIgnored var access: UInt64 = 0
        @ObservationIgnored var cost = 0
        init(value: SourceAppStyle.Resolved) { self.value = value }
        func cancel() { cancellation.cancel(); operation?.cancel() }
    }

    private var entries: [String: Entry] = [:]
    private var access: UInt64 = 0
    private let countLimit: Int
    private let byteLimit: Int
    private let queue: OperationQueue
    private let load: (String) -> SourceAppArtwork?
    private(set) var cachedBytes = 0
    var cachedCount: Int { entries.count }
    var pendingCount: Int { entries.values.filter { $0.operation != nil }.count }

    init(
        countLimit: Int = maximumCount, byteLimit: Int = maximumBytes,
        queue: OperationQueue? = nil, load: @escaping (String) -> SourceAppArtwork? = SourceAppArtwork.load
    ) {
        self.countLimit = max(1, countLimit)
        self.byteLimit = max(0, byteLimit)
        self.queue = queue ?? Self.work
        self.queue.maxConcurrentOperationCount = 2
        self.load = load
    }

    deinit { entries.values.forEach { $0.cancel() } }

    func resolve(bundleID: String?) -> SourceAppStyle.Resolved {
        guard let bundleID else { return SourceAppStyle.fallback }
        if let entry = entries[bundleID] {
            access &+= 1; entry.access = access
            return entry.value
        }
        while entries.count >= countLimit { evictOldest() }
        let entry = Entry(value: SourceAppStyle.pending)
        access &+= 1; entry.access = access
        entries[bundleID] = entry
        let id = entry.id
        let cancellation = entry.cancellation
        let load = self.load
        let operation = BlockOperation { [weak self] in
            guard !cancellation.isCancelled else { return }
            let artwork = autoreleasepool { load(bundleID) }
            guard !cancellation.isCancelled else { return }
            DispatchQueue.main.async { [weak self] in
                self?.complete(bundleID, id: id, artwork: artwork)
            }
        }
        entry.operation = operation
        queue.addOperation(operation)
        return entry.value
    }

    func releaseCache() {
        entries.values.forEach { $0.cancel() }
        entries.removeAll()
        cachedBytes = 0
    }

    private func complete(_ bundleID: String, id: UUID, artwork: SourceAppArtwork?) {
        guard let entry = entries[bundleID], entry.id == id else { return }
        entry.operation = nil
        guard let artwork else { entry.value = SourceAppStyle.fallback; return }
        let cost = artwork.icon.bytesPerRow * artwork.icon.height
        guard cost <= byteLimit else { entry.value = SourceAppStyle.fallback; return }
        while cachedBytes + cost > byteLimit { evictOldest(excluding: bundleID) }
        entry.cost = cost
        cachedBytes += cost
        entry.value = SourceAppStyle.resolved(
            icon: NSImage(cgImage: artwork.icon, size: NSSize(width: 32, height: 32)), base: artwork.color)
    }

    private func evictOldest(excluding protected: String? = nil) {
        guard let key = entries.filter({ $0.key != protected }).min(by: { $0.value.access < $1.value.access })?.key,
            let removed = entries.removeValue(forKey: key)
        else { return }
        removed.cancel()
        cachedBytes -= removed.cost
    }
}

/// Transfer only a small, independently rasterized icon and its original tint.
struct SourceAppArtwork {
    let icon: CGImage
    let color: NSColor

    static func load(_ bundleID: String) -> SourceAppArtwork? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return rasterize(NSWorkspace.shared.icon(forFile: url.path))
    }

    static func rasterize(_ image: NSImage) -> SourceAppArtwork? {
        let side = 64
        guard
            let bitmap = CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let context = NSGraphicsContext(cgContext: bitmap, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        guard let icon = bitmap.makeImage() else { return nil }
        // TIFF serializes every representation, including 2048px variants.
        // Select just the old 1024px color sample, with a fixed 1x context.
        var sampleRect = CGRect(x: 0, y: 0, width: 1024, height: 1024)
        let sample = image.cgImage(forProposedRect: &sampleRect, context: context, hints: nil) ?? icon
        return SourceAppArtwork(icon: icon, color: dominantColor(of: sample) ?? .systemGray)
    }

    private static func dominantColor(of image: CGImage) -> NSColor? {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        guard width > 0, height > 0 else { return nil }
        let step = max(1, min(width, height) / 24)
        var red = 0.0, green = 0.0, blue = 0.0, weight = 0.0
        for x in stride(from: 0, to: width, by: step) {
            for y in stride(from: 0, to: height, by: step) {
                guard let sample = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                    sample.alphaComponent > 0.5
                else { continue }
                let pixelWeight = 0.15 + sample.saturationComponent
                red += sample.redComponent * pixelWeight
                green += sample.greenComponent * pixelWeight
                blue += sample.blueComponent * pixelWeight
                weight += pixelWeight
            }
        }
        guard weight > 0 else { return nil }
        let average = NSColor(srgbRed: red / weight, green: green / weight, blue: blue / weight, alpha: 1)
        return NSColor(
            hue: average.hueComponent,
            saturation: min(max(average.saturationComponent, 0.35), 0.75),
            brightness: min(max(average.brightnessComponent, 0.45), 0.72), alpha: 1)
    }
}

// WhiskyMac: modified or added 2026-11-17 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import QuickLookThumbnailing

/// File providers and Icon Services may block even before Quick Look starts.
/// Never call them from SwiftUI layout, request submission or cancellation.
final class FileThumbnailWorker: @unchecked Sendable {
    typealias Generator = (String, @escaping (CGImage?) -> Void) -> () -> Void
    static let shared = FileThumbnailWorker()
    private static let cancellationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "dev.whisky.maclx.file-preview-cancellation"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        return queue
    }()

    final class Ticket: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        private var completed = false
        private weak var operation: Operation?
        private var cancelGeneration: (() -> Void)?

        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

        func attach(_ operation: Operation) {
            lock.lock(); self.operation = operation; let cancelled = cancelled; lock.unlock()
            if cancelled { operation.cancel() }
        }

        func attachCancellation(_ action: @escaping () -> Void) {
            lock.lock()
            let cancelled = cancelled
            if !cancelled, !completed { cancelGeneration = action }
            lock.unlock()
            if cancelled { FileThumbnailWorker.cancellationQueue.addOperation(action) }
        }

        func finish() {
            lock.lock(); completed = true; operation = nil; cancelGeneration = nil; lock.unlock()
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let operation = operation
            let action = cancelGeneration
            self.operation = nil; cancelGeneration = nil
            lock.unlock()
            operation?.cancel()
            if let action { FileThumbnailWorker.cancellationQueue.addOperation(action) }
        }
    }

    private let queue: OperationQueue
    private let icon: (String) -> CGImage?
    private let generate: Generator

    init(
        queue: OperationQueue? = nil,
        icon: @escaping (String) -> CGImage? = FileThumbnailWorker.fileIcon,
        generate: @escaping Generator = FileThumbnailWorker.thumbnail
    ) {
        let queue = queue ?? OperationQueue()
        queue.name = "dev.whisky.maclx.file-previews"
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .utility
        self.queue = queue
        self.icon = icon
        self.generate = generate
    }

    func start(_ path: String, deliver: @escaping (CGImage?, Bool) -> Void) -> Ticket {
        let ticket = Ticket()
        let operation = BlockOperation { [icon, generate] in
            autoreleasepool {
                guard !ticket.isCancelled else { return }
                let image = icon(path)
                guard !ticket.isCancelled else { return }
                deliver(image, false)
                guard !ticket.isCancelled else { return }
                let cancel = generate(path) { image in
                    defer { ticket.finish() }
                    guard !ticket.isCancelled else { return }
                    deliver(image, true)
                }
                ticket.attachCancellation(cancel)
            }
        }
        ticket.attach(operation)
        queue.addOperation(operation)
        return ticket
    }

    private static func thumbnail(_ path: String, completion: @escaping (CGImage?) -> Void) -> () -> Void {
        let request = QLThumbnailGenerator.Request(
            fileAt: URL(fileURLWithPath: path), size: CGSize(width: 202, height: 96),
            scale: 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            completion(representation?.cgImage)
        }
        return { QLThumbnailGenerator.shared.cancel(request) }
    }

    private static func fileIcon(_ path: String) -> CGImage? {
        let icon = NSWorkspace.shared.icon(forFile: path)
        // Rasterize on this worker too: an NSImage can defer vector drawing
        // until SwiftUI first displays it, moving the stall back to main.
        let pixels = 256
        guard
            let bitmap = CGContext(
                data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap, flipped: false)
        icon.draw(in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.makeImage()
    }
}

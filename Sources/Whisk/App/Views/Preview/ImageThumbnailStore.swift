// WhiskyMac: modified or added 2026-11-15 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Combine

private enum ImageThumbnailWork {
    static let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "dev.whisky.maclx.image-thumbnails"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        return queue
    }()
}

struct ImageThumbnailRequest: Equatable, Sendable {
    let id: UUID
    let content: BinaryContent
    let maxPixelSize: Int

    init(id: UUID, data: Data, maxPixelSize: Int) {
        self.init(id: id, content: .inline(data), maxPixelSize: maxPixelSize)
    }

    init(id: UUID, content: BinaryContent, maxPixelSize: Int) {
        self.id = id
        self.content = content
        self.maxPixelSize = min(ImageThumbnailDecoder.maximumPixelSize, max(1, maxPixelSize))
    }
}

@MainActor
final class ImageThumbnailStore: ObservableObject {
    static let shared = ImageThumbnailStore()
    typealias Decoder = (Data, Int) -> CGImage?

    @Published private(set) var isProtected = false
    private(set) var cachedBytes = 0
    var cachedCount: Int { cache.count }
    var pendingCount: Int { pending.count }

    private struct Key: Hashable {
        let id: UUID
        let pixels: Int
        init(_ request: ImageThumbnailRequest) { id = request.id; pixels = request.maxPixelSize }
    }

    private struct Cached {
        let content: BinaryContent
        let image: NSImage?
        let cost: Int
        var access: UInt64
    }

    private final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
        func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    }

    private final class Pending {
        let generation = UUID()
        let request: ImageThumbnailRequest
        let cancellation = Cancellation()
        var operation: BlockOperation?
        var waiters: [UUID: (NSImage?) -> Void] = [:]
        init(_ request: ImageThumbnailRequest) { self.request = request }
    }

    private var cache: [Key: Cached] = [:]
    private var pending: [Key: Pending] = [:]
    private var access: UInt64 = 0
    private let byteLimit: Int
    private let countLimit: Int
    private let queue: OperationQueue
    private let decoder: Decoder

    init(
        byteLimit: Int = 24 * 1024 * 1024, countLimit: Int = 64,
        queue: OperationQueue? = nil, decoder: @escaping Decoder = ImageThumbnailDecoder.decode
    ) {
        self.byteLimit = max(0, byteLimit)
        self.countLimit = max(1, countLimit)
        self.queue = queue ?? ImageThumbnailWork.queue
        self.decoder = decoder
        self.queue.maxConcurrentOperationCount = 1
    }

    deinit {
        for job in pending.values {
            job.cancellation.cancel()
            job.operation?.cancel()
        }
    }

    func cachedImage(for request: ImageThumbnailRequest) -> NSImage? {
        guard !isProtected, let entry = cache[Key(request)], entry.content == request.content else { return nil }
        touch(Key(request))
        return entry.image
    }

    @discardableResult
    func load(
        _ request: ImageThumbnailRequest, priority: Operation.QueuePriority = .normal,
        completion: @escaping (NSImage?) -> Void
    ) -> UUID? {
        guard !isProtected else { completion(nil); return nil }
        let key = Key(request)
        if let entry = cache[key], entry.content == request.content {
            touch(key)
            completion(entry.image)
            return nil
        }
        removeCached(key)
        if let old = pending[key], old.request.content != request.content { cancelJob(key) }
        let ticket = UUID()
        if let job = pending[key] {
            job.waiters[ticket] = completion
            if priority.rawValue > (job.operation?.queuePriority.rawValue ?? 0) {
                job.operation?.queuePriority = priority
            }
            return ticket
        }
        let job = Pending(request)
        job.waiters[ticket] = completion
        pending[key] = job
        let generation = job.generation
        let cancellation = job.cancellation
        let decoder = self.decoder
        let operation = BlockOperation { [weak self] in
            guard !cancellation.isCancelled else { return }
            let bitmap = autoreleasepool { (try? request.content.read()).flatMap { decoder($0, request.maxPixelSize) } }
            guard !cancellation.isCancelled else { return }
            DispatchQueue.main.async { [weak self] in
                self?.complete(key, generation: generation, bitmap: bitmap)
            }
        }
        operation.queuePriority = priority
        job.operation = operation
        queue.addOperation(operation)
        return ticket
    }

    func cancel(_ ticket: UUID) {
        guard let (key, job) = pending.first(where: { $0.value.waiters[ticket] != nil }) else { return }
        job.waiters[ticket] = nil
        if job.waiters.isEmpty { cancelJob(key) }
    }

    func setPrivacy(_ protected: Bool) {
        isProtected = protected
        guard protected else { return }
        releaseCache()
    }

    func releaseCache() {
        cache.removeAll()
        cachedBytes = 0
        for key in Array(pending.keys) { cancelJob(key) }
    }

    private func cancelJob(_ key: Key) {
        guard let job = pending.removeValue(forKey: key) else { return }
        job.cancellation.cancel()
        job.operation?.cancel()
        job.waiters.values.forEach { $0(nil) }
    }

    private func complete(_ key: Key, generation: UUID, bitmap: CGImage?) {
        guard !isProtected, let job = pending[key], job.generation == generation else { return }
        pending[key] = nil
        let image = bitmap.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        // Retained encoded bytes count too, so a cached source cannot evade the memory budget.
        let sourceCost = job.request.content.reference == nil ? job.request.content.byteCount : 0
        let cost = sourceCost + (bitmap.map { $0.bytesPerRow * $0.height } ?? 0)
        if cost <= byteLimit {
            while !cache.isEmpty, cachedBytes + cost > byteLimit || cache.count >= countLimit {
                guard let oldest = cache.min(by: { $0.value.access < $1.value.access })?.key else { break }
                removeCached(oldest)
            }
            access &+= 1
            cache[key] = Cached(content: job.request.content, image: image, cost: cost, access: access)
            cachedBytes += cost
        }
        job.waiters.values.forEach { $0(image) }
    }

    private func removeCached(_ key: Key) {
        if let entry = cache.removeValue(forKey: key) { cachedBytes -= entry.cost }
    }

    private func touch(_ key: Key) { access &+= 1; cache[key]?.access = access }
}

@MainActor
final class ImageThumbnailLoader: ObservableObject {
    @Published private(set) var image: NSImage?
    @Published private(set) var isLoading = false
    private var displayed: ImageThumbnailRequest?
    private var requested: ImageThumbnailRequest?
    private var ticket: UUID?
    private var generation = UUID()
    private weak var store: ImageThumbnailStore?

    deinit {
        if let ticket, let store {
            Task { @MainActor in store.cancel(ticket) }
        }
    }

    func image(for request: ImageThumbnailRequest) -> NSImage? {
        guard displayed?.id == request.id, displayed?.content == request.content else { return nil }
        return image
    }

    func load(
        _ request: ImageThumbnailRequest, store: ImageThumbnailStore,
        priority: Operation.QueuePriority = .normal
    ) {
        guard requested != request || self.store !== store else { return }
        cancelPending()
        if displayed?.id != request.id || displayed?.content != request.content { image = nil; displayed = nil }
        self.store = store
        requested = request
        isLoading = true
        let generation = self.generation
        ticket = store.load(request, priority: priority) { [weak self] image in
            guard let self, self.generation == generation else { return }
            self.image = image
            self.displayed = request
            self.isLoading = false
            self.ticket = nil
        }
    }

    func cancel() {
        cancelPending()
        requested = nil
        displayed = nil
        image = nil
        isLoading = false
    }

    private func cancelPending() {
        generation = UUID()
        if let ticket { store?.cancel(ticket) }
        ticket = nil
    }
}

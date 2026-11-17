// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Combine
import SwiftUI

/// QuickLook thumbnails for copied files, cached by path. Views fall back
/// to the file-type icon until (or unless) a thumbnail arrives. The cache
/// is bounded by entry count and decoded bytes, evicting the least
/// recently used thumbnails instead of clearing everything at a limit.
@MainActor
final class FileThumbnailStore: ObservableObject {
    static let shared = FileThumbnailStore()

    nonisolated let objectWillChange = ObservableObjectPublisher()
    private(set) var thumbnails: [String: NSImage] = [:]
    private(set) var icons: [String: NSImage] = [:]
    private struct Pending {
        let id = UUID()
        var consumers: Set<UUID> = []
        var ticket: FileThumbnailWorker.Ticket?
    }
    private var requests: [String: Pending] = [:]
    private var waiting: [String] = []
    private let worker: FileThumbnailWorker
    private let concurrency: Int
    private var isPrivate = false
    var pendingCount: Int { requests.count }
    var activeCount: Int { requests.values.filter { $0.ticket != nil }.count }
    private var costs: [String: Int] = [:]
    private var accessOrder: [String: UInt64] = [:]
    private var accessCounter: UInt64 = 0
    private let countLimit: Int
    private let byteLimit: Int
    private(set) var cachedBytes = 0

    nonisolated static let maximumCount = 128
    nonisolated static let maximumBytes = 24 * 1024 * 1024

    init(
        countLimit: Int = FileThumbnailStore.maximumCount, byteLimit: Int = FileThumbnailStore.maximumBytes,
        concurrency: Int = 2, worker: FileThumbnailWorker = .shared
    ) {
        self.countLimit = max(1, countLimit)
        self.byteLimit = max(0, byteLimit)
        self.concurrency = max(1, concurrency)
        self.worker = worker
    }

    deinit { requests.values.forEach { $0.ticket?.cancel() } }

    func setPrivacy(_ protected: Bool) {
        isPrivate = protected
        if protected {
            releaseCache()
        }
    }

    func releaseCache() {
        requests.values.forEach { $0.ticket?.cancel() }
        requests.removeAll()
        waiting.removeAll()
        if !thumbnails.isEmpty || !icons.isEmpty { objectWillChange.send() }
        thumbnails.removeAll()
        icons.removeAll()
        costs.removeAll()
        accessOrder.removeAll()
        cachedBytes = 0
    }

    func image(for path: String) -> NSImage? {
        guard !isPrivate else { return nil }
        if let thumbnail = thumbnail(for: path) { return thumbnail }
        guard let icon = icons[path] else { return nil }
        accessCounter &+= 1; accessOrder[path] = accessCounter
        return icon
    }

    func thumbnail(for path: String) -> NSImage? {
        guard !isPrivate else { return nil }
        guard let image = thumbnails[path] else { return nil }
        accessCounter &+= 1
        accessOrder[path] = accessCounter
        return image
    }

    @discardableResult
    func load(_ path: String) -> UUID? {
        guard !isPrivate, thumbnails[path] == nil else { return nil }
        let consumer = UUID()
        if requests[path] == nil {
            requests[path] = Pending()
            waiting.append(path)
        }
        requests[path]?.consumers.insert(consumer)
        startWaiting()
        return consumer
    }

    func cancel(_ consumer: UUID) {
        guard let path = requests.first(where: { $0.value.consumers.contains(consumer) })?.key else { return }
        requests[path]?.consumers.remove(consumer)
        guard requests[path]?.consumers.isEmpty == true else { return }
        requests.removeValue(forKey: path)?.ticket?.cancel()
        waiting.removeAll { $0 == path }
        startWaiting()
    }

    private func startWaiting() {
        while !isPrivate, activeCount < concurrency, !waiting.isEmpty {
            let path = waiting.removeFirst()
            guard let pending = requests[path] else { continue }
            let id = pending.id
            requests[path]?.ticket = worker.start(path) { [weak self] bitmap, finished in
                DispatchQueue.main.async {
                    guard let self, !self.isPrivate, self.requests[path]?.id == id else { return }
                    if let bitmap {
                        self.cache(NSImage(cgImage: bitmap, size: .zero), for: path, isIcon: !finished)
                    }
                    if finished {
                        self.requests[path] = nil
                        self.startWaiting()
                    }
                }
            }
        }
    }

    /// Keeps a thumbnail for a path — generated in production, canned in
    /// tests.
    func store(_ image: NSImage, for path: String) {
        requests.removeValue(forKey: path)?.ticket?.cancel()
        waiting.removeAll { $0 == path }
        cache(image, for: path, isIcon: false)
        startWaiting()
    }

    private func cache(_ image: NSImage, for path: String, isIcon: Bool) {
        guard !isPrivate else { return }
        let cost = Self.pixelBytes(image)
        guard cost <= byteLimit else { return }
        // One notification for the entire icon/thumbnail replacement and
        // any budget eviction, rather than publishing each dictionary edit.
        objectWillChange.send()
        remove(path)
        if isIcon { icons[path] = image } else { thumbnails[path] = image }
        costs[path] = cost
        cachedBytes += cost
        accessCounter &+= 1
        accessOrder[path] = accessCounter
        evictIfNeeded()
    }

    private func evictIfNeeded() {
        while !costs.isEmpty, cachedBytes > byteLimit || costs.count > countLimit {
            guard let oldest = accessOrder.min(by: { $0.value < $1.value })?.key else { break }
            remove(oldest)
        }
    }

    private func remove(_ path: String) {
        thumbnails[path] = nil
        icons[path] = nil
        if let cost = costs.removeValue(forKey: path) { cachedBytes -= cost }
        accessOrder[path] = nil
    }

    static func pixelBytes(_ image: NSImage) -> Int {
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return cg.bytesPerRow * cg.height
        }
        return max(0, Int(image.size.width * image.size.height * 4))
    }
}

import AppKit
import LinkPresentation
import SwiftUI

/// Page metadata for a copied link — title, icon, lead image.
struct LinkPreview {
    let title: String?
    let host: String?
    let icon: NSImage?
    let image: NSImage?

    var hasContent: Bool {
        title != nil || icon != nil || image != nil
    }
}

/// Fetches and caches link metadata through LinkPresentation. Frameworks
/// ring: it touches the network, so nothing below the views knows about it.
/// Failures are cached too, so a dead link is only fetched once. Images are
/// shrunk to display size before they land in the cache, and the cache is
/// bounded by both entry count and decoded bytes.
@MainActor
final class LinkPreviewStore: ObservableObject {
    static let shared = LinkPreviewStore()

    @Published private(set) var previews: [String: LinkPreview] = [:]
    /// Off, no request leaves the machine and cards show the bare address,
    /// including for links already looked up.
    @Published private(set) var isEnabled = true
    typealias CancelFetch = () -> Void
    typealias Fetch = (URL, @escaping (LPLinkMetadata?) -> Void) -> CancelFetch

    private final class Request {
        let url: URL
        var consumers: Set<UUID> = []
        var cancelFetch: (() -> Void)?
        var images: Progress?

        init(url: URL) { self.url = url }
        func cancel() {
            cancelFetch?()
            images?.cancel()
        }
    }

    private let fetch: Fetch
    private var requests: [String: Request] = [:]
    private var waiting: [String] = []
    private static let concurrency = 2
    var activeCount: Int { requests.values.filter { $0.cancelFetch != nil }.count }
    var pendingCount: Int { requests.count }
    @Published private var isPrivate = false
    @Published private var hiddenAddresses: Set<String> = []
    private var costs: [String: Int] = [:]
    private var accessOrder: [String: UInt64] = [:]
    private var accessCounter: UInt64 = 0
    private let countLimit: Int
    private let byteLimit: Int
    private(set) var cachedBytes = 0

    nonisolated static let maximumCount = 96
    nonisolated static let maximumBytes = 24 * 1024 * 1024
    nonisolated static let maximumImageDimension: CGFloat = 640

    init(
        countLimit: Int = LinkPreviewStore.maximumCount, byteLimit: Int = LinkPreviewStore.maximumBytes,
        fetch: @escaping Fetch = LinkPreviewStore.fetchMetadata
    ) {
        self.fetch = fetch
        self.countLimit = max(1, countLimit)
        self.byteLimit = max(0, byteLimit)
    }

    deinit { requests.values.forEach { $0.cancel() } }

    nonisolated private static func fetchMetadata(_ url: URL, completion: @escaping (LPLinkMetadata?) -> Void)
        -> CancelFetch
    {
        let provider = LPMetadataProvider()
        provider.timeout = 6
        provider.startFetchingMetadata(for: url) { metadata, _ in completion(metadata) }
        return { provider.cancel() }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if !enabled { cancelRequests() }
    }

    func setPrivacy(_ protected: Bool) {
        guard isPrivate != protected else { return }
        isPrivate = protected
        if protected {
            releaseCache()
        }
    }

    func releaseCache() {
        cancelRequests()
        previews.removeAll(); costs.removeAll(); accessOrder.removeAll(); cachedBytes = 0
    }

    func setHiddenAddresses(_ addresses: Set<String>) {
        guard hiddenAddresses != addresses else { return }
        hiddenAddresses = addresses
        for address in Array(requests.keys) where addresses.contains(address) {
            discardRequest(address)
        }
        startWaiting()
        let removed = previews.keys.filter(addresses.contains)
        for address in removed { remove(address) }
    }

    private func cancelRequests() {
        waiting.removeAll()
        let old = requests
        requests.removeAll()
        old.values.forEach { $0.cancel() }
    }

    func allowsPreview(for address: String) -> Bool {
        isEnabled && !isPrivate && !hiddenAddresses.contains(address)
    }

    func preview(for address: String) -> LinkPreview? {
        guard allowsPreview(for: address) else { return nil }
        guard previews[address] != nil else { return nil }
        accessCounter &+= 1
        accessOrder[address] = accessCounter
        return previews[address]
    }

    @discardableResult
    func load(_ address: String) -> UUID? {
        guard allowsPreview(for: address), previews[address] == nil,
            let url = URL(string: address), let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else { return nil }
        let consumer = UUID()
        if let existing = requests[address] {
            existing.consumers.insert(consumer)
        } else {
            let request = Request(url: url)
            request.consumers.insert(consumer)
            requests[address] = request
            waiting.append(address)
            startWaiting()
        }
        return consumer
    }

    func cancel(_ consumer: UUID) {
        guard let (address, request) = requests.first(where: { $0.value.consumers.contains(consumer) }) else { return }
        request.consumers.remove(consumer)
        if request.consumers.isEmpty {
            discardRequest(address)
            startWaiting()
        }
    }

    private func discardRequest(_ address: String) {
        waiting.removeAll { $0 == address }
        requests.removeValue(forKey: address)?.cancel()
    }

    private func startWaiting() {
        while !waiting.isEmpty && activeCount < Self.concurrency {
            let address = waiting.removeFirst()
            guard let request = requests[address] else { continue }
            request.cancelFetch = fetch(request.url) { [weak self, weak request] metadata in
                DispatchQueue.main.async {
                    guard let self, let request, self.requests[address] === request else { return }
                    request.images = Self.assemble(metadata: metadata, host: request.url.host) {
                        [weak self, weak request] preview in
                        guard let self, let request, self.requests[address] === request else { return }
                        self.requests[address] = nil
                        self.insert(preview, for: address)
                        self.startWaiting()
                    }
                }
            }
        }
    }

    /// Keeps a preview for an address — fetched in production, canned in
    /// tests — and lets the address be fetched again later. Count and
    /// decoded-byte budgets evict the least recently used entries; one
    /// image larger than the whole byte budget is not kept at all.
    func store(_ preview: LinkPreview, for address: String) {
        guard !isPrivate, !hiddenAddresses.contains(address) else { return }
        discardRequest(address)
        let resized = LinkPreview(
            title: preview.title, host: preview.host,
            icon: preview.icon.map(Self.downscaled),
            image: preview.image.map(Self.downscaled))
        insert(resized, for: address)
        startWaiting()
    }

    private func insert(_ resized: LinkPreview, for address: String) {
        remove(address)
        let cost = Self.cost(of: resized)
        guard cost <= byteLimit else { return }
        previews[address] = resized
        costs[address] = cost
        cachedBytes += cost
        accessCounter &+= 1
        accessOrder[address] = accessCounter
        evictIfNeeded()
    }

    private func evictIfNeeded() {
        while !previews.isEmpty, cachedBytes > byteLimit || previews.count > countLimit {
            guard let oldest = accessOrder.min(by: { $0.value < $1.value })?.key else { break }
            remove(oldest)
        }
    }

    private func remove(_ address: String) {
        guard previews[address] != nil else { return }
        previews[address] = nil
        if let cost = costs.removeValue(forKey: address) { cachedBytes -= cost }
        accessOrder[address] = nil
    }

    static func cost(of preview: LinkPreview) -> Int {
        (preview.icon.map(pixelBytes) ?? 0) + (preview.image.map(pixelBytes) ?? 0)
    }

    /// The decoded pixel storage an image is holding right now.
    static func pixelBytes(_ image: NSImage) -> Int {
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return cg.bytesPerRow * cg.height
        }
        return max(0, Int(image.size.width * image.size.height * 4))
    }

    /// LinkPresentation hands over original-size bitmaps; the largest card
    /// or overlay display is far smaller, so store only what can be shown.
    nonisolated static func downscaled(_ image: NSImage) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), cg.width > 0, cg.height > 0
        else { return image }
        let scale = maximumImageDimension / CGFloat(max(cg.width, cg.height))
        guard scale < 1 else { return image }
        let width = max(1, Int((CGFloat(cg.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(cg.height) * scale).rounded()))
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        context.interpolationQuality = .high
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let bitmap = context.makeImage() else { return image }
        // A standalone bitmap; a drawing-handler NSImage would capture and
        // retain the original, defeating the cache's decoded-byte budget.
        return NSImage(cgImage: bitmap, size: NSSize(width: width, height: height))
    }

    private nonisolated static let imageQueue = DispatchQueue(label: "dev.whisky.maclx.link-images", qos: .utility)

    @discardableResult
    nonisolated static func assemble(
        metadata: LPLinkMetadata?,
        host: String?,
        completion: @escaping (LinkPreview) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 2)
        guard let metadata else {
            completion(LinkPreview(title: nil, host: host, icon: nil, image: nil))
            return progress
        }
        let group = DispatchGroup()
        var icon: NSImage?
        var image: NSImage?
        func load(_ provider: NSItemProvider?, assign: @escaping (NSImage?) -> Void) {
            group.enter()
            let child = loadImage(from: provider) { source in
                imageQueue.async {
                    if !progress.isCancelled {
                        assign(autoreleasepool { source.map(Self.downscaled) })
                    }
                    group.leave()
                }
            }
            if let child { progress.addChild(child, withPendingUnitCount: 1) }
        }
        load(metadata.iconProvider) { icon = $0 }
        load(metadata.imageProvider) { image = $0 }
        group.notify(queue: .main) {
            guard !progress.isCancelled else { return }
            completion(LinkPreview(title: metadata.title, host: host, icon: icon, image: image))
        }
        return progress
    }

    @discardableResult
    nonisolated static func loadImage(from provider: NSItemProvider?, completion: @escaping (NSImage?) -> Void)
        -> Progress?
    {
        guard let provider, provider.canLoadObject(ofClass: NSImage.self) else {
            completion(nil)
            return nil
        }
        return provider.loadObject(ofClass: NSImage.self) { object, _ in
            completion(object as? NSImage)
        }
    }
}

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
    private var providers: [String: LPMetadataProvider] = [:]
    private var generation = 0
    private var isPrivate = false
    private var hiddenAddresses: Set<String> = []
    private var inFlight: Set<String> = []
    private var costs: [String: Int] = [:]
    private var accessOrder: [String: UInt64] = [:]
    private var accessCounter: UInt64 = 0
    private let countLimit: Int
    private let byteLimit: Int
    private(set) var cachedBytes = 0

    nonisolated static let maximumCount = 96
    nonisolated static let maximumBytes = 24 * 1024 * 1024
    nonisolated static let maximumImageDimension: CGFloat = 640

    init(countLimit: Int = LinkPreviewStore.maximumCount, byteLimit: Int = LinkPreviewStore.maximumBytes) {
        self.countLimit = max(1, countLimit)
        self.byteLimit = max(0, byteLimit)
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled { cancelRequests() }
    }

    func setPrivacy(_ protected: Bool) {
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
        cancelRequests()
        let removed = previews.keys.filter(addresses.contains)
        for address in removed { remove(address) }
    }

    private func cancelRequests() {
        generation += 1
        providers.values.forEach { $0.cancel() }
        providers.removeAll()
        inFlight.removeAll()
    }

    func preview(for address: String) -> LinkPreview? {
        guard isEnabled && !isPrivate && !hiddenAddresses.contains(address) else { return nil }
        guard previews[address] != nil else { return nil }
        accessCounter &+= 1
        accessOrder[address] = accessCounter
        return previews[address]
    }

    func load(_ address: String) {
        guard isEnabled, !isPrivate, !hiddenAddresses.contains(address), previews[address] == nil,
            !inFlight.contains(address),
            let url = URL(string: address)
        else { return }
        inFlight.insert(address)
        let generation = generation
        let provider = LPMetadataProvider()
        providers[address] = provider
        provider.timeout = 6
        provider.startFetchingMetadata(for: url) { [weak self] metadata, _ in
            Self.assemble(metadata: metadata, host: url.host) { preview in
                DispatchQueue.main.async {
                    guard let self, self.generation == generation, !self.isPrivate, self.isEnabled else { return }
                    self.providers[address] = nil
                    self.store(preview, for: address)
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
        remove(address)
        let resized = LinkPreview(
            title: preview.title, host: preview.host,
            icon: preview.icon.map(Self.downscaled),
            image: preview.image.map(Self.downscaled))
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
        inFlight.remove(address)
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
    static func downscaled(_ image: NSImage) -> NSImage {
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

    nonisolated static func assemble(
        metadata: LPLinkMetadata?,
        host: String?,
        completion: @escaping (LinkPreview) -> Void
    ) {
        guard let metadata else {
            completion(LinkPreview(title: nil, host: host, icon: nil, image: nil))
            return
        }
        let group = DispatchGroup()
        var icon: NSImage?
        var image: NSImage?
        group.enter()
        loadImage(from: metadata.iconProvider) {
            icon = $0
            group.leave()
        }
        group.enter()
        loadImage(from: metadata.imageProvider) {
            image = $0
            group.leave()
        }
        group.notify(queue: .main) {
            completion(LinkPreview(title: metadata.title, host: host, icon: icon, image: image))
        }
    }

    nonisolated static func loadImage(from provider: NSItemProvider?, completion: @escaping (NSImage?) -> Void) {
        guard let provider, provider.canLoadObject(ofClass: NSImage.self) else {
            completion(nil)
            return
        }
        _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
            completion(object as? NSImage)
        }
    }
}

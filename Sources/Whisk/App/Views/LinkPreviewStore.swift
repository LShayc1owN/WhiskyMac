// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

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
/// Failures are cached too, so a dead link is only fetched once.
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
    private var inFlight: Set<String> = []

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled { cancelRequests() }
    }

    func setPrivacy(_ protected: Bool) {
        isPrivate = protected
        if protected {
            cancelRequests()
            previews.removeAll()
        }
    }

    private func cancelRequests() {
        generation += 1
        providers.values.forEach { $0.cancel() }
        providers.removeAll()
        inFlight.removeAll()
    }

    func preview(for address: String) -> LinkPreview? {
        isEnabled && !isPrivate ? previews[address] : nil
    }

    func load(_ address: String) {
        guard isEnabled, !isPrivate, previews[address] == nil, !inFlight.contains(address),
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
    /// tests — and lets the address be fetched again later.
    func store(_ preview: LinkPreview, for address: String) {
        guard !isPrivate else { return }
        if previews.count >= Self.limit {
            previews.removeAll()
        }
        previews[address] = preview
        inFlight.remove(address)
    }

    /// Distinct links seen in a session; past it the oldest go together —
    /// a refetch costs one request, an unbounded dictionary costs memory.
    static let limit = 512

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

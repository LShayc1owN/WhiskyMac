// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import QuickLookThumbnailing
import SwiftUI

/// QuickLook thumbnails for copied files, cached by path. Views fall back
/// to the file-type icon until (or unless) a thumbnail arrives.
@MainActor
final class FileThumbnailStore: ObservableObject {
    static let shared = FileThumbnailStore()

    @Published private(set) var thumbnails: [String: NSImage] = [:]
    private var requests: [String: QLThumbnailGenerator.Request] = [:]
    private var generation = 0
    private var isPrivate = false
    private var inFlight: Set<String> = []

    func setPrivacy(_ protected: Bool) {
        isPrivate = protected
        if protected {
            generation += 1
            requests.values.forEach { QLThumbnailGenerator.shared.cancel($0) }
            requests.removeAll()
            inFlight.removeAll()
            thumbnails.removeAll()
        }
    }

    func thumbnail(for path: String) -> NSImage? {
        isPrivate ? nil : thumbnails[path]
    }

    func load(_ path: String) {
        guard !isPrivate, thumbnails[path] == nil, !inFlight.contains(path) else { return }
        inFlight.insert(path)
        let request = QLThumbnailGenerator.Request(
            fileAt: URL(fileURLWithPath: path),
            size: CGSize(width: 202, height: 96),
            scale: 2,
            representationTypes: .thumbnail
        )
        requests[path] = request
        let generation = generation
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            let image = (representation?.cgImage).map { NSImage(cgImage: $0, size: .zero) }
            DispatchQueue.main.async {
                guard let self, self.generation == generation, !self.isPrivate else { return }
                self.requests[path] = nil
                self.inFlight.remove(path)
                if let image { self.store(image, for: path) }
            }
        }
    }

    /// Keeps a thumbnail for a path — generated in production, canned in
    /// tests.
    func store(_ image: NSImage, for path: String) {
        guard !isPrivate else { return }
        if thumbnails.count >= Self.limit {
            thumbnails.removeAll()
        }
        thumbnails[path] = image
        inFlight.remove(path)
    }

    /// Distinct files thumbnailed in a session; past it they go together.
    static let limit = 512
}

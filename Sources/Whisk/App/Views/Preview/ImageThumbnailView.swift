// WhiskyMac: modified or added 2026-11-15 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

struct ImageThumbnailView: View {
    let id: UUID
    let content: BinaryContent
    var fills = false
    var isActive = true
    @ObservedObject var thumbnails = ImageThumbnailStore.shared
    @StateObject private var loader = ImageThumbnailLoader()
    @Environment(\.displayScale) private var displayScale

    init(id: UUID, data: Data, fills: Bool = false, isActive: Bool = true) {
        self.init(id: id, content: .inline(data), fills: fills, isActive: isActive)
    }

    init(id: UUID, content: BinaryContent, fills: Bool = false, isActive: Bool = true) {
        self.id = id; self.content = content; self.fills = fills; self.isActive = isActive
    }

    var body: some View {
        GeometryReader { geometry in
            let pixels = Self.pixelSize(for: geometry.size, scale: displayScale, fills: fills)
            let request = ImageThumbnailRequest(id: id, content: content, maxPixelSize: pixels)
            Color.clear.overlay {
                if isActive, !thumbnails.isProtected, let image = loader.image(for: request) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: fills ? .fill : .fit)
                } else if isActive, !thumbnails.isProtected, loader.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onAppear { if isActive, pixels > 0 { load(request) } }
            .onChange(of: request) { _, value in if isActive, pixels > 0 { load(value) } }
            .onChange(of: isActive) { _, active in
                if active, pixels > 0 { load(request) } else { loader.cancel() }
            }
            .onChange(of: thumbnails.isProtected) { _, protected in
                if protected { loader.cancel() } else if isActive, pixels > 0 { load(request) }
            }
            .onDisappear { loader.cancel() }
        }
        .accessibilityLabel(localized("Image"))
    }

    private func load(_ request: ImageThumbnailRequest) {
        loader.load(request, store: thumbnails, priority: fills ? .normal : .veryHigh)
    }

    static func pixelSize(for size: CGSize, scale: CGFloat, fills: Bool) -> Int {
        let dimension = max(size.width, size.height) * max(1, scale) * (fills ? 1.05 : 1)
        guard dimension.isFinite, dimension > 0 else { return 0 }
        let limit = fills ? 512 : ImageThumbnailDecoder.maximumPixelSize
        let pixels = Int(min(CGFloat(limit), ceil(dimension)))
        return min(limit, max(64, (pixels + 63) / 64 * 64))
    }
}

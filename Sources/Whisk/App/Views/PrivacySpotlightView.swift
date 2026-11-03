// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import ImageIO
import SwiftUI

/// Protected cards publish only identities. A single hovered item is fetched
/// after the dwell; Canvas emits no content accessibility descendants.
struct PrivacySpotlightView: View {
    @ObservedObject var store: HistoryViewStateStore
    var body: some View {
        VStack(spacing: 12) {
            Label(
                store.allowsSpotlight && store.interactions.hover == .preview
                    ? localized("Manual privacy: hover to reveal a small area")
                    : localized("Content hidden by Privacy Mode"), systemImage: "eye.slash"
            )
            .font(.caption).foregroundStyle(.secondary)
            if store.privacyAllowsSearch {
                TextField(
                    localized("Search clipboard history"),
                    text: Binding(
                        get: { store.protectedQuery }, set: { store.searchWhileProtected($0) })
                )
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 480)
                .padding(.horizontal, 16)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: HistoryViewStateStore.cardGap) {
                    ForEach(store.protectedCardIDs, id: \.self) { id in
                        VStack(spacing: 6) {
                            if let source = store.protectedSourceLabel(for: id) {
                                Text(source).font(.caption).lineLimit(1)
                                    .frame(width: store.cardSide, alignment: .leading)
                            }
                            SpotlightCard(store: store, id: id)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: store.cardSide + (store.privacyShowsSourceApps ? 42 : 16))
            if store.privacyAllowsSearch, store.protectedCardIDs.isEmpty {
                Text(localized("No matches")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 18)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localized("Content hidden by Privacy Mode"))
    }
}

private struct SpotlightCard: View {
    @ObservedObject var store: HistoryViewStateStore
    let id: UUID
    @State private var point: CGPoint?
    @State private var payload: Payload?
    @State private var thumbnail: NSImage?
    @State private var task: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SpotlightCardSurface(side: store.cardSide, payload: payload, point: point, thumbnail: thumbnail)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    point = location
                    guard task == nil else { return }
                    task = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(store.interactions.hoverDelay))
                        guard !Task.isCancelled, point != nil else { return }
                        let value = store.spotlightPayload(for: id)
                        if case .image(let data) = value { thumbnail = SpotlightCanvas.thumbnail(data) }
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { payload = value }
                    }
                case .ended: clear()
                }
            }
            .onDisappear { clear() }
            .onChange(of: store.interactions) { _, _ in clear() }
            .onChange(of: store.allowsSpotlight) { _, _ in clear() }
            .accessibilityHidden(true)
    }

    private func clear() {
        task?.cancel()
        task = nil
        payload = nil
        thumbnail = nil
        point = nil
    }
}

/// Revealing content only updates the overlay; the rail always measures the
/// same fixed card surface, including during its opacity transition.
struct SpotlightCardSurface: View {
    let side: CGFloat
    var payload: Payload?
    var point: CGPoint?
    var thumbnail: NSImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(.regularMaterial)
            .frame(width: side, height: side)
            .overlay {
                ZStack {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                    if let point, let payload {
                        SpotlightCanvas(payload: payload, point: point, thumbnail: thumbnail)
                            .transition(.opacity)
                            .allowsHitTesting(false)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))

    }
}

struct SpotlightCanvas: View {
    let payload: Payload
    let point: CGPoint
    var thumbnail: NSImage?

    var body: some View {
        Canvas { context, size in
            // Clip before drawing: no full unmasked preview surface.
            context.clip(to: Path(ellipseIn: SpotlightGeometry.revealBounds(around: point)))
            context.fill(
                Path(CGRect(origin: .zero, size: size)), with: .color(Color(nsColor: .windowBackgroundColor)))
            switch payload {
            case .text(let text): draw(text, in: &context, size: size)
            case .link(let url): draw(url.absoluteString, in: &context, size: size)
            case .fileReferences(let paths):
                draw(
                    paths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: "\n"),
                    in: &context, size: size)
            case .image:
                if let image = thumbnail {
                    context.draw(
                        Image(nsImage: image), in: SpotlightGeometry.imageRect(imageSize: image.size, canvasSize: size))
                }
            }
        }
        .mask {
            RadialGradient(
                colors: [.white, .clear], center: .center,
                startRadius: SpotlightGeometry.innerRadius, endRadius: SpotlightGeometry.outerRadius
            )
            .frame(width: SpotlightGeometry.outerRadius * 2, height: SpotlightGeometry.outerRadius * 2)
            .position(point)
        }
    }

    static func thumbnail(_ data: Data) -> NSImage? {
        guard data.count <= 8 * 1024 * 1024,
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 512,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                ] as CFDictionary)
        else { return nil }
        return NSImage(cgImage: image, size: .zero)
    }

    private func draw(_ text: String, in context: inout GraphicsContext, size: CGSize) {
        // Render a bounded card excerpt, not an RTF decoder, URL fetch or QL request.
        let resolved = context.resolve(
            Text(String(text.prefix(4000))).font(.system(size: 14)).foregroundColor(.primary))
        let measured = resolved.measure(in: CGSize(width: max(1, size.width - 24), height: .greatestFiniteMagnitude))
        // Let long text extend below the card and clip it, rather than asking
        // the card's height to constrain the paragraph's layout.
        context.draw(resolved, in: CGRect(origin: CGPoint(x: 12, y: 12), size: measured))
    }

}

/// Geometry stays independent of reveal state and source image proportions.
enum SpotlightGeometry {
    static let innerRadius: CGFloat = 56
    static let outerRadius: CGFloat = 80

    static func revealBounds(around point: CGPoint) -> CGRect {
        CGRect(
            x: point.x - outerRadius, y: point.y - outerRadius,
            width: outerRadius * 2, height: outerRadius * 2)
    }

    static func imageRect(imageSize: CGSize, canvasSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
            imageSize.width.isFinite, imageSize.height.isFinite,
            canvasSize.width > 0, canvasSize.height > 0
        else { return .zero }
        let scale = min(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (canvasSize.width - size.width) / 2, y: (canvasSize.height - size.height) / 2,
            width: size.width, height: size.height)
    }
}

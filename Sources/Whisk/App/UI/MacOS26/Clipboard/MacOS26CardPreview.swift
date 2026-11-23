// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

@available(macOS 26, *)
struct MacOS26CardPreview: View {
    let card: CardViewState
    let isActive: Bool

    private let mediaShape = ConcentricRectangle(corners: .concentric(minimum: .fixed(10)), isUniform: true)

    var body: some View {
        Group {
            if card.contentHidden {
                VStack(alignment: .leading, spacing: 6) {
                    if case .text(let placeholder) = card.preview { Text(placeholder).lineLimit(1) }
                    Label(localized("Content always hidden"), systemImage: "eye.slash")
                        .lineLimit(2)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            } else if let richText = card.richText, case .text(let fallback) = card.dragPayload {
                MacOS26RichCardExcerpt(content: richText, fallback: fallback, matches: card.matches, active: isActive)
            } else {
                payload
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var payload: some View {
        switch card.preview {
        case .text(let value):
            if card.matches.isEmpty {
                Text(value).font(.callout)
            } else {
                Text(CardTextFormatting.highlighted(value, matches: card.matches)).font(.callout)
            }
        case .code(let value, let tokens):
            Text(CardTextFormatting.attributed(value, tokens: tokens, matches: card.matches))
                .font(.system(.callout, design: .monospaced))
                .lineSpacing(2)
        case .color(let code, let rgb):
            VStack(alignment: .leading, spacing: 7) {
                mediaShape.fill(Color(red: rgb.red, green: rgb.green, blue: rgb.blue).opacity(rgb.alpha))
                    .background(.fill.quaternary, in: mediaShape)
                    .overlay(mediaShape.stroke(.primary.opacity(0.13), lineWidth: 1))
                Text(code).font(.callout.monospaced()).lineLimit(1)
            }
        case .image(let data):
            MacOS26CardThumbnail(id: card.id, content: .inline(data), active: isActive).clipShape(mediaShape)
        case .storedImage(let reference):
            MacOS26CardThumbnail(id: card.id, content: .stored(reference), active: isActive).clipShape(mediaShape)
        case .link(let address):
            MacOS26LinkCardExcerpt(address: address, active: isActive)
        case .files(let names, let overflow, let path):
            MacOS26FileCardExcerpt(names: names, overflow: overflow, path: path, active: isActive)
        }
    }
}

@available(macOS 26, *)
private struct MacOS26CardThumbnail: View {
    let id: UUID
    let content: BinaryContent
    let active: Bool

    @ObservedObject private var store = ImageThumbnailStore.shared
    @StateObject private var loader = ImageThumbnailLoader()
    @Environment(\.displayScale) private var displayScale

    private struct Work: Equatable {
        let request: ImageThumbnailRequest
        let isEnabled: Bool
    }

    var body: some View {
        GeometryReader { geometry in
            let request = ImageThumbnailRequest(id: id, content: content, maxPixelSize: pixelSize(geometry.size))
            let work = Work(
                request: request,
                isEnabled: active && !store.isProtected && geometry.size.width > 0 && geometry.size.height > 0)
            ZStack {
                Rectangle().fill(.fill.quaternary)
                if work.isEnabled, let image = loader.image(for: request) ?? store.cachedImage(for: request) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else if work.isEnabled && loader.isLoading && store.lightweightMode {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "photo").font(.title3).foregroundStyle(.secondary)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .task(id: work) {
                guard !Task.isCancelled else { return }
                if work.isEnabled { loader.load(request, store: store) } else { loader.cancel() }
            }
            .onDisappear { loader.cancel() }
        }
    }

    private func pixelSize(_ size: CGSize) -> Int {
        let limit = ImageThumbnailRequest.cardPixelLimit
        guard store.lightweightMode else { return limit }
        let dimension = min(CGFloat(limit), max(size.width, size.height) * displayScale * 1.05)
        return min(limit, max(64, (Int(dimension.rounded(.up)) + 63) / 64 * 64))
    }
}

@available(macOS 26, *)
private struct MacOS26LinkCardExcerpt: View {
    let address: String
    let active: Bool

    @ObservedObject private var store = LinkPreviewStore.shared
    @State private var ticket: UUID?

    private struct Request: Equatable {
        let address: String
        let enabled: Bool
    }

    var body: some View {
        let request = Request(address: address, enabled: active && store.allowsPreview(for: address))
        let preview = request.enabled ? store.preview(for: address) : nil
        VStack(alignment: .leading, spacing: 6) {
            if let image = preview?.image {
                ViewThatFits(in: .vertical) {
                    VStack(alignment: .leading, spacing: 6) {
                        GeometryReader { geometry in
                            Image(nsImage: image)
                                .resizable().scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        }
                        .frame(height: 62)
                        .clipShape(.rect(corners: .concentric(minimum: .fixed(10))))
                        identity(preview)
                    }
                    identity(preview)
                }
            } else {
                identity(preview)
            }
        }
        .task(id: request) {
            guard !Task.isCancelled else { return }
            cancel()
            if request.enabled { ticket = store.load(address) }
        }
        .onDisappear(perform: cancel)
    }

    private func identity(_ preview: LinkPreview?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if let icon = preview?.icon {
                    Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                } else {
                    Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
                }
                Text(preview?.title ?? address)
                    .font(.callout.weight(.medium))
                    .lineLimit(preview?.image == nil ? 4 : 2)
            }
            if let host = preview?.host, preview?.title != nil {
                Text(host).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func cancel() {
        if let ticket { store.cancel(ticket) }
        ticket = nil
    }
}

@available(macOS 26, *)
private struct MacOS26FileCardExcerpt: View {
    let names: [String]
    let overflow: Int
    let path: String?
    let active: Bool

    @ObservedObject private var store = FileThumbnailStore.shared
    @State private var ticket: UUID?

    private struct Request: Equatable {
        let path: String?
        let active: Bool
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            if let path, active {
                VStack(alignment: .leading, spacing: 7) {
                    (store.image(for: path).map(Image.init(nsImage:)) ?? Image(systemName: "doc"))
                        .resizable().scaledToFit().frame(maxWidth: .infinity)
                        .frame(height: 54)
                    fileNames(limit: names.count)
                }
            }
            fileNames(limit: names.count)
            fileNames(limit: 2)
            fileNames(limit: 1)
        }
        .task(id: Request(path: path, active: active)) {
            guard !Task.isCancelled else { return }
            cancel()
            if active, let path { ticket = store.load(path, checkingCachedFile: true) }
        }
        .onDisappear(perform: cancel)
    }

    private func fileNames(limit: Int) -> some View {
        let count = min(limit, names.count)
        let hidden = overflow + names.count - count
        return VStack(alignment: .leading, spacing: 5) {
            ForEach(names.indices.prefix(count), id: \.self) { index in
                Label(names[index], systemImage: "doc").font(.caption).lineLimit(1)
            }
            if hidden > 0 { Text(localized("+ \(hidden) more")).font(.caption2).foregroundStyle(.secondary) }
        }
    }

    private func cancel() {
        if let ticket { store.cancel(ticket) }
        ticket = nil
    }
}

@available(macOS 26, *)
private struct MacOS26RichCardExcerpt: View {
    let content: BinaryContent
    let fallback: String
    let matches: [MatchSpan]
    let active: Bool

    @State private var loaded: (request: Request, text: NSAttributedString)?

    private struct Request: Equatable {
        let content: BinaryContent
        let fallback: String
        let active: Bool
    }

    var body: some View {
        let request = Request(content: content, fallback: fallback, active: active)
        Group {
            if let loaded, active, loaded.request == request {
                Drawing(text: loaded.text, matches: fallback.hasPrefix(loaded.text.string) ? matches : [])
            } else {
                Text(CardTextFormatting.highlighted(fallback, matches: matches)).font(.callout)
            }
        }
        .task(id: request) {
            loaded = nil
            guard request.active,
                let data = await RichTextPreviewReader.shared.read(
                    content, maximumBytes: RichTextCardContent.maximumBytes),
                !Task.isCancelled
            else { return }
            loaded = (request, RichTextCardContent.decode(data, fallback: fallback))
        }
        .onDisappear { loaded = nil }
    }

    private struct Drawing: NSViewRepresentable {
        let text: NSAttributedString
        let matches: [MatchSpan]

        func makeNSView(context: Context) -> Surface { Surface() }

        func updateNSView(_ view: Surface, context: Context) {
            guard !view.source.isEqual(to: text) || view.matches != matches else { return }
            view.source = text
            view.matches = matches
            let styled = NSMutableAttributedString(attributedString: text)
            styled.removeAttribute(.link, range: NSRange(location: 0, length: styled.length))
            for span in matches where span.start >= 0 && span.start < styled.length && span.length > 0 {
                styled.addAttribute(
                    .underlineStyle, value: NSUnderlineStyle.single.rawValue,
                    range: NSRange(location: span.start, length: min(span.length, styled.length - span.start)))
            }
            view.styled = styled
            view.needsDisplay = true
        }

        final class Surface: NSView {
            var source = NSAttributedString()
            var matches: [MatchSpan] = []
            var styled = NSAttributedString()

            override var isFlipped: Bool { true }
            override func hitTest(_ point: NSPoint) -> NSView? { nil }
            override func draw(_ dirtyRect: NSRect) {
                styled.draw(
                    with: bounds, options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine])
            }
        }
    }
}

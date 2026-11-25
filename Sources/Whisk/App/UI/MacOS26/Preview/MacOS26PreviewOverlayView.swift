// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

/// Space-bar preview: the selected card, live-updated as the selection
/// moves. The window decides the size — a short screen hands it less
/// room — and the content adapts to whatever it gets.
@available(macOS 26, *)
struct MacOS26PreviewOverlayView: View {
    @Environment(\.interfaceTypography) private var typography

    @ObservedObject var store: HistoryViewStateStore

    var actions: PanelActions? = nil

    var body: some View {
        Group {
            if store.isProtected {
                MacOS26PrivacyPlaceholder()
            } else if let card = store.previewCard {
                MacOS26HeaderContentLayout {
                    ViewThatFits(in: .vertical) {
                        header(for: card).fixedSize(horizontal: false, vertical: true)
                        ScrollView { header(for: card) }
                            .scrollIndicators(.visible)
                            .id(card.id)
                    }

                    Group {
                        if let source = store.previewItems.first, source.splitGroup != nil {
                            MacOS26SplitGroupPreview(source: source)
                        } else if store.previewItems.contains(where: { $0.hasRichText }) {
                            richVersions
                        } else {
                            content(for: card)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .padding(20)
            } else {
                Text(localized("Nothing selected"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacOS26ClipboardMaterialSurface(shape: RoundedRectangle(cornerRadius: 24), cornerRadius: 24))
    }

    private func header(for card: CardViewState) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                sourceLabel(for: card)
                Spacer(minLength: 0)
                metadata(for: card)
            }

            VStack(alignment: .leading, spacing: 4) {
                sourceLabel(for: card)
                metadata(for: card)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sourceLabel(for card: CardViewState) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let icon = SourceAppStyle.resolve(bundleID: card.sourceBundleID).icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                    .accessibilityHidden(true)
            }
            Text(card.sourceLabel)
                .font(typography.font(.headline))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func metadata(for card: CardViewState) -> some View {
        Text("\(card.kindLabel) · \(card.timeLabel)")
            .font(typography.font(.caption))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var visibleVersions: ArraySlice<ClipboardItem> {
        store.previewItems.prefix(store.expandedVersions ? store.previewItems.count : 2)
    }

    private var richVersions: some View {
        GeometryReader { geometry in
            if typography.usesLargeLayout || geometry.size.height < typography.room(170) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        versionPrompt
                        ForEach(visibleVersions) { item in
                            version(item, paneHeight: 112)
                        }
                        moreVersionsButton
                    }
                }
                .scrollIndicators(.visible)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    versionPrompt
                    GeometryReader { columns in
                        ScrollView(.horizontal) {
                            LazyHStack(alignment: .top, spacing: 16) {
                                ForEach(visibleVersions) { item in
                                    version(item)
                                        .frame(
                                            width: min(340, max(240, (columns.size.width - 16) / 2)),
                                            height: columns.size.height, alignment: .topLeading)
                                }
                            }
                        }
                    }
                    moreVersionsButton
                }
            }
        }
    }

    @ViewBuilder private var versionPrompt: some View {
        if store.pendingAction != nil {
            Text(localized("Choose a format to continue"))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func version(_ item: ClipboardItem, paneHeight: CGFloat? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.source?.name ?? localized("Rich text"))
                .font(typography.font(.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            MacOS26RichTextPreviewPane(item: item)
                .frame(height: paneHeight)
                .frame(maxWidth: .infinity, maxHeight: paneHeight == nil ? .infinity : nil)
            if let actions {
                Button {
                    store.chooseVersion(item.id, actions: actions)
                } label: {
                    Text(store.pendingAction?.label ?? localized("Copy"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.borderless)
                .layoutPriority(1)
            }
        }
    }

    @ViewBuilder private var moreVersionsButton: some View {
        if store.previewItems.count > 2 {
            Button {
                store.expandedVersions.toggle()
            } label: {
                Text(store.expandedVersions ? localized("Show fewer formats") : "+\(store.previewItems.count - 2)")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder private func content(for card: CardViewState) -> some View {
        switch card.preview {
        case .text(let value):
            MacOS26TextPreviewView(text: store.previewItems.first?.payload.transformableText ?? value)
        case .code(let text, let tokens):
            let full = store.previewItems.first?.payload.transformableText ?? text
            MacOS26TextPreviewView(
                text: full, tokens: full == text ? tokens : CodeHighlighter.tokens(in: full), monospaced: true)
        case .color(let code, let rgb):
            VStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(red: rgb.red, green: rgb.green, blue: rgb.blue))
                Text(code)
                    .font(typography.plainText.font(.title3).monospaced())
            }
        case .link(let address):
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    MacOS26LinkPreviewView(address: address, size: .large)
                    Text(address)
                        .font(typography.plainText.font(.callout).monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        case .storedImage(let reference):
            MacOS26ImageThumbnailView(id: card.id, content: .stored(reference))
        case .image(let data):
            MacOS26ImageThumbnailView(id: card.id, data: data)
        case .files(let names, let overflow, let thumbnailPath):
            ScrollView {
                MacOS26FilePreviewView(names: names, overflow: overflow, thumbnailPath: thumbnailPath, size: .large)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
}

@available(macOS 26, *)
struct MacOS26HeaderContentLayout: Layout {
    var maximumHeaderFraction: CGFloat = 0.45
    var spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let idealHeader = subviews[0].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        let headerHeight = min(idealHeader.height, bounds.height * maximumHeaderFraction)
        subviews[0].place(
            at: bounds.origin, anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: headerHeight))

        let contentStart = min(bounds.height, headerHeight + spacing)
        subviews[1].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + contentStart), anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height - contentStart))
    }
}

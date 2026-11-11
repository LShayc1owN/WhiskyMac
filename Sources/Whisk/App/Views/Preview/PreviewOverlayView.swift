// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

/// Space-bar preview: the selected card, live-updated as the selection
/// moves. The window decides the size — a short screen hands it less
/// room — and the content adapts to whatever it gets.
struct PreviewOverlayView: View {
    @ObservedObject var store: HistoryViewStateStore

    var actions: PanelActions? = nil

    var body: some View {
        Group {
            if store.isProtected {
                PrivacyPlaceholder()
            } else if let card = store.previewCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        if let icon = SourceAppStyle.resolve(bundleID: card.sourceBundleID).icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 20, height: 20)
                                .accessibilityHidden(true)
                        }
                        Text(card.sourceLabel)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                        Text("\(card.kindLabel) · \(card.timeLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Group {
                        if let source = store.previewItems.first, source.splitGroup != nil {
                            SplitGroupPreview(source: source)
                        } else if store.previewItems.contains(where: { $0.rtf != nil }) {
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
        .liquidGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), cornerRadius: 24)
    }

    private var richVersions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.pendingAction != nil {
                Text(localized("Choose a format to continue"))
            }
            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(store.previewItems.prefix(store.expandedVersions ? store.previewItems.count : 2)) {
                            item in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.source?.name ?? localized("Rich text"))
                                    .font(.caption).foregroundStyle(.secondary)
                                RichTextPreviewPane(item: item)
                                if let actions {
                                    Button(store.pendingAction?.label ?? localized("Copy")) {
                                        store.chooseVersion(item.id, actions: actions)
                                    }
                                }
                            }
                            .frame(
                                width: min(340, max(240, (geometry.size.width - 16) / 2)),
                                height: max(100, geometry.size.height))
                        }
                    }
                }
            }
            if store.previewItems.count > 2 {
                Button(store.expandedVersions ? localized("Show fewer formats") : "+\(store.previewItems.count - 2)") {
                    store.expandedVersions.toggle()
                }
            }
        }
    }

    @ViewBuilder private func content(for card: CardViewState) -> some View {
        switch card.preview {
        case .text(let value):
            ScrollView {
                Text(store.previewItems.first?.payload.transformableText ?? value)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        case .code(let text, let tokens):
            ScrollView([.vertical, .horizontal]) {
                let full = store.previewItems.first?.payload.transformableText ?? text
                CodeTextView(
                    text: full, tokens: full == text ? tokens : CodeHighlighter.tokens(in: full), lineLimit: nil
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        case .color(let code, let rgb):
            VStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(red: rgb.red, green: rgb.green, blue: rgb.blue))
                Text(code)
                    .font(.title3.monospaced())
            }
        case .link(let address):
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    LinkPreviewView(address: address, size: .large)
                    Text(address)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        case .image(let data):
            if let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(localized("Image"))
            }
        case .files(let names, let overflow, let thumbnailPath):
            ScrollView {
                FilePreviewView(names: names, overflow: overflow, thumbnailPath: thumbnailPath, size: .large)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
}

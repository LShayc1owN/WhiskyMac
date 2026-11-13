// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import ImageIO
import SwiftUI

/// Equatable on the view state alone: the action closures never compare
/// equal, and without this every card would rebuild (and visibly flash) on
/// each selection move.
struct ItemCardView: View, Equatable {
    let card: CardViewState
    /// Every menu entry, shortcut and gesture of the card lands here.
    let actions: PanelActions
    var keyBindings: KeyBindingsStore? = nil
    /// One cursor at a time: while vim's search mode holds it, the ring
    /// stays off even though the selection survives underneath.
    var showsSelection = true
    /// The card's side before the selection zoom.
    var side: CGFloat = 200
    var interactions = InteractionBindings()
    var canExport: () -> Bool = { true }
    var onInteraction: ((CardAction) -> Void)? = nil
    var onHoverPreview: (() -> Void)? = nil
    var onHoverChanged: ((Bool) -> Void)? = nil
    @State private var showingMenu = false
    @State private var editingPin = false
    @State private var hoverTask: Task<Void, Never>?

    private func perform(_ action: CardAction) {
        guard canExport() else { return }
        if action == .menu {
            showingMenu = true
        } else if let onInteraction {
            showingMenu = false; onInteraction(action)
        } else if action == .paste {
            actions.select(card.id)
        } else if action == .copy {
            actions.copy(card.id)
        } else if action == .split, !card.contentHidden, !card.isSplitGroup, card.transformable {
            actions.split(card.id)
        }
    }

    static func == (lhs: ItemCardView, rhs: ItemCardView) -> Bool {
        lhs.card == rhs.card && lhs.showsSelection == rhs.showsSelection && lhs.side == rhs.side
            && lhs.interactions == rhs.interactions
    }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

    private var zoomedSide: CGFloat {
        side * HistoryViewStateStore.selectionZoom
    }

    private var selectedSide: CGFloat {
        card.isSelected ? zoomedSide : side
    }

    private var cardAccessibilityValue: String {
        guard card.isSplitGroup else { return card.accessibilityValue }
        return [card.accessibilityValue, localized("Card group"), localized("\(card.splitCount) items")]
            .joined(separator: ", ")
    }

    private var backdrop: some View {
        Color.clear
            .frame(width: selectedSide, height: selectedSide)
            .frostedSurface(
                in: Self.shape,
                cornerRadius: 18,
                tint: SourceAppStyle.resolve(bundleID: card.sourceBundleID)
                    .surfaceTint(dark: scheme == .dark)
            )
            .background {
                if card.isSplitGroup { CardGroupBackdrop() }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: card.isSelected)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !card.pinnedMetadata.note.isEmpty {
                Text(card.pinnedMetadata.note).font(.headline).lineLimit(2).padding(.horizontal, 14)
            }
            PinTagDots(tags: card.pinnedMetadata.tags).padding(.horizontal, 14)
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        // The selection zoom needs both mechanisms at once: scaleEffect
        // grows the SwiftUI-drawn content (text, icons, ring), while the
        // frosted backdrop — an AppKit view that ignores transforms —
        // grows geometrically to the same size. Same factor, same curve:
        // they track. The outer slot stays constant so neighbors never
        // shift.
        .frame(width: side, height: side)
        .overlay(selectionRing)
        .scaleEffect(card.isSelected ? HistoryViewStateStore.selectionZoom : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: card.isSelected)
        .frame(width: zoomedSide, height: zoomedSide)
        .background { backdrop }
        .contentShape(Rectangle())
        .grabPointer()
        .onDrag {
            guard !card.contentHidden, !card.isSplitGroup, canExport(), card.variantIDs.count <= 1 else {
                return NSItemProvider()
            }
            actions.dragBegan()
            return Self.dragProvider(for: card.dragPayload)
        }
        .gesture(
            TapGesture(count: 2).exclusively(before: TapGesture(count: 1)).onEnded { value in
                switch value {
                case .first: perform(interactions.doubleClick)
                case .second: perform(interactions.singleClick)
                }
            }
        )
        .background(CardRightClick { perform(interactions.rightClick) })
        .onHover { inside in
            onHoverChanged?(inside)
            hoverTask?.cancel()
            if inside, interactions.hover == .preview {
                hoverTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(interactions.hoverDelay))
                    guard !Task.isCancelled else { return }
                    if let onHoverPreview { onHoverPreview() } else { perform(.preview) }
                }
            }
        }
        .onAppear { Self.prewarm([card]) }
        .onChange(of: editingPin) { _, value in actions.metadataEditorChanged(value) }
        .onChange(of: showingMenu) { _, shown in
            actions.cardMenuChanged(shown)
            if !shown { editingPin = false }
        }
        .onChange(of: interactions) { _, _ in hoverTask?.cancel() }
        .onDisappear {
            actions.metadataEditorChanged(false)
            actions.cardMenuChanged(false)
            hoverTask?.cancel()
            onHoverChanged?(false)
        }
        .popover(isPresented: $showingMenu) {
            VStack(alignment: .leading, spacing: 10) {
                if !canExport() {
                    PrivacyPlaceholder().padding(12)
                } else if editingPin {
                    PinnedItemEditor(value: card.pinnedMetadata) { value in
                        actions.updatePinnedMetadata(card.id, value)
                        showingMenu = false
                    }.padding(12)
                } else {
                    CardActionMenu(
                        card: card, actions: actions, keyBindings: keyBindings,
                        perform: perform, editPinnedItem: { editingPin = true },
                        dismiss: { showingMenu = false }
                    )
                }
            }.background(CardActionPopoverLayer())
        }
        // Continuous, not enter/exit: after a keyboard scroll parks a card
        // under the pointer, the very first real movement inside it must
        // reclaim the selection — without crossing a card edge first.
        .onContinuousHover { phase in
            if case .active = phase, MouseActivity.movedRecently {
                actions.highlight(card.id)
            }
        }

        // One VoiceOver element per card: the presenter's label and value
        // say it all, the icons and texts inside are decorative.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilityLabel)
        .accessibilityValue(cardAccessibilityValue)
        .accessibilityHint(localized("Uses the configured card action"))
        .accessibilityAddTraits(card.isSelected && showsSelection ? [.isButton, .isSelected] : [.isButton])
        .accessibilityAction(.default) { perform(interactions.singleClick) }
        .accessibilityAction(named: Text(localized("Actions"))) { perform(.menu) }
        .accessibilityAction(named: Text(localized("Copy"))) { perform(.copy) }
        .accessibilityAction(named: Text(card.isPinned ? localized("Unpin") : localized("Pin"))) {
            actions.togglePin(card.id)
        }
        .accessibilityAction(named: Text(localized("Delete"))) { actions.delete(card.id) }
    }

    @ViewBuilder private var selectionRing: some View {
        if card.isSelected && showsSelection {
            Self.shape
                .strokeBorder(Color.matcha, lineWidth: 2)
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            if let icon = SourceAppStyle.resolve(bundleID: card.sourceBundleID).icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            MarqueeText(card.sourceLabel, font: .system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
                .help(
                    card.sourceKey == "origin:handoff-marker"
                        ? localized("A Handoff marker was observed. The device and source app are unknown.")
                        : localized("Application observed on this Mac at capture time; source is not verified."))
            if card.isSplitGroup { CardGroupIndicator(count: card.splitCount) }
            if card.variantIDs.count > 1 {
                Text("\(card.variantIDs.count)").font(.caption.monospacedDigit())
            }
            Image(systemName: "ellipsis.circle")
                .beButton { showingMenu = true }
                .buttonStyle(.plain)
                .fixedSize()
                .help(localized("Actions"))
            if let position = card.stackPosition {
                HStack(spacing: 3) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 8))
                    Text("\(position)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                }
                .foregroundStyle(Color.matcha)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.matcha.opacity(0.18)))
            }
            if card.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder private var preview: some View {
        if card.contentHidden {
            HiddenPinnedContent(card: card).padding(.horizontal, 14)
        } else if let rtf = card.rtf, case .text(let fallback) = card.dragPayload {
            RichTextCardView(data: rtf, fallback: fallback, matches: card.matches)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .mask(bottomFade)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            switch card.preview {
            case .text(let value):
                // A plain Text unless there is something to underline: the
                // attributed path costs more and runs only under a live query.
                Group {
                    if card.matches.isEmpty {
                        Text(value)
                    } else {
                        Text(CodeTextView.highlighted(value, matches: card.matches))
                    }
                }
                .font(.system(size: 12))
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .mask(bottomFade)
            case .color(let code, let rgb):
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(red: rgb.red, green: rgb.green, blue: rgb.blue).opacity(rgb.alpha))
                        .frame(height: 86)
                    Text(code)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
            case .code(let text, let tokens):
                CodeTextView(text: text, tokens: tokens, lineLimit: nil, matches: card.matches)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .mask(bottomFade)
            case .link(let address):
                LinkPreviewView(address: address, size: .card)
                    .padding(.horizontal, 14)
            case .image(let data):
                if let image = Self.decodedImage(for: card.id, data: data) {
                    // Color.clear takes exactly the offered space; the filling
                    // image lives in an overlay so its ideal size can never
                    // inflate the layout, and the clip keeps it inside.
                    Color.clear
                        .overlay(
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(.horizontal, 14)
                } else {
                    Text(localized("Image"))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                }
            case .files(let names, let overflow, let thumbnailPath):
                FilePreviewView(names: names, overflow: overflow, thumbnailPath: thumbnailPath, size: .card)
                    .padding(.horizontal, 14)
            }
        }
    }

    /// Overflowing text melts into the card's bottom edge instead of being
    /// chopped: full opacity everywhere but the last stretch, which fades
    /// to nothing. Short content never reaches the fade zone.
    private var bottomFade: some View {
        VStack(spacing: 0) {
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 26)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(card.timeLabel)
            Spacer()
            if let detail = card.detailLabel {
                Text(detail)
                Text("·")
            }
            Image(systemName: card.kindSymbol)
                .accessibilityLabel(card.kindLabel)
                .help(card.kindLabel)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    /// Cards can be dragged straight into other applications; the presenter
    /// decided what travels, this only wraps it for the drag session.
    static func dragProvider(for payload: DragPayload) -> NSItemProvider {
        switch payload {
        case .text(let value):
            return NSItemProvider(object: value as NSString)
        case .link(let url):
            return NSItemProvider(object: url as NSURL)
        case .image(let data):
            if let image = NSImage(data: data) {
                return NSItemProvider(object: image)
            }
            return NSItemProvider()
        case .files(let paths):
            // One provider per drag session: the first file travels.
            if let path = paths.first,
                let provider = NSItemProvider(contentsOf: URL(fileURLWithPath: path))
            {
                return provider
            }
            return NSItemProvider()
        }
    }

    // Decoding image bytes during a body evaluation is visible as a flash,
    // so each card decodes once into a card-sized thumbnail — and the rail
    // prewarms the whole batch off the main thread, so a card entering the
    // scroll window arrives already decoded.
    private static let imageCache: NSCache<NSUUID, NSImage> = {
        let cache = NSCache<NSUUID, NSImage>()
        // A few screens' worth of thumbnails; the rest decode again on demand.
        cache.countLimit = 512
        return cache
    }()
    private static let thumbnailMaxDimension = 480
    private static let prewarmQueue = DispatchQueue(label: "whisk.card-prewarm", qos: .utility)

    /// Decodes the thumbnails of every image card in the background, ahead
    /// of the card being mounted.
    static func prewarm(_ cards: [CardViewState]) {
        for card in cards where !card.contentHidden {
            guard case .image(let data) = card.preview else { continue }
            let key = card.id as NSUUID
            guard imageCache.object(forKey: key) == nil else { continue }
            prewarmQueue.async {
                guard imageCache.object(forKey: key) == nil,
                    let thumbnail = thumbnail(from: data)
                else { return }
                imageCache.setObject(thumbnail, forKey: key)
            }
        }
    }

    private static func decodedImage(for id: UUID, data: Data) -> NSImage? {
        let key = id as NSUUID
        if let cached = imageCache.object(forKey: key) {
            return cached
        }
        guard let thumbnail = thumbnail(from: data) else { return nil }
        imageCache.setObject(thumbnail, forKey: key)
        return thumbnail
    }

    private static func thumbnail(from data: Data) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxDimension,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}

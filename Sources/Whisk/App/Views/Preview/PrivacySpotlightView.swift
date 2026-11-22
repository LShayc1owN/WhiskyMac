// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

/// Protected cards publish only identities. A single hovered item is fetched
/// after the dwell; Canvas emits no content accessibility descendants.
struct PrivacySpotlightView: View {
    private final class Viewport {
        var geometry: ScrollGeometry?
        var sourceRange: Range<Int>?
    }
    @ObservedObject var store: HistoryViewStateStore
    var actions: PanelActions? = nil
    @State private var appScope = FilterAppScope(visibleSourceKeys: [])
    @State private var viewport = Viewport()
    @StateObject private var imageThumbnails = ImageThumbnailStore(byteLimit: 0)
    @Environment(\.layoutDirection) private var layoutDirection
    var body: some View {
        let ids = store.protectedCardIDs
        let filters = store.protectedFilters
        VStack(spacing: PanelLayout.contentSpacing) {
            Label(
                store.allowsSpotlight && store.privacyInteractions.hover == .preview
                    ? localized("Manual privacy: hover to reveal a small area")
                    : localized("Content hidden by Privacy Mode"), systemImage: "eye.slash"
            )
            .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                if store.privacyAllowsSearch {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                        TextField(
                            localized("Search clipboard history"),
                            text: Binding(
                                get: { store.protectedQuery }, set: { store.searchWhileProtected($0) })
                        )
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(height: 36)
                    .background(ClipboardSearchBackground())
                    .frame(maxWidth: 480)
                } else {
                    Spacer(minLength: 0)
                }
                HistoryToolbarActions(store: store, actions: actions)
            }
            .frame(maxWidth: 660)
            .padding(.horizontal, 16)
            if !filters.isEmpty {
                FilterBarView(
                    filters: filters, tagScale: store.filterTagScale,
                    appScope: appScope, cursorSuppressed: true,
                    appTrigger: store.appFilterTrigger, hoverEnabled: store.panelVisible && !store.cardMenuOpen,
                    isPanelVisible: store.panelVisible,
                    onSelectApp: { if !store.cardMenuOpen { store.filterWhileProtected(.selectApp($0)) } },
                    onSelectKind: { if !store.cardMenuOpen { store.filterWhileProtected(.selectKind($0)) } },
                    onToggleApp: { store.filterWhileProtected(.toggleApp($0)) },
                    onToggleKind: { store.filterWhileProtected(.toggleKind($0)) },
                    onFocusApp: { _ in }, onFocusKind: { _ in })
            }
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                LazyHStack(spacing: HistoryViewStateStore.cardGap) {
                    ForEach(ids, id: \.self) { id in
                        VStack(spacing: 6) {
                            if let source = store.protectedSourceLabel(for: id) {
                                Text(source).font(.caption).lineLimit(1)
                                    .frame(width: store.cardSide, alignment: .leading)
                            }
                            SpotlightCard(store: store, id: id, imageThumbnails: imageThumbnails)
                        }
                        .frame(height: store.cardSide + (store.privacyShowsSourceApps ? 26 : 0), alignment: .bottom)
                    }
                }
                .padding(.horizontal, PanelLayout.contentMargin)
                .padding(.bottom, PanelLayout.railVerticalPadding)
            }
            .onScrollGeometryChange(for: ScrollGeometry.self) {
                $0
            } action: { _, geometry in
                viewport.geometry = geometry
                updateAppScope()
            }
            .onReceive(store.$state) { _ in updateAppScope(refresh: true) }
            .onChange(of: store.privacyAllowsAppFiltering) { _, _ in updateAppScope(refresh: true) }
            .onChange(of: store.cardSide) { _, _ in updateAppScope() }
            .frame(
                minHeight: 0, idealHeight: store.cardSide + (store.privacyShowsSourceApps ? 34 : 8),
                maxHeight: store.cardSide + (store.privacyShowsSourceApps ? 34 : 8))
            if store.privacyAllowsSearch, ids.isEmpty {
                Text(localized("No matches")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, PanelLayout.bottomPadding)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localized("Content hidden by Privacy Mode"))
    }

    private func updateAppScope(refresh: Bool = false) {
        guard let geometry = viewport.geometry else { return }
        let start =
            geometry.contentOffset.x - PanelLayout.contentMargin
            - (layoutDirection == .rightToLeft ? geometry.contentInsets.leading + geometry.contentInsets.trailing : 0)
        let range = FilterAppScope.visibleRange(
            count: store.protectedCardCount, side: store.cardSide,
            stride: store.cardSide + HistoryViewStateStore.cardGap,
            start: start, width: geometry.containerSize.width)
        guard refresh || viewport.sourceRange != range else { return }
        viewport.sourceRange = range
        appScope.update(store.protectedSourceKeys(in: range))
    }
}

private struct SpotlightCard: View {
    @ObservedObject var store: HistoryViewStateStore
    let id: UUID
    @State private var point: CGPoint?
    @State private var payload: Payload?
    @StateObject private var imageLoader = ImageThumbnailLoader()
    let imageThumbnails: ImageThumbnailStore
    @State private var task: Task<Void, Never>?
    @State private var showingMenu = false
    @State private var pendingExport: CardAction?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var thumbnail: NSImage? {
        guard let content = imageContent(payload) else { return nil }
        return imageLoader.image(for: ImageThumbnailRequest(id: id, content: content, maxPixelSize: 512))
    }

    private func imageContent(_ value: Payload?) -> BinaryContent? {
        switch value {
        case .image(let data): return .inline(data)
        case .storedImage(let reference): return .stored(reference)
        default: return nil
        }
    }

    private func prepareImage(_ value: Payload?) {
        imageLoader.cancel()
        guard let content = imageContent(value), content.byteCount <= 8 * 1024 * 1024 else { return }
        imageLoader.load(
            ImageThumbnailRequest(id: id, content: content, maxPixelSize: 512), store: imageThumbnails,
            priority: .veryHigh)
    }

    var body: some View {
        SpotlightCardSurface(
            side: store.cardSide, payload: payload, point: point, thumbnail: thumbnail, spotlight: store.spotlight
        )
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                point = location
                guard store.privacyInteractions.hover == .preview, task == nil, !showingMenu,
                    !store.cardMenuOpen
                else { return }
                task = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(store.privacyInteractions.hoverDelay))
                    guard !Task.isCancelled, point != nil, !store.cardMenuOpen else { return }
                    let value = store.spotlightPayload(for: id)
                    prepareImage(value)
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { payload = value }
                }
            case .ended: clear()
            }
        }
        .gesture(
            TapGesture(count: 2).exclusively(before: TapGesture(count: 1)).onEnded { value in
                switch value {
                case .first: perform(store.privacyInteractions.doubleClick)
                case .second: perform(store.privacyInteractions.singleClick)
                }
            }
        )
        .background(CardRightClick { perform(store.privacyInteractions.rightClick) })
        .overlay(alignment: .topTrailing) {
            Image(systemName: "ellipsis")
                .padding(10)
                .beButton { perform(.menu) }
                .buttonStyle(.plain).accessibilityLabel(localized("Actions"))
        }
        .cardActionPopover(isPresented: $showingMenu) {
            VStack(alignment: .leading, spacing: 10) {
                if let action = pendingExport {
                    Text(localized("Choose a format to continue"))
                    IndexedForEach(store.protectedVersions(for: id), id: \.self) { index, version in
                        Button(formatLabel(index + 1)) {
                            showingMenu = false
                            store.exportWhileProtected(cardID: id, versionID: version, action: action)
                        }
                    }
                } else {
                    Button(CardAction.copy.label) { perform(.copy) }
                    Button(CardAction.paste.label) { perform(.paste) }
                    Button(localized("Reveal a small area")) { perform(.preview) }.disabled(!store.allowsSpotlight)
                }
            }.padding()
        }
        .onDisappear {
            clear(); showingMenu = false; pendingExport = nil
        }
        .onChange(of: store.privacyInteractions) { _, _ in
            clear(); showingMenu = false; pendingExport = nil
        }
        .onChange(of: store.cardMenuOpen) { _, open in
            if open { task?.cancel(); task = nil }
        }
        .onChange(of: store.allowsSpotlight) { _, _ in clear() }
        .onChange(of: store.panelVisible) { _, visible in
            if !visible { clear(); showingMenu = false; pendingExport = nil }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localized("Protected clipboard item"))
        .accessibilityAction(.default) { perform(store.privacyInteractions.singleClick) }
        .accessibilityAction(named: Text(localized("Actions"))) { perform(.menu) }
    }

    private func formatLabel(_ number: Int) -> String { localized("Format \(number)") }

    private func perform(_ action: CardAction) {
        guard store.isProtected, store.panelVisible, store.containsProtectedCard(id) else { return }
        task?.cancel(); task = nil
        switch action {
        case .copy, .paste:
            payload = nil; imageLoader.cancel()
            if store.protectedVersions(for: id).count > 1 {
                pendingExport = action; showingMenu = true
            } else {
                showingMenu = false
                store.exportWhileProtected(cardID: id, versionID: id, action: action)
            }
        case .preview:
            showingMenu = false
            if payload != nil { payload = nil; imageLoader.cancel(); return }
            let value = store.protectedRevealPayload(for: id)
            prepareImage(value)
            if point == nil { point = CGPoint(x: store.cardSide / 2, y: store.cardSide / 2) }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { payload = value }
        case .menu:
            payload = nil; imageLoader.cancel()
            pendingExport = nil; showingMenu = true
        case .none, .edit, .split: break
        }
    }

    private func clear() {
        task?.cancel()
        task = nil
        payload = nil
        imageLoader.cancel()
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
    var spotlight = SpotlightPreferences()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(.regularMaterial)
            .overlay {
                if scheme == .light {
                    let shape = RoundedRectangle(cornerRadius: 18)
                    shape.fill(.white.opacity(0.72))
                    shape.strokeBorder(.primary.opacity(0.11), lineWidth: 0.5)
                }
            }
            .frame(width: side, height: side)
            .clipboardShadow(in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                ZStack {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                    if let point, let payload {
                        SpotlightCanvas(payload: payload, point: point, thumbnail: thumbnail, spotlight: spotlight)
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
    var spotlight = SpotlightPreferences()

    var body: some View {
        Canvas { context, size in
            // Clip before drawing: no full unmasked preview surface.
            context.clip(to: Path(ellipseIn: SpotlightGeometry.revealBounds(around: point, spotlight: spotlight)))
            context.fill(
                Path(CGRect(origin: .zero, size: size)), with: .color(Color(nsColor: .windowBackgroundColor)))
            switch payload {
            case .text(let text): draw(text, in: &context, size: size)
            case .link(let url): draw(url.absoluteString, in: &context, size: size)
            case .fileReferences(let paths):
                draw(
                    paths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: "\n"),
                    in: &context, size: size)
            case .image, .storedImage:
                if let image = thumbnail {
                    context.draw(
                        Image(nsImage: image), in: SpotlightGeometry.imageRect(imageSize: image.size, canvasSize: size))
                }
            }
        }
        .mask {
            Group {
                if spotlight.blurRadius == 0 {
                    Circle().fill(.white)
                } else {
                    RadialGradient(
                        colors: [.white, .clear], center: .center,
                        startRadius: spotlight.innerRadius, endRadius: spotlight.outerRadius)
                }
            }
            .frame(width: spotlight.diameter, height: spotlight.diameter)
            .position(point)
        }
    }

    static func thumbnail(_ data: Data) -> NSImage? {
        guard data.count <= 8 * 1024 * 1024,
            let image = ImageThumbnailDecoder.decode(data, maxPixelSize: 512)
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
    static func revealBounds(around point: CGPoint, spotlight: SpotlightPreferences = SpotlightPreferences()) -> CGRect
    {
        let outerRadius = spotlight.outerRadius
        return
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

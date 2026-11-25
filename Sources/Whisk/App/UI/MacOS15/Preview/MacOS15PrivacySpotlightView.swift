// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

/// Protected cards publish only identities. A single hovered item is fetched
/// after the dwell; Canvas emits no content accessibility descendants.
struct MacOS15PrivacySpotlightView: View {
    @Environment(\.interfaceTypography) private var typography

    @ObservedObject var store: HistoryViewStateStore
    var actions: PanelActions? = nil
    @State private var appScope = FilterAppScope(visibleSourceKeys: [])
    @State private var scrolling = CardRailScrollState()
    @State private var position = ScrollPosition()
    @State private var revealedCardID: UUID?
    @State private var hasRevealedContent = false
    @StateObject private var imageThumbnails = ImageThumbnailStore(byteLimit: 0)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let ids = store.protectedCardIDs
        let filters = store.protectedFilters
        let sourceHeight = typography.usesLargeLayout ? typography.lineHeight(11) * 2 + 6 : typography.room(26)
        let cardHeight = store.cardSide + (store.privacyShowsSourceApps ? sourceHeight : 0)
        let railHeight = cardHeight + MacOS15PanelLayout.railVerticalPadding
        let returnToLatest = MacOS15ReturnToLatestButton {
            scrolling.returnToLatest(position: $position, reduceMotion: reduceMotion)
        }
        .disabled(ids.isEmpty)
        let isUnlocked = store.panelVisible && store.allowsSpotlight && hasRevealedContent
        MacOS15HistoryPanelSections(minimumContentHeight: min(railHeight, typography.room(100))) {
            VStack(spacing: MacOS15PanelLayout.contentSpacing) {
                Label {
                    Text(localized("Privacy Mode is on"))
                } icon: {
                    Image(systemName: isUnlocked ? "lock.open.fill" : "lock.fill")
                        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                        .frame(width: typography.room(16))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isUnlocked)
                        .accessibilityHidden(true)
                }
                .font(typography.font(.caption))
                .foregroundStyle(.secondary)
                if store.privacyAllowsSearch {
                    let prompt = ClipboardSearchPrompt(count: ids.count, typography: typography)
                    let metrics = MacOS15ClipboardSearchMetrics(
                        prompt: prompt, expanded: !store.protectedQuery.isEmpty)
                    MacOS15ClipboardSearchToolbarLayout(field: metrics) {
                        HStack(spacing: 10) {
                            returnToLatest
                            searchField(prompt: prompt, width: metrics.preferredWidth)
                        }
                        HStack { MacOS15HistoryToolbarActions(store: store, actions: actions) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                } else {
                    HStack(spacing: 10) {
                        Spacer(minLength: 0)
                        returnToLatest
                        MacOS15HistoryToolbarActions(store: store, actions: actions)
                    }
                    .frame(maxWidth: 704)
                    .padding(.horizontal, 16)
                }
                if !filters.isEmpty {
                    MacOS15FilterBarView(
                        filters: filters, tagScale: store.filterTagScale,
                        appScope: appScope, cursorSuppressed: true,
                        appTrigger: store.appFilterTrigger, hoverEnabled: store.panelVisible && !store.cardMenuOpen,
                        isPanelVisible: store.panelVisible,
                        onSelectApp: { if !store.cardMenuOpen { store.filterWhileProtected(.selectApp($0)) } },
                        onSelectKind: { if !store.cardMenuOpen { store.filterWhileProtected(.selectKind($0)) } },
                        onToggleApp: { store.filterWhileProtected(.toggleApp($0)) },
                        onToggleKind: { store.filterWhileProtected(.toggleKind($0)) },
                        onFocusApp: { _ in }, onFocusKind: { _ in })
                } else if store.reservesHiddenFilterRow {
                    let tags = MacOS15FilterTagMetrics(scale: store.filterTagScale, typography: typography)
                    Color.clear.frame(height: tags.totalRowHeight)
                        .accessibilityHidden(true)
                }
            }
        } content: {
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                LazyHStack(spacing: HistoryViewStateStore.cardGap) {
                    ForEach(ids, id: \.self) { id in
                        VStack(spacing: 6) {
                            if let source = store.protectedSourceLabel(for: id) {
                                Text(source)
                                    .font(typography.font(.caption))
                                    .lineLimit(typography.usesLargeLayout ? 2 : 1)
                                    .frame(width: store.cardSide, alignment: .leading)
                                    .help(source)
                            }
                            MacOS15SpotlightCard(
                                store: store, id: id, revealedCardID: $revealedCardID, imageThumbnails: imageThumbnails)
                        }
                        .frame(height: cardHeight, alignment: .bottom)
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, MacOS15PanelLayout.contentMargin)
                .padding(.bottom, MacOS15PanelLayout.railVerticalPadding)
            }
            .scrollPosition($position)
            .onPreferenceChange(MacOS15SpotlightContentVisible.self) { hasRevealedContent = $0 }
            .onScrollGeometryChange(for: CardRailViewport.self) {
                CardRailViewport(
                    $0, count: store.protectedCardCount, side: store.cardSide,
                    stride: store.cardSide + HistoryViewStateStore.cardGap,
                    rtl: layoutDirection == .rightToLeft, leadingPadding: MacOS15PanelLayout.contentMargin)
            } action: { previous, next in
                let initial = scrolling.viewport == nil
                scrolling.update(next, position: $position, reduceMotion: reduceMotion)
                if initial || previous.visible != next.visible { updateAppScope() }
            }
            .onChange(of: store.panelVisible) { _, visible in
                if !visible { scrolling.cancelReturn() }
            }
            .onScrollPhaseChange { _, phase in
                if phase == .tracking || phase == .interacting { scrolling.cancelReturn() }
            }
            .onDisappear { scrolling.cancelReturn() }
            .onReceive(store.$state) { _ in updateAppScope() }
            .onChange(of: store.privacyAllowsAppFiltering) { _, _ in updateAppScope() }
            .frame(minHeight: 0, idealHeight: railHeight, maxHeight: railHeight)
            .overlay {
                if store.privacyAllowsSearch, ids.isEmpty {
                    Text(localized("No matches")).font(typography.font(.caption)).foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .animation(
                reduceMotion || !store.panelVisible ? nil : .easeInOut(duration: 0.18),
                value: store.historyVisibilityRevision)
        }
        .padding(.bottom, MacOS15PanelLayout.bottomPadding)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localized("Content hidden by Privacy Mode"))
    }

    private func searchField(prompt: ClipboardSearchPrompt, width: CGFloat) -> some View {
        HStack(spacing: 10) {
            MacOS15ClipboardSearchIcon()
            TextField(
                localized("Search clipboard history"),
                text: Binding(get: { store.protectedQuery }, set: { store.searchWhileProtected($0) }),
                prompt: Text(verbatim: "")
            )
            .textFieldStyle(.plain)
            .macOS15ClipboardSearchPrompt(
                prompt, accent: .macOS15ReadableAccent(in: scheme), isVisible: store.protectedQuery.isEmpty
            )
            .font(typography.font(size: ClipboardSearchPrompt.fontSize))
            .frame(minWidth: 0, idealWidth: width, maxWidth: width)
            MacOS15SearchMatchPicker(mode: store.searchMatchMode) { mode in
                store.selectSearchMatchMode(mode, whileProtected: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 36)
        .modifier(MacOS15ClipboardSearchSurface())
    }

    private func updateAppScope() {
        guard let visible = scrolling.viewport?.visible else { return }
        appScope.update(store.protectedSourceKeys(in: visible.clamped(to: 0..<store.protectedCardCount)))
    }
}

private struct MacOS15SpotlightCard: View {
    @ObservedObject var store: HistoryViewStateStore
    let id: UUID
    @Binding var revealedCardID: UUID?
    @State private var point: CGPoint?
    @State private var content: SpotlightExcerpt?
    @StateObject private var imageLoader = ImageThumbnailLoader()
    let imageThumbnails: ImageThumbnailStore
    @State private var task: Task<Void, Never>?
    @State private var showingMenu = false
    @State private var pendingExport: CardAction?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsFullCard: Bool { revealedCardID == id }
    private var canReveal: Bool { store.isProtected && store.allowsSpotlight && store.panelVisible }

    private func prepareReveal(_ payload: Payload?) -> SpotlightExcerpt? {
        imageLoader.cancel()
        guard let payload else { return nil }
        if let request = ImageThumbnailRequest.spotlight(id: id, payload: payload) {
            imageLoader.load(request, store: imageThumbnails, priority: .veryHigh)
        }
        return SpotlightExcerpt(payload)
    }

    var body: some View {
        MacOS15SpotlightCardSurface(
            side: store.cardSide, content: canReveal ? content : nil, point: point,
            thumbnail: canReveal ? imageLoader.image : nil, spotlight: store.spotlight, showsFullCard: showsFullCard
        )
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                guard canReveal, !showsFullCard else { return }
                point = location
                guard store.privacyInteractions.hover == .preview,
                    task == nil, !showingMenu, !store.cardMenuOpen
                else { return }
                task = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(store.privacyInteractions.hoverDelay))
                    guard !Task.isCancelled, point != nil, !store.cardMenuOpen else { return }
                    let value = store.spotlightPayload(for: id)
                    let excerpt = prepareReveal(value)
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { content = excerpt }
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
        .background(
            MacOS15CardRightClick {
                let action = store.privacyInteractions.rightClick
                if action == .preview { revealCard() } else { perform(action) }
            }
        )
        .overlay(alignment: .topTrailing) {
            Image(systemName: "ellipsis")
                .padding(10)
                .beButton { perform(.menu) }
                .buttonStyle(.plain).accessibilityLabel(localized("Actions"))
        }
        .macOS15CardActionPopover(isPresented: $showingMenu) {
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
                    Button(localized("Show card"), action: revealCard).disabled(!canReveal)
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
        .onChange(of: revealedCardID) { previous, current in
            if previous == id, current != id { clear() }
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

    private func revealCard() {
        if showsFullCard { clear(); return }
        clear()
        showingMenu = false
        guard let value = store.protectedRevealPayload(for: id) else { return }
        revealedCardID = id
        content = prepareReveal(value)
    }

    private func perform(_ action: CardAction) {
        guard store.isProtected, store.panelVisible, store.containsProtectedCard(id) else { return }
        task?.cancel(); task = nil
        switch action {
        case .copy, .paste:
            clear()
            if store.protectedVersions(for: id).count > 1 {
                pendingExport = action; showingMenu = true
            } else {
                showingMenu = false
                store.exportWhileProtected(cardID: id, versionID: id, action: action)
            }
        case .preview:
            showingMenu = false
            if content != nil { clear(); return }
            let value = store.protectedRevealPayload(for: id)
            let excerpt = prepareReveal(value)
            if point == nil { point = CGPoint(x: store.cardSide / 2, y: store.cardSide / 2) }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { content = excerpt }
        case .menu:
            clear()
            pendingExport = nil; showingMenu = true
        case .none, .edit, .split: break
        }
    }

    private func clear() {
        task?.cancel()
        task = nil
        content = nil
        if showsFullCard { revealedCardID = nil }
        imageLoader.cancel()
        point = nil
    }
}

private struct MacOS15SpotlightContentVisible: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// Revealing content only updates the overlay; the rail always measures the
/// same fixed card surface, including during its opacity transition.
struct MacOS15SpotlightCardSurface: View {

    let side: CGFloat
    var content: SpotlightExcerpt?
    var point: CGPoint?
    var thumbnail: NSImage?
    var spotlight = SpotlightPreferences()
    var showsFullCard = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(Material.ultraThin)
            .opacity(0.88)
            .overlay {
                if scheme == .light {
                    let shape = RoundedRectangle(cornerRadius: 18)
                    shape.fill(.white.opacity(0.72))
                    shape.strokeBorder(.primary.opacity(0.11), lineWidth: 0.5)
                }
            }
            .frame(width: side, height: side)
            .macOS15ClipboardShadow(in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                ZStack {
                    Image(systemName: "lock.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .opacity(0.7)
                    if let content, showsFullCard || point != nil {
                        MacOS15SpotlightCanvas(
                            content: content, point: showsFullCard ? nil : point, thumbnail: thumbnail,
                            spotlight: spotlight
                        )
                        .transition(.opacity)
                        .allowsHitTesting(false)
                        .preference(key: MacOS15SpotlightContentVisible.self, value: true)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))

    }
}

struct MacOS15SpotlightCanvas: View {

    let content: SpotlightExcerpt
    let point: CGPoint?
    var thumbnail: NSImage?
    var spotlight = SpotlightPreferences()

    var body: some View {
        MacOS15SpotlightDrawing(content: content, thumbnail: thumbnail)
            .equatable()
            .mask {
                if let point {
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
                } else {
                    Rectangle().fill(.white)
                }
            }
    }
}

private struct MacOS15SpotlightDrawing: View, Equatable {
    let content: SpotlightExcerpt
    let thumbnail: NSImage?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.content == rhs.content && lhs.thumbnail === rhs.thumbnail
    }

    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)), with: .color(Color(nsColor: .windowBackgroundColor)))
            switch content {
            case .text(let text): draw(text, in: &context, size: size)
            case .image:
                if let image = thumbnail {
                    context.draw(
                        Image(nsImage: image),
                        in: MacOS15SpotlightGeometry.imageRect(imageSize: image.size, canvasSize: size))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(_ text: String, in context: inout GraphicsContext, size: CGSize) {
        // Render a bounded card excerpt, not an RTF decoder, URL fetch or QL request.
        let resolved = context.resolve(
            Text(verbatim: text).font(.system(size: 14)).foregroundColor(.primary))
        let measured = resolved.measure(in: CGSize(width: max(1, size.width - 24), height: .greatestFiniteMagnitude))
        // Let long text extend below the card and clip it, rather than asking
        // the card's height to constrain the paragraph's layout.
        context.draw(resolved, in: CGRect(origin: CGPoint(x: 12, y: 12), size: measured))
    }

}

/// Geometry stays independent of reveal state and source image proportions.
enum MacOS15SpotlightGeometry {
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

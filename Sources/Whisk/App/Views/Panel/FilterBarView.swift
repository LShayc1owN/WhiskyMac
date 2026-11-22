// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

/// One chip row above the search field: All and the pinned toggle,
/// then independent origins, source applications and content
/// categories. Several chips can be active at once; the focused chip is
/// the keyboard cursor (↑/↓ reach the row, ←/→ move, Return toggles) and
/// hovering moves that same focus with the mouse.
struct FilterBarView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The viewport's width, so a row that fits can be stretched to it.
    @State private var rowWidth: CGFloat = 0
    /// Mouse focus remains in the controller for arrow navigation, but its
    /// outline must disappear on exit when filtering by click.
    @State private var pointerFocusedID: String?
    @Namespace private var viewportSpace
    var horizontalMargin: CGFloat = 16
    @State private var leadingOverflow: CGFloat = 0
    let filters: FilterBarViewState
    var tagScale: Double = GeneralSettingsStore.defaultFilterTagScale
    private var metrics: FilterTagMetrics { FilterTagMetrics(scale: tagScale) }
    @ObservedObject var appScope = FilterAppScope()
    /// One cursor at a time: vim's search mode swallows the chip focus.
    var cursorSuppressed = false
    var appTrigger = AppFilterTrigger.click
    var hoverEnabled = true
    var isPanelVisible = true
    var onSelectApp: (String) -> Void = { _ in }
    var onSelectKind: (String) -> Void = { _ in }
    let onToggleApp: (String) -> Void
    let onToggleKind: (String) -> Void
    let onFocusApp: (String) -> Void
    let onFocusKind: (String) -> Void

    private var appExpansionAnimation: Animation? {
        reduceMotion || !isPanelVisible ? nil : .easeInOut(duration: 0.22)
    }

    var body: some View {
        let collapsedApps = FilterAppScope.apps(filters.apps, visibleKeys: appScope.visibleSourceKeys, expanded: false)
        let displayedApps = appScope.isExpanded ? filters.apps : collapsedApps
        let hasExpansionControl = appScope.isExpanded || collapsedApps.count < filters.apps.count
        let firstFixedChip = filters.all.first ?? filters.pinned.first ?? filters.origins.first
        let firstAfterApps = displayedApps.first ?? filters.kinds.first ?? filters.tags.first
        let leadingChipID = firstFixedChip?.id ?? (hasExpansionControl ? nil : firstAfterApps?.id)
        let overflowChanged: (CGFloat) -> Void = { leadingOverflow = $0 }
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8 * metrics.scale) {
                    ForEach(filters.all) { chip in
                        ChipButton(
                            chip: chip, viewportWidth: rowWidth, viewportSpace: viewportSpace,
                            leadingOverflowChanged: chip.id == leadingChipID ? overflowChanged : nil,
                            isPanelVisible: isPanelVisible, focusVisible: !cursorSuppressed,
                            clickToFilter: appTrigger == .click, focusFromPointer: pointerFocusedID == chip.id,
                            onToggle: { onToggleKind(chip.id) },
                            onFocus: { focus(chip.id, perform: onFocusKind) },
                            onHoverSelect: appTrigger == .hover && hoverEnabled ? { onSelectKind(chip.id) } : nil
                        ) {
                            HStack(spacing: 5 * metrics.scale) {
                                chipIcon(chip.icon)
                                Text(chip.label)
                            }
                        }

                        .id(chip.id)
                    }
                    ForEach(filters.pinned) { chip in
                        ChipButton(
                            chip: chip,
                            viewportWidth: rowWidth, viewportSpace: viewportSpace,
                            leadingOverflowChanged: chip.id == leadingChipID ? overflowChanged : nil,
                            isPanelVisible: isPanelVisible,
                            focusVisible: !cursorSuppressed,
                            clickToFilter: appTrigger == .click, focusFromPointer: pointerFocusedID == chip.id,
                            onToggle: { onToggleKind(chip.id) },
                            onFocus: { focus(chip.id, perform: onFocusKind) },
                            onHoverSelect: appTrigger == .hover && hoverEnabled ? { onSelectKind(chip.id) } : nil
                        ) {
                            HStack(spacing: 5 * metrics.scale) {
                                chipIcon(chip.icon)
                                Text(chip.label)
                            }
                        }
                        .id(chip.id)
                    }
                    if !filters.pinned.isEmpty
                        && !(filters.origins.isEmpty && filters.apps.isEmpty && filters.kinds.isEmpty)
                    {
                        separator
                    }
                    ForEach(filters.origins) { chip in
                        ChipButton(
                            chip: chip, viewportWidth: rowWidth, viewportSpace: viewportSpace,
                            leadingOverflowChanged: chip.id == leadingChipID ? overflowChanged : nil,
                            isPanelVisible: isPanelVisible, focusVisible: !cursorSuppressed,
                            clickToFilter: appTrigger == .click, focusFromPointer: pointerFocusedID == chip.id,
                            onToggle: { onToggleKind(chip.id) },
                            onFocus: { focus(chip.id, perform: onFocusKind) },
                            onHoverSelect: appTrigger == .hover && hoverEnabled ? { onSelectKind(chip.id) } : nil
                        ) {
                            HStack(spacing: 5 * metrics.scale) {
                                chipIcon(chip.icon)
                                Text(chip.label)
                            }
                        }
                        .id(chip.id)
                    }
                    if hasExpansionControl {
                        HStack(spacing: 5 * metrics.scale) {
                            Text(appScope.isExpanded ? localized("Collapse apps") : localized("More apps"))
                                .contentTransition(.opacity)
                            Image(systemName: "chevron.right")
                                .font(.system(size: metrics.smallFontSize, weight: .semibold))
                                .rotationEffect(.degrees(appScope.isExpanded ? 180 : 0))
                                .accessibilityHidden(true)
                        }
                        .beButton {
                            withAnimation(appExpansionAnimation) {
                                appScope.isExpanded.toggle()
                            }
                        }
                        .buttonStyle(FilterChipStyle(isActive: false, isFocused: false))
                        .accessibilityValue(appScope.isExpanded ? localized("Expanded") : localized("Collapsed"))
                    }
                    ForEach(displayedApps) { chip in
                        let style = SourceAppStyle.resolve(bundleID: chip.sourceBundleID)
                        ChipButton(
                            chip: chip,
                            viewportWidth: rowWidth, viewportSpace: viewportSpace,
                            leadingOverflowChanged: chip.id == leadingChipID ? overflowChanged : nil,
                            isPanelVisible: isPanelVisible,
                            baseTint: style.filterTint(dark: scheme == .dark),
                            activeTint: Color.matcha.opacity(0.22),
                            focusVisible: !cursorSuppressed,
                            clickToFilter: appTrigger == .click, focusFromPointer: pointerFocusedID == chip.id,
                            onToggle: { onToggleApp(chip.id) },
                            onFocus: { focus(chip.id, perform: onFocusApp) },
                            onHoverSelect: appTrigger == .hover && hoverEnabled ? { onSelectApp(chip.id) } : nil
                        ) {
                            HStack(spacing: 5 * metrics.scale) {
                                if let icon = style.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 17 * metrics.scale, height: 17 * metrics.scale)
                                }
                                Text(chip.label)
                            }
                        }
                        .id(chip.id)
                        .transition(.opacity)
                    }
                    if !filters.apps.isEmpty && !filters.kinds.isEmpty {
                        separator
                    }
                    ForEach(filters.kinds + filters.tags) { chip in
                        ChipButton(
                            chip: chip,
                            viewportWidth: rowWidth, viewportSpace: viewportSpace,
                            leadingOverflowChanged: chip.id == leadingChipID ? overflowChanged : nil,
                            isPanelVisible: isPanelVisible,
                            focusVisible: !cursorSuppressed,
                            clickToFilter: appTrigger == .click, focusFromPointer: pointerFocusedID == chip.id,
                            onToggle: { onToggleKind(chip.id) },
                            onFocus: { focus(chip.id, perform: onFocusKind) },
                            onHoverSelect: appTrigger == .hover && hoverEnabled ? { onSelectKind(chip.id) } : nil
                        ) {
                            HStack(spacing: 5 * metrics.scale) {
                                if let tag = PinTagColor.allCases.first(where: { $0.filterKey == chip.id }) {
                                    Circle().fill(tag.color).frame(width: 9 * metrics.scale, height: 9 * metrics.scale)
                                } else {
                                    chipIcon(chip.icon)
                                }
                                Text(chip.label)
                            }
                        }
                        .id(chip.id)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .padding(.vertical, metrics.rowVerticalPadding)
                .frame(minWidth: max(0, rowWidth - 2 * horizontalMargin - leadingOverflow), alignment: .leading)
                // Keep insets inside the measured document: macOS 15's
                // scroll contentMargins can expand the viewport unevenly.
                .padding(.horizontal, horizontalMargin)
                .padding(.leading, leadingOverflow)
            }
            .scrollClipDisabled()
            .frame(height: metrics.totalRowHeight)
            .defaultScrollAnchor(.leading)
            .coordinateSpace(name: viewportSpace)
            .readSize { rowWidth = $0.width }
            .onChange(of: leadingChipID) { _, _ in leadingOverflow = 0 }
            .onChange(of: isPanelVisible) { _, _ in
                pointerFocusedID = nil
                appScope.isExpanded = false
                rewind(proxy)
            }
            .onChange(of: appScope.isExpanded) { _, expanded in
                if !expanded { rewind(proxy, animated: true) }
            }
            .onChange(of: filters.focusedChipID) { _, id in
                if id != pointerFocusedID { pointerFocusedID = nil }
                guard let id else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                    proxy.scrollTo(id)
                }
            }
        }
        .environment(\.filterTagScale, tagScale)
    }

    private func focus(_ id: String, perform: (String) -> Void) {
        if pointerFocusedID != id { pointerFocusedID = id }
        perform(id)
    }

    private func rewind(_ proxy: ScrollViewProxy, animated: Bool = false) {
        let animation = animated ? appExpansionAnimation : nil
        var transaction = Transaction(animation: animation)
        transaction.disablesAnimations = animation == nil
        withTransaction(transaction) {
            if let firstID = filters.all.first?.id ?? filters.pinned.first?.id ?? filters.origins.first?.id
                ?? FilterAppScope.apps(
                    filters.apps, visibleKeys: appScope.visibleSourceKeys, expanded: appScope.isExpanded
                ).first?.id
                ?? filters.kinds.first?.id ?? filters.tags.first?.id
            {
                proxy.scrollTo(firstID, anchor: .leading)
            }
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.25))
            .frame(width: 1, height: 16 * metrics.scale)
            .padding(.horizontal, 4 * metrics.scale)
            .accessibilityHidden(true)
    }

    @ViewBuilder private func chipIcon(_ icon: ChipIcon?) -> some View {
        switch icon {
        case .resource(let name, let fallback):
            if let image = CategoryIcons.image(named: name) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: 16 * metrics.scale, height: 16 * metrics.scale)
            } else {
                symbol(fallback)
            }
        case .symbol(let name):
            symbol(name)
        case nil:
            EmptyView()
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 12 * metrics.scale))
            .foregroundStyle(.secondary)
    }
}

/// Geometry publishes only boundary crossings, not every scroll offset.
struct FilterChipViewport: Equatable, Sendable {
    enum Region: Sendable { case unknown, preload, retain, outside }
    let region: Region
    let isVisible: Bool

    static let unknown = FilterChipViewport(region: .unknown, isVisible: false)

    static func measure(frame: CGRect, viewportWidth: CGFloat) -> FilterChipViewport {
        guard viewportWidth.isFinite, viewportWidth > 0, !frame.isNull,
            frame.minX.isFinite, frame.maxX.isFinite, frame.width > 0
        else { return .unknown }
        // Include the largest selection zoom without changing layout bounds.
        let bounds = frame.insetBy(dx: -frame.width * 0.03, dy: 0)
        func intersects(_ margin: CGFloat) -> Bool {
            bounds.maxX > -margin && bounds.minX < viewportWidth + margin
        }
        return FilterChipViewport(
            region: intersects(160) ? .preload : (intersects(240) ? .retain : .outside),
            isVisible: intersects(0))
    }

    func keepsGlass(previouslyMounted: Bool) -> Bool {
        switch region {
        case .preload: true
        case .retain: previouslyMounted
        case .unknown, .outside: false
        }
    }
}

/// One chip. Like the cards: hovering moves the shared keyboard focus onto
/// it, and focus or an active filter zooms it slightly.
private struct ChipButton<Label: View>: View {
    let chip: FilterChip
    let viewportWidth: CGFloat
    let viewportSpace: Namespace.ID
    var leadingOverflowChanged: ((CGFloat) -> Void)? = nil
    let isPanelVisible: Bool
    var baseTint: Color?
    var activeTint: Color = Color.matcha.opacity(0.18)
    var focusVisible = true
    var clickToFilter = true
    var focusFromPointer = false
    let onToggle: () -> Void
    let onFocus: () -> Void
    var onHoverSelect: (() -> Void)?
    @State private var hoverActivation = FilterHoverActivation()
    @State private var viewport = FilterChipViewport.unknown
    @State private var glassMounted = false
    @State private var isHovered = false
    @ViewBuilder let label: () -> Label
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isFocused: Bool {
        chip.isFocused && focusVisible && (!clickToFilter || !focusFromPointer || isHovered)
    }

    private var zoomed: Bool {
        isFocused || chip.isActive
    }

    private var canHover: Bool { isPanelVisible && viewport.isVisible && onHoverSelect != nil }

    var body: some View {
        label()
            .beButton {
                hoverActivation.cancel()
                onToggle()
            }
            .buttonStyle(
                FilterChipStyle(
                    isActive: chip.isActive, isFocused: isFocused,
                    showsBorder: !clickToFilter || isHovered || (isFocused && !focusFromPointer))
            )
            .accessibilityLabel(chip.accessibilityLabel)
            .accessibilityAddTraits(chip.isActive ? .isSelected : [])
            .linkPointer()
            .onGeometryChange(for: FilterChipViewport.self) { geometry in
                FilterChipViewport.measure(
                    frame: geometry.frame(in: .named(viewportSpace)), viewportWidth: viewportWidth)
            } action: { observation in
                hoverActivation.isEnabled = isPanelVisible && observation.isVisible && onHoverSelect != nil
                viewport = observation
                glassMounted = observation.keepsGlass(previouslyMounted: glassMounted)
            }
            .scaleEffect(zoomed ? 1.06 : 1)
            .onGeometryChange(for: CGFloat.self) { geometry in
                zoomed ? geometry.size.width * 0.03 : 0
            } action: { overflow in
                leadingOverflowChanged?(overflow)
            }
            // The frosted capsule is an AppKit view and ignores transforms, so
            // it grows geometrically in a measured background — oversize does
            // not push neighbors — while the content scales above it.
            .background {
                GeometryReader { proxy in
                    if isPanelVisible && glassMounted {
                        ClipboardMaterialSurface(
                            shape: Capsule(), material: .underWindowBackground,
                            tint: chip.isActive ? activeTint : baseTint ?? .clear,
                            castsCompactShadowInDarkMode: true
                        )
                        .frame(
                            width: proxy.size.width * (zoomed ? 1.06 : 1),
                            height: proxy.size.height * (zoomed ? 1.06 : 1)
                        )
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        .transition(.identity)
                    }
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isFocused)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: chip.isActive)
            .onHover { inside in
                isHovered = inside
                hoverActivation.cancel()
                hoverActivation.isEnabled = canHover
                if inside, canHover, let onHoverSelect, MouseActivity.movedRecently {
                    hoverActivation.enter(onHoverSelect)
                }
            }
            .onAppear {
                hoverActivation.isEnabled = canHover
            }
            .onDisappear {
                hoverActivation.isEnabled = false
                isHovered = false
            }
            .onChange(of: isPanelVisible) { _, visible in
                if !visible {
                    isHovered = false
                }
            }
            .onChange(of: canHover) { _, enabled in hoverActivation.isEnabled = enabled }
            .onContinuousHover { phase in
                if case .active = phase, isPanelVisible, viewport.isVisible, MouseActivity.movedRecently {
                    onFocus()
                }
            }
    }
}

private struct FilterChipStyle: ButtonStyle {
    @Environment(\.filterTagScale) private var tagScale
    @Environment(\.colorScheme) private var scheme
    let isActive: Bool
    let isFocused: Bool
    var showsBorder = true

    func makeBody(configuration: Configuration) -> some View {
        let metrics = FilterTagMetrics(scale: tagScale)
        return configuration.label
            .font(.system(size: metrics.fontSize, weight: isActive ? .semibold : .regular))
            .foregroundStyle(isActive ? Color.readableAccent(in: scheme) : .primary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, metrics.verticalPadding)
            .overlay(
                Capsule().strokeBorder(borderColor, lineWidth: isFocused ? 2 : 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }

    private var borderColor: Color {
        guard showsBorder else { return .clear }
        if isFocused {
            return .readableAccent(in: scheme)
        }
        if isActive {
            return Color.readableAccent(in: scheme).opacity(0.8)
        }
        return .clear
    }
}

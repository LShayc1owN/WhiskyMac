// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

/// One chip row above the search field: All and the pinned toggle,
/// then source applications and content
/// categories. Several chips can be active at once; the focused chip is
/// the keyboard cursor (↑/↓ reach the row, ←/→ move, Return toggles) and
/// hovering moves that same focus with the mouse.
struct FilterBarView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The viewport's width, so a row that fits can be stretched to it.
    @State private var rowWidth: CGFloat = 0
    @Namespace private var viewportSpace
    private static let horizontalMargin: CGFloat = 16
    let filters: FilterBarViewState
    /// One cursor at a time: vim's search mode swallows the chip focus.
    var cursorSuppressed = false
    var appTrigger = AppFilterTrigger.click
    var hoverEnabled = true
    var isPanelVisible = true
    var onSelectApp: (String) -> Void = { _ in }
    let onToggleApp: (String) -> Void
    let onToggleKind: (String) -> Void
    let onFocusApp: (String) -> Void
    let onFocusKind: (String) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filters.all) { chip in
                        ChipButton(
                            chip: chip, viewportWidth: rowWidth, viewportSpace: viewportSpace,
                            isPanelVisible: isPanelVisible, focusVisible: !cursorSuppressed,
                            onToggle: { onToggleKind(chip.id) }, onFocus: { onFocusKind(chip.id) }
                        ) {
                            HStack(spacing: 5) {
                                chipIcon(chip.icon)
                                Text(chip.label)
                            }
                        }
                        .id(chip.id)
                    }
                    ForEach(filters.pinned) { chip in
                        ChipButton(
                            chip: chip,
                            viewportWidth: rowWidth, viewportSpace: viewportSpace, isPanelVisible: isPanelVisible,
                            focusVisible: !cursorSuppressed,
                            onToggle: { onToggleKind(chip.id) },
                            onFocus: { onFocusKind(chip.id) }
                        ) {
                            HStack(spacing: 5) {
                                chipIcon(chip.icon)
                                Text(chip.label)
                            }
                        }
                        .id(chip.id)
                    }
                    if !filters.pinned.isEmpty && !(filters.apps.isEmpty && filters.kinds.isEmpty) {
                        separator
                    }
                    ForEach(filters.apps) { chip in
                        ChipButton(
                            chip: chip,
                            viewportWidth: rowWidth, viewportSpace: viewportSpace, isPanelVisible: isPanelVisible,
                            baseTint: SourceAppStyle.resolve(bundleID: chip.sourceBundleID)
                                .surfaceTint(dark: scheme == .dark),
                            focusVisible: !cursorSuppressed,
                            onToggle: { onToggleApp(chip.id) },
                            onFocus: { onFocusApp(chip.id) },
                            onHoverSelect: appTrigger == .hover && hoverEnabled ? { onSelectApp(chip.id) } : nil
                        ) {
                            HStack(spacing: 5) {
                                if let icon = SourceAppStyle.resolve(bundleID: chip.sourceBundleID).icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 17, height: 17)
                                }
                                Text(chip.label)
                            }
                        }
                        .id(chip.id)
                    }
                    if !filters.apps.isEmpty && !filters.kinds.isEmpty {
                        separator
                    }
                    ForEach(filters.kinds + filters.tags) { chip in
                        ChipButton(
                            chip: chip,
                            viewportWidth: rowWidth, viewportSpace: viewportSpace, isPanelVisible: isPanelVisible,
                            focusVisible: !cursorSuppressed,
                            onToggle: { onToggleKind(chip.id) },
                            onFocus: { onFocusKind(chip.id) }
                        ) {
                            HStack(spacing: 5) {
                                if let tag = PinTagColor.allCases.first(where: { $0.filterKey == chip.id }) {
                                    Circle().fill(tag.color).frame(width: 9, height: 9)
                                } else {
                                    chipIcon(chip.icon)
                                }
                                Text(chip.label)
                            }
                        }
                        .id(chip.id)
                    }
                }
                .padding(.vertical, 3)
                // Centered under the search capsule while the chips fit: a
                // scroll view hugs the leading edge otherwise. Stretched to
                // the viewport, the stack centers its content; a wider row
                // scrolls as before.
                .frame(minWidth: max(0, rowWidth - 2 * Self.horizontalMargin))
                // Keep insets inside the measured document: macOS 15's
                // scroll contentMargins can expand the viewport unevenly.
                .padding(.horizontal, Self.horizontalMargin)
            }
            .scrollClipDisabled()
            .defaultScrollAnchor(.center)
            .coordinateSpace(name: viewportSpace)
            .readSize { rowWidth = $0.width }
            .onChange(of: filters.focusedChipID) { _, id in
                guard let id else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                    proxy.scrollTo(id)
                }
            }
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(.white.opacity(0.25))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 4)
            .accessibilityHidden(true)
    }

    @ViewBuilder private func chipIcon(_ icon: ChipIcon?) -> some View {
        switch icon {
        case .resource(let name, let fallback):
            if let image = CategoryIcons.image(named: name) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: 16, height: 16)
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
            .font(.system(size: 12))
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
    let isPanelVisible: Bool
    var baseTint: Color?
    var focusVisible = true
    let onToggle: () -> Void
    let onFocus: () -> Void
    var onHoverSelect: (() -> Void)?
    @State private var hoverActivation = FilterHoverActivation()
    @State private var viewport = FilterChipViewport.unknown
    @State private var glassMounted = false
    @ViewBuilder let label: () -> Label
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isFocused: Bool {
        chip.isFocused && focusVisible
    }

    private var zoomed: Bool {
        isFocused || chip.isActive
    }

    private var canHover: Bool { isPanelVisible && viewport.isVisible && onHoverSelect != nil }

    var body: some View {
        label().beButton {
            hoverActivation.cancel()
            onToggle()
        }
        .buttonStyle(FilterChipStyle(isActive: chip.isActive, isFocused: isFocused))
        .accessibilityLabel(chip.accessibilityLabel)
        .accessibilityAddTraits(chip.isActive ? .isSelected : [])
        .linkPointer()
        .onGeometryChange(for: FilterChipViewport.self) { geometry in
            FilterChipViewport.measure(frame: geometry.frame(in: .named(viewportSpace)), viewportWidth: viewportWidth)
        } action: { observation in
            hoverActivation.isEnabled = isPanelVisible && observation.isVisible && onHoverSelect != nil
            viewport = observation
            glassMounted = observation.keepsGlass(previouslyMounted: glassMounted)
        }
        .scaleEffect(zoomed ? 1.06 : 1)
        // The frosted capsule is an AppKit view and ignores transforms, so
        // it grows geometrically in a measured background — oversize does
        // not push neighbors — while the content scales above it.
        .background {
            GeometryReader { proxy in
                if isPanelVisible && glassMounted {
                    Color.clear
                        .liquidGlass(
                            in: Capsule(),
                            tint: chip.isActive ? Color.matcha.opacity(0.28) : baseTint
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
            hoverActivation.cancel()
            hoverActivation.isEnabled = canHover
            if inside, canHover, let onHoverSelect, MouseActivity.movedRecently {
                hoverActivation.enter(onHoverSelect)
            }
        }
        .onAppear { hoverActivation.isEnabled = canHover }
        .onDisappear { hoverActivation.isEnabled = false }
        .onChange(of: canHover) { _, enabled in hoverActivation.isEnabled = enabled }
        .onContinuousHover { phase in
            if case .active = phase, isPanelVisible, viewport.isVisible, MouseActivity.movedRecently {
                onFocus()
            }
        }
    }
}

private struct FilterChipStyle: ButtonStyle {
    let isActive: Bool
    let isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(isActive ? .semibold : .regular))
            .foregroundStyle(isActive ? Color.matcha : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay(
                Capsule().strokeBorder(borderColor, lineWidth: isFocused ? 2 : 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }

    private var borderColor: Color {
        if isFocused {
            return Color.matcha
        }
        if isActive {
            return Color.matcha.opacity(0.8)
        }
        return .clear
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

@available(macOS 26, *)
struct MacOS26HistoryCard: View, Equatable {
    private static let sourceFontSize = NSFont.preferredFont(forTextStyle: .callout, options: [:]).pointSize * 1.1

    let card: CardViewState
    let actions: PanelActions
    let keyBindings: KeyBindingsStore?
    let side: CGFloat
    let showsSelection: Bool
    let isVisible: Bool
    let hoverEnabled: Bool
    let pinnedWorkspace: Bool
    let interactions: InteractionBindings
    let canExport: () -> Bool
    let interact: (CardAction) -> Void
    let hoverPreview: () -> Void
    let hoverChanged: (Bool) -> Void

    @State private var showingActions = false
    @State private var editingPin = false
    @State private var isHovering = false
    @State private var hoverTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.cardPopoverCoordinator) private var popoverCoordinator

    private var shape: RoundedRectangle { MacOS26CardSurface.outline }
    private var focusColor: Color { .macOS26ReadableAccent(in: scheme) }
    private var isFocused: Bool { card.isSelected && showsSelection }
    private var zoomedSide: CGFloat { side * HistoryViewStateStore.selectionZoom }
    private var slotInset: CGFloat { (zoomedSide - side) / 2 }
    private var source: SourceAppStyle.Resolved { SourceAppStyle.resolve(bundleID: card.sourceBundleID) }
    private var railBorder: Color { MacOS26CardSurface.border(in: contrast) }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.card == rhs.card && lhs.side == rhs.side && lhs.showsSelection == rhs.showsSelection
            && lhs.isVisible == rhs.isVisible && lhs.hoverEnabled == rhs.hoverEnabled
            && lhs.pinnedWorkspace == rhs.pinnedWorkspace && lhs.interactions == rhs.interactions
    }

    var body: some View {
        cardBody
            .interfaceType(.standard)
            .scaleEffect(card.isSelected ? HistoryViewStateStore.selectionZoom : 1)
            .frame(width: zoomedSide, height: zoomedSide)
            .contentShape(.rect)
            .macOS26GrabPointer()
            .onDrag(offerDrag)
            .gesture(
                TapGesture(count: 2).exclusively(before: TapGesture()).onEnded { value in
                    switch value {
                    case .first: perform(interactions.doubleClick)
                    case .second: perform(interactions.singleClick)
                    }
                }
            )
            .overlay(alignment: .topTrailing) {
                actionButton
                    .padding(card.isSelected ? 10 : slotInset + 10)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: card.isSelected)
            .background(MacOS26CardRightClick { perform(interactions.rightClick) })
            .onHover { inside in
                isHovering = inside
                hoverChanged(inside)
                scheduleHoverPreview()
            }
            .onContinuousHover { phase in
                if case .active = phase, hoverEnabled, MouseActivity.movedRecently { actions.highlight(card.id) }
            }
            .onChange(of: hoverEnabled) { _, _ in scheduleHoverPreview() }
            .onChange(of: interactions) { _, _ in hoverTask?.cancel() }
            .onChange(of: showingActions) { _, shown in
                hoverTask?.cancel()
                if !shown { setEditingPin(false) }
            }
            .onDisappear {
                setEditingPin(false)
                hoverTask?.cancel()
                hoverChanged(false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("clipboard-card-macos26-\(card.id.uuidString)")
            .accessibilityLabel(card.accessibilityLabel)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(localized("Uses the configured card action"))
            .accessibilityAddTraits(isFocused ? [.isButton, .isSelected] : [.isButton])
            .accessibilityAction(.default) { perform(interactions.singleClick) }
            .accessibilityAction(named: Text(localized("Actions"))) { perform(.menu) }
            .accessibilityAction(named: Text(localized("Copy"))) { perform(.copy) }
            .accessibilityAction(named: Text(card.isPinned ? localized("Unpin") : localized("Pin"))) {
                if canExport() { actions.togglePin(card.id) }
            }
            .accessibilityAction(named: Text(localized("Delete"))) {
                if canExport() { actions.delete(card.id) }
            }
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            metadata
            MacOS26CardPreview(card: card, isActive: isVisible)
            footer
        }
        .padding(12)
        .frame(width: side, height: side)
        .containerShape(shape)
        .background {
            ZStack {
                if card.isSplitGroup {
                    ForEach([2, 1], id: \.self) { layer in
                        shape.fill(Color(nsColor: .windowBackgroundColor))
                            .overlay(shape.strokeBorder(railBorder))
                            .padding(.horizontal, CGFloat(layer) * 5)
                            .offset(y: -CGFloat(layer) * 4)
                    }
                }
                shape.fill(MacOS26CardSurface.fill(in: scheme))
                    .overlay(alignment: .top) {
                        if card.sourceBundleID != nil {
                            LinearGradient(
                                colors: [source.tint.opacity(scheme == .dark ? 0.16 : 0.10), .clear],
                                startPoint: .top, endPoint: .bottom
                            )
                            .frame(height: side * 0.52)
                            .clipShape(shape)
                        }
                    }
            }
            .shadow(color: .black.opacity(scheme == .dark ? 0.30 : 0.12), radius: 5, y: 2)
        }
        .overlay {
            shape.strokeBorder(isFocused ? focusColor : railBorder, lineWidth: isFocused ? 2 : 1)
                .allowsHitTesting(false)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Group {
                if let icon = source.icon {
                    Image(nsImage: icon).resizable().scaledToFit()
                } else {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: Self.sourceFontSize))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 22, height: 22)
            Text(card.sourceLabel)
                .font(.system(size: Self.sourceFontSize, weight: .semibold))
                .lineLimit(1)
                .help(
                    card.sourceKey == "origin:handoff-marker"
                        ? localized("A Handoff marker was observed. The device and source app are unknown.")
                        : localized("Application observed on this Mac at capture time; source is not verified.")
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
        }
        .frame(height: 25)
        .padding(.trailing, 30)
    }

    @ViewBuilder private var metadata: some View {
        if !card.pinnedMetadata.note.isEmpty {
            Text(card.pinnedMetadata.note).font(.callout.weight(.semibold)).lineLimit(side < 175 ? 1 : 2)
        }
        if card.isSplitGroup || card.variantCount > 1 || card.stackPosition != nil || card.isPinned {
            HStack(spacing: 6) {
                if card.isSplitGroup { countBadge(card.splitCount, symbol: "square.on.square") }
                if card.variantCount > 1 { countBadge(card.variantCount, symbol: "doc.on.doc") }
                if let position = card.stackPosition {
                    countBadge(position, symbol: "square.stack.3d.up.fill").foregroundStyle(focusColor)
                }
                if card.isPinned {
                    Image(systemName: "pin.fill")
                    ForEach(PinTagColor.allCases.filter(card.pinnedMetadata.tags.contains)) { tag in
                        Circle().fill(tag.macOS26Color).frame(width: 6, height: 6)
                    }
                }
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
    }

    private func countBadge(_ count: Int, symbol: String) -> some View {
        Label(count.formatted(), systemImage: symbol)
            .lineLimit(1)
            .fixedSize()
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Text(card.timeLabel)
            Spacer(minLength: 4)
            if let detail = card.detailLabel {
                Text(detail).foregroundStyle(.tertiary)
            }
            Image(systemName: card.kindSymbol).help(card.kindLabel)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var actionButton: some View {
        Image(systemName: "ellipsis")
            .font(.caption.weight(.semibold))
            .foregroundStyle(scheme == .dark ? Color(white: 0.94) : Color(white: 0.16))
            .frame(width: 25, height: 25)
            .contentShape(.circle)
            .beButton { perform(.menu) }
            .buttonStyle(.plain)
            .background(.fill.quaternary, in: .circle)
            .glassEffect(reduceTransparency ? .identity : .regular.interactive(), in: .circle)
            .accessibilityLabel(localized("Actions"))
            .help(localized("Actions"))
            .macOS26CardActionPopover(isPresented: $showingActions) {
                if canExport() {
                    if editingPin {
                        MacOS26PinnedItemEditor(value: card.pinnedMetadata) { value in
                            guard canExport() else { return }
                            actions.updatePinnedMetadata(card.id, value)
                            closeActions()
                        }
                        .padding(16)
                    } else {
                        MacOS26CardActionList(
                            card: card, keyBindings: keyBindings, pinnedWorkspace: pinnedWorkspace,
                            run: runCommand, transform: runTransform, dismiss: closeActions)
                    }
                }
            }
    }

    private var accessibilityValue: String {
        guard card.isSplitGroup else { return card.accessibilityValue }
        return [card.accessibilityValue, localized("Card group"), localized("\(card.splitCount) items")]
            .joined(separator: ", ")
    }

    private func perform(_ action: CardAction) {
        guard canExport() else { return }
        if action == .menu { showingActions = true } else { interact(action) }
    }

    private func offerDrag() -> NSItemProvider {
        guard canExport(), !card.contentHidden, !card.isSplitGroup, card.variantCount <= 1 else {
            return NSItemProvider()
        }
        actions.dragBegan()
        return CardDragProvider.make(for: card.dragPayload)
    }

    private func runCommand(_ command: CardMenuCommand) {
        guard canExport() else { return }
        if command == .pinDetails {
            setEditingPin(true)
        } else {
            closeActions()
            command.run(for: card, actions: actions, perform: perform)
        }
    }

    private func runTransform(_ transform: TextTransform) {
        guard canExport() else { return }
        closeActions()
        actions.transform(card.id, transform)
    }

    private func closeActions() {
        popoverCoordinator?.dismiss(restoreFocus: true)
        showingActions = false
    }

    private func setEditingPin(_ value: Bool) {
        guard editingPin != value else { return }
        editingPin = value
        actions.metadataEditorChanged(value)
    }

    private func scheduleHoverPreview() {
        hoverTask?.cancel()
        guard isHovering, hoverEnabled, !showingActions, isVisible, interactions.hover == .preview else { return }
        hoverTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(interactions.hoverDelay))
            guard !Task.isCancelled, canExport() else { return }
            hoverPreview()
        }
    }
}

// WhiskyMac: modified or added 2026-11-10 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

/// The same command layout is used by the card's ellipsis and by a configured Menu action.
@available(macOS 26, *)
struct MacOS26CardActionMenu: View {
    @Environment(\.interfaceTypography) private var typography

    let card: CardViewState
    let actions: PanelActions
    var keyBindings: KeyBindingsStore? = nil
    var pinnedWorkspace = false
    let perform: (CardAction) -> Void
    let editPinnedItem: () -> Void
    let dismiss: () -> Void

    @State private var showsTransforms = false
    @State private var focusedID: String?
    @State private var keyboardRegistration = UUID()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.cardPopoverCoordinator) private var popoverCoordinator
    @Environment(\.cardPopoverKeyboard) private var keyboard

    static func sections(for card: CardViewState, pinnedWorkspace: Bool = false) -> [[CardMenuCommand]] {
        CardMenuCommand.sections(for: card, pinnedWorkspace: pinnedWorkspace)
    }

    private var visibleCommands: [CardMenuCommand] {
        Self.sections(for: card, pinnedWorkspace: pinnedWorkspace).flatMap { $0 }
    }
    private var visibleIDs: [String] {
        showsTransforms
            ? ["back"] + TextTransform.allCases.map { "transform.\($0.rawValue)" } : visibleCommands.map(\.id)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if showsTransforms {
                        menuRow(id: "back", title: localized("Paste as…"), symbol: "chevron.left") {
                            showsTransforms = false
                        }
                        Divider().padding(.horizontal, 7).padding(.vertical, 3)
                        ForEach(TextTransform.allCases, id: \.rawValue) { transform in
                            menuRow(id: "transform.\(transform.rawValue)", title: transform.label, symbol: "textformat")
                            {
                                dismiss()
                                actions.transform(card.id, transform)
                            }
                        }
                    } else {
                        if card.variantCount > 1 {
                            Text(localized("Pin, delete and stack actions apply to the newest format."))
                                .font(typography.font(.caption)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 7).padding(.bottom, 4)
                        }
                        IndexedForEach(
                            Self.sections(for: card, pinnedWorkspace: pinnedWorkspace), indexID: \.self
                        ) { index, section in
                            if index > 0 { Divider().padding(.horizontal, 7).padding(.vertical, 3) }
                            ForEach(section) { command in
                                menuRow(
                                    id: command.id, title: command.title(for: card), symbol: command.symbol,
                                    shortcut: command.keyAction.flatMap { keyBindings?.label(for: $0) },
                                    destructive: command.isDestructive,
                                    accessory: command == .pasteAs ? "chevron.right" : nil
                                ) {
                                    run(command)
                                }
                            }
                        }
                    }
                }
                .padding(3)
            }
            .frame(width: min(typography.room(304), (NSScreen.main?.visibleFrame.width ?? 720) - 32))
            .frame(maxHeight: min(520, (NSScreen.main?.visibleFrame.height ?? 700) - 70))
            .onMoveCommand { direction in
                guard let current = focusedID.flatMap({ visibleIDs.firstIndex(of: $0) }) else {
                    focusedID = visibleIDs.first
                    return
                }
                switch direction {
                case .up: focusedID = visibleIDs[max(0, current - 1)]
                case .down: focusedID = visibleIDs[min(visibleIDs.count - 1, current + 1)]
                default: break
                }
            }
            .onExitCommand {
                if showsTransforms { showsTransforms = false } else { dismiss() }
            }
            .onAppear {
                focusedID = visibleIDs.first
                keyboard?.install(keyboardRegistration, handler: handleKey)
            }
            .onDisappear { keyboard?.remove(keyboardRegistration) }
            .onChange(of: showsTransforms) { _, _ in focusedID = visibleIDs.first }
            .onChange(of: focusedID) { _, id in
                guard let id else { return }
                if reduceMotion {
                    proxy.scrollTo(id)
                } else {
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) }
                }
            }
        }
    }

    private func menuRow(
        id: String, title: String, symbol: String, shortcut: String? = nil,
        destructive: Bool = false, accessory: String? = nil, action: @escaping () -> Void
    ) -> some View {
        let destructiveColor = scheme == .light ? Color.macOS26ReadableAccent(in: scheme, color: .systemRed) : .red
        return HStack(alignment: .center, spacing: 8) {
            Image(systemName: symbol)
                .font(typography.font(size: 14))
                .frame(width: typography.room(18), alignment: .center)
                .foregroundStyle(destructive ? destructiveColor : .secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(typography.font(size: 13))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .foregroundStyle(destructive ? destructiveColor : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let shortcut {
                Text(shortcut)
                    .font(typography.font(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .accessibilityHidden(true)
            }
            if let accessory {
                Image(systemName: accessory).font(typography.font(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary).accessibilityHidden(true)
            }
        }
        .frame(minHeight: 30)
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity)
        .background(
            focusedID == id ? Color.accentColor.opacity(0.16) : Color.clear,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .contentShape(Rectangle())
        .beButton(action)
        .buttonStyle(.plain)
        .onHover { inside in if inside { focusedID = id } }
        .id(id)
        .accessibilityLabel(title)
        .accessibilityHint(shortcut ?? "")
    }

    private func run(_ command: CardMenuCommand) {
        if command == .pasteAs { showsTransforms = true; return }
        if command == .pinDetails { editPinnedItem(); return }
        popoverCoordinator?.dismiss(restoreFocus: true)
        dismiss()
        command.run(for: card, actions: actions, perform: perform)
    }

    private func handleKey(_ code: UInt16) -> Bool {
        switch code {
        case 125, 126:
            guard let index = focusedID.flatMap({ visibleIDs.firstIndex(of: $0) }) else {
                focusedID = visibleIDs.first
                return true
            }
            focusedID = visibleIDs[min(max(index + (code == 125 ? 1 : -1), 0), visibleIDs.count - 1)]
        case 36, 76:
            guard let focusedID else { return false }
            if showsTransforms {
                if focusedID == "back" {
                    showsTransforms = false
                } else if let transform = TextTransform.allCases.first(where: {
                    "transform.\($0.rawValue)" == focusedID
                }) {
                    popoverCoordinator?.dismiss(restoreFocus: true)
                    dismiss()
                    actions.transform(card.id, transform)
                }
            } else if let command = CardMenuCommand(rawValue: focusedID) {
                run(command)
            }
        case 53:
            if showsTransforms {
                showsTransforms = false
            } else {
                popoverCoordinator?.dismiss(restoreFocus: true); dismiss()
            }
        default: return false
        }
        return true
    }
}

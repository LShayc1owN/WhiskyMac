// WhiskyMac: modified or added 2026-11-19 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

/// History controls stay outside the search capsule, including in Privacy Mode.
struct HistoryToolbarActions: View {
    @ObservedObject var store: HistoryViewStateStore
    var actions: PanelActions?

    private var enabled: Bool {
        actions != nil && store.canToggleHistoryVisibility
    }
    private var helpEnabled: Bool {
        store.panelVisible && !store.historyHidingOptionsOpen
    }

    private var hideHelp: String {
        localized(
            "Hide cards created before the selected time. Click to use now, or right-click to choose a time. Click again to show hidden cards."
        )
    }
    private var typeHelp: String {
        localized(
            "Hide selected types or Handoff cards created before the selected time. Click to choose filters and a time. Click again to show hidden cards."
        )
    }

    var body: some View {
        if !store.isPinnedWorkspace {
            HStack(spacing: 8) {
                hideButton
                typeButton
            }
            .fixedSize()
            .onDisappear(perform: closeOptions)
        }
    }

    private var hideButton: some View {
        Label(
            store.isHistoryHidden ? localized("Show") : localized("Hide"),
            systemImage: store.isHistoryHidden ? "eye" : "eye.slash"
        )
        .modifier(HidingButtonSurface(active: store.isHistoryHidden))
        .beButton {
            if let actions {
                store.toggleHistoryVisibility(actions: actions)
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(store.isHistoryHidden ? localized("Show hidden cards") : localized("Hide existing cards"))
        .accessibilityIdentifier("clipboard-hide-history")
        .accessibilityAction(named: Text(localized("Choose hiding time"))) {
            openTimeOptions()
        }
        .background(
            CardRightClick {
                openTimeOptions()
            }
        )
        .modifier(HistoryHoverHelp(title: localized("Hide"), message: hideHelp, enabled: helpEnabled))
        .popover(isPresented: showingOptions(.time)) {
            HistoryHidingOptions(
                includesTypes: false, confirm: apply, cancel: closeOptions,
                draft: HistoryHidingDraft(usesNow: false, date: store.historyHidingCutoff ?? Date()))
        }
    }

    private var typeButton: some View {
        Label(
            store.isTypeHistoryHidden ? localized("Show by type or source") : localized("Hide by type or source"),
            systemImage: "line.3.horizontal.decrease.circle"
        )
        .modifier(HidingButtonSurface(active: store.isTypeHistoryHidden))
        .beButton {
            if let actions {
                store.toggleTypeHistoryVisibility(actions: actions)
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier("clipboard-hide-types")
        .modifier(HistoryHoverHelp(title: localized("Hide by type or source"), message: typeHelp, enabled: helpEnabled))
        .popover(isPresented: showingOptions(.typeOrSource)) {
            HistoryHidingOptions(includesTypes: true, confirm: apply, cancel: closeOptions)
        }
    }

    private func openTimeOptions() {
        guard enabled else { return }
        store.historyHidingOptions = .time
    }

    private func showingOptions(_ options: HistoryViewStateStore.HidingOptions) -> Binding<Bool> {
        Binding(
            get: { store.historyHidingOptions == options },
            set: { showing in
                if !showing, store.historyHidingOptions == options { closeOptions() }
            })
    }

    private func apply(_ rule: HistoryHidingRule) {
        closeOptions()
        if let actions {
            store.setHistoryHiding(rule, actions: actions)
        }
    }

    private func closeOptions() {
        if store.historyHidingOptionsOpen { store.historyHidingOptions = nil }
    }
}

private struct HidingButtonSurface: ViewModifier {
    let active: Bool
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let accent = Color.readableAccent(in: scheme)
        content
            .font(.callout)
            .foregroundStyle(active ? accent : .primary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(ClipboardMaterialSurface(shape: Capsule(), material: .underWindowBackground))
            .overlay(Capsule().strokeBorder(accent.opacity(active ? 0.8 : 0), lineWidth: 1))
    }
}

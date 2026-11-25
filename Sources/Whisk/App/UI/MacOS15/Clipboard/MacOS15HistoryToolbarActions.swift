// WhiskyMac: modified or added 2026-11-19 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

struct MacOS15ReturnToLatestButton: View {
    @Environment(\.interfaceTypography) private var typography

    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let title = localized("Back to latest")
        HStack(spacing: 0) {
            Image(systemName: "arrow.left.to.line")
                .font(typography.font(size: 14, weight: .semibold))
                .frame(width: max(36, typography.lineHeight(14) + 18))
            if hovering && !typography.usesLargeLayout {
                Text(title)
                    .font(typography.font(.caption).weight(.semibold))
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.trailing, 12)
                    .transition(.opacity)
            }
        }
        .frame(height: max(36, typography.lineHeight(14) + 18))
        .foregroundStyle(.white)
        .background(
            MacOS15ClipboardMaterialSurface(
                shape: Capsule(), material: .underWindowBackground, tint: .macOS15ReadableAccent(in: scheme))
        )
        .contentShape(Capsule())
        .beButton(action)
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .help(title)
        .onHover { inside in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                hovering = inside
            }
        }
    }
}

/// History controls stay outside the search capsule, including in Privacy Mode.
struct MacOS15HistoryToolbarActions: View {
    @Environment(\.interfaceTypography) private var typography
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

    @ViewBuilder
    private func actionLabel(_ title: String, systemImage: String) -> some View {
        if typography.usesLargeLayout {
            Label(title, systemImage: systemImage).labelStyle(.iconOnly)
        } else {
            Label(title, systemImage: systemImage)
        }
    }

    private var hideButton: some View {
        actionLabel(
            store.isHistoryHidden ? localized("Show") : localized("Hide"),
            systemImage: store.isHistoryHidden ? "eye" : "eye.slash"
        )
        .modifier(MacOS15HidingButtonSurface(active: store.isHistoryHidden))
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
            MacOS15CardRightClick {
                openTimeOptions()
            }
        )
        .modifier(MacOS15HistoryHoverHelp(title: localized("Hide"), message: hideHelp, enabled: helpEnabled))
        .popover(isPresented: showingOptions(.time)) {
            options(
                includesTypes: false,
                draft: HistoryHidingDraft(usesNow: false, date: store.historyHidingCutoff ?? Date()))
        }
    }

    private var typeButton: some View {
        actionLabel(
            store.isTypeHistoryHidden ? localized("Show by type or source") : localized("Hide by type or source"),
            systemImage: "line.3.horizontal.decrease.circle"
        )
        .modifier(MacOS15HidingButtonSurface(active: store.isTypeHistoryHidden))
        .beButton {
            if let actions {
                store.toggleTypeHistoryVisibility(actions: actions)
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(
            store.isTypeHistoryHidden ? localized("Show by type or source") : localized("Hide by type or source")
        )
        .accessibilityIdentifier("clipboard-hide-types")
        .modifier(
            MacOS15HistoryHoverHelp(title: localized("Hide by type or source"), message: typeHelp, enabled: helpEnabled)
        )
        .popover(isPresented: showingOptions(.typeOrSource)) {
            options(includesTypes: true, draft: HistoryHidingDraft())
        }
    }

    @ViewBuilder private func options(includesTypes: Bool, draft: HistoryHidingDraft) -> some View {
        MacOS15HistoryHidingOptions(includesTypes: includesTypes, confirm: apply, cancel: closeOptions, draft: draft)

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

private struct MacOS15HidingButtonSurface: ViewModifier {
    @Environment(\.interfaceTypography) private var typography

    let active: Bool
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let accent = Color.macOS15ReadableAccent(in: scheme)
        content
            .font(typography.font(.callout))
            .foregroundStyle(active ? accent : .primary)
            .padding(.horizontal, 12)
            .frame(height: max(36, typography.lineHeight(14) + 18))
            .background(MacOS15ClipboardMaterialSurface(shape: Capsule(), material: .underWindowBackground))
            .overlay(Capsule().strokeBorder(accent.opacity(active ? 0.8 : 0), lineWidth: 1))
    }
}

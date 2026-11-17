// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

/// The card indices the scroll position keeps on screen, quantized to
/// whole cards so state only changes when the leading card does.
struct CardRailWindow: Equatable {
    var leading = 0
    var capacity = 8

    static let buffer = 2

    func contains(_ index: Int, selectedIndex: Int?) -> Bool {
        if index == selectedIndex { return true }
        let lower = max(0, leading - Self.buffer)
        let upper = leading + capacity + Self.buffer
        return (lower...upper).contains(index)
    }
}

struct RailFilter: Equatable {
    let query: String
    let activeChips: [String]

    init(_ state: HistoryViewState) {
        query = state.query
        activeChips = (state.filters.all + state.filters.pinned + state.filters.apps + state.filters.kinds)
            .filter(\.isActive).map(\.id)
    }
}

struct HistoryPanelView: View {
    @ObservedObject var store: HistoryViewStateStore
    let actions: PanelActions
    var keyBindings: KeyBindingsStore? = nil
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The rail runs edge to edge, but what replaces it is bounded and
    /// centered: on an ultra-wide monitor an editor spanning the screen
    /// would set 400-character lines, and the empty-state slab would be a
    /// 3400-point plate for one sentence.
    static let editorMaxWidth: CGFloat = 960
    /// The search capsule's expanded width, so the two read as one column.
    static let emptyStateMaxWidth: CGFloat = 680

    /// The field echoes keystrokes instantly; the controller's query only
    /// follows after the debounce, so the text must live here.
    @State private var searchText = ""
    @State private var returnToLatestRevision = 0
    @State private var appScope = FilterAppScope(visibleSourceKeys: [])

    private var queryBinding: Binding<String> {
        Binding(
            get: { searchText },
            set: { newValue in
                searchText = newValue
                actions.search(newValue)
            }
        )
    }

    private var searchExpanded: Bool {
        store.searchExpanded(typed: searchText)
    }

    private var cursorOnSearch: Bool {
        store.cursorOnSearch
    }

    var body: some View {
        Group {
            if store.isProtected {
                PrivacySpotlightView(store: store)
            } else {
                historyBody
            }
        }
        .id(store.appearanceRevision)
        .overlay(alignment: .topLeading) {
            AppSymbolView()
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .padding(.leading, 20)
                .padding(.top, 15)
                .allowsHitTesting(false)
        }
        .tint(Color.matcha)
        .onChange(of: store.isProtected) { _, _ in searchText = "" }
    }

    private var historyBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The landing page's layout, mirrored: a centered search capsule
            // of bounded width, the filter chips centered right below it.
            HStack(spacing: 10) {
                Image(systemName: "arrow.left.to.line")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .frostedSurface(in: Circle())
                    .beButton { returnToLatestRevision += 1 }
                    .buttonStyle(.plain)
                    .disabled(store.state.cards.isEmpty || store.editing != nil)
                    .help(localized("Back to latest"))
                    .accessibilityLabel(localized("Back to latest"))
                toolbar
            }
            .frame(maxWidth: searchExpanded ? 680 : 480)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: searchExpanded)
            if !store.state.filters.isEmpty {
                FilterBarView(
                    filters: store.state.filters,
                    appScope: appScope,
                    cursorSuppressed: cursorOnSearch,
                    appTrigger: store.appFilterTrigger,
                    hoverEnabled: store.panelVisible,
                    isPanelVisible: store.panelVisible,
                    onSelectApp: { key in
                        guard store.panelVisible, !store.isProtected, store.appFilterTrigger == .hover else { return }
                        actions.selectSourceFilter(key)
                    },
                    onToggleApp: actions.toggleSourceFilter,
                    onToggleKind: actions.toggleCategoryFilter,
                    onFocusApp: actions.focusSourceChip,
                    onFocusKind: actions.focusCategoryChip
                )
            }
            if !store.isPinnedWorkspace { SensitiveSessionView(session: store.sensitiveSession) }
            content
        }
        .padding(.top, PanelLayout.panelTopBand)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onAppear {
            searchText = store.state.query; searchFocused = store.searchActive
        }
        .onChange(of: store.focusRevision) {
            searchFocused = store.searchActive
            searchText = store.state.query
        }
        .onChange(of: store.searchActive) { _, active in
            // One beat later: entering search mode swaps the hint for the
            // field, which must exist before it can take focus.
            DispatchQueue.main.async {
                searchFocused = active
            }
        }
        .onChange(of: store.state.query) { _, query in
            // NORMAL-mode clears (the c command) land in the controller
            // first; the local echo follows once nobody is typing.
            if !searchFocused {
                searchText = query
            }
        }

    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            if store.vimEnabled && !store.searchActive {
                // NORMAL mode: the letters are commands, the field is out
                // of the loop — the persisted query stays readable.
                Text(
                    searchText.isEmpty
                        ? String(format: localized("Press %@ to search"), store.vimSearchKey)
                        : searchText
                )
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .linkPointer()
            } else {
                TextField(
                    searchExpanded ? localized("Search clipboard history") : localized("Search"),
                    text: queryBinding
                )
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($searchFocused)
            }
            Spacer(minLength: 0)
            if store.state.stackCount > 0 {
                Label("\(store.state.stackCount)", systemImage: "square.stack.3d.up.fill")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.matcha)
                    .help(localized("Paste stack — pop with the global shortcut"))
                    .accessibilityLabel(localized("\(store.state.stackCount) in the paste stack"))
            }
            if !store.isPinnedWorkspace {
                Label(localized("Clear"), systemImage: "trash")
                    .font(.caption)
                    .beButton(role: .destructive) {
                        store.clearHistory(actions: actions)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!store.state.canClearHistory || store.editing != nil)
                    .accessibilityLabel(localized("Clear unpinned history"))
                    .help(
                        localized(
                            "Clears all unpinned history, including hidden results. Pinned items are kept. Undo with Command-Z."
                        ))
            }
            Text(store.state.countLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            if store.vimEnabled {
                Text(store.searchActive ? localized("SEARCH") : localized("NORMAL"))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(.secondary.opacity(0.4), lineWidth: 1))
                    .accessibilityLabel(store.searchActive ? localized("Search mode") : localized("Normal mode"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frostedSurface(in: Capsule())
        // The capsule lights up as it stretches: a crisp matcha rim, the
        // same language as the cards' selection ring. Plain opacity (not
        // if/else) so the outer animation carries the fade.
        .overlay {
            Capsule()
                .strokeBorder(Color.matcha.opacity(0.9), lineWidth: 1)
                .opacity(searchExpanded ? 1 : 0)
                .allowsHitTesting(false)
        }
        .contentShape(Capsule())
        .onTapGesture {
            if store.vimEnabled, !store.searchActive {
                store.setSearchActive(true)
            }
        }
    }

    @ViewBuilder private var content: some View {
        if let editing = store.editing {
            EditItemView(
                store: store,
                card: editing,
                onSave: { text in
                    store.saveEditing(actions: actions)
                },
                onCancel: { store.endEditing() }
            )
            .frame(maxWidth: Self.editorMaxWidth)
            .frame(maxWidth: .infinity)
        } else if let prompt = store.state.accessPrompt, store.state.cards.isEmpty {
            accessPrompt(prompt)
                .frame(maxWidth: Self.emptyStateMaxWidth)
                .frame(maxWidth: .infinity)
        } else if let message = store.state.emptyMessage {
            emptyState(message)
                .frame(maxWidth: Self.emptyStateMaxWidth)
                .frame(maxWidth: .infinity)
        } else {
            HistoryCardRail(
                store: store, actions: actions, keyBindings: keyBindings,
                returnToLatestRevision: returnToLatestRevision, appScope: appScope)
        }
    }

    private func emptyState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(message)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frostedSurface(in: RoundedRectangle(cornerRadius: 22, style: .continuous), cornerRadius: 22)
        .padding(.horizontal, 16)
    }

    private func accessPrompt(_ prompt: AccessPromptViewState) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "hand.raised")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(prompt.message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(prompt.buttonTitle) { actions.requestClipboardAccess() }
                .buttonStyle(.borderedProminent)
                .tint(Color.matcha)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frostedSurface(in: RoundedRectangle(cornerRadius: 22, style: .continuous), cornerRadius: 22)
        .padding(.horizontal, 16)
    }
}

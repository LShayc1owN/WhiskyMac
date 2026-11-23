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
    let searchMatchMode: SearchMatchMode
    let activeChips: [String]

    init(_ state: HistoryViewState) {
        query = state.query
        searchMatchMode = state.searchMatchMode
        activeChips = state.filters.activeChipIDs
    }
}

struct HistoryPanelView: View {
    @ObservedObject var store: HistoryViewStateStore
    let actions: PanelActions
    var keyBindings: KeyBindingsStore? = nil
    var popoverCoordinator: CardPopoverCoordinator? = nil
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    private var accent: Color { .readableAccent(in: scheme) }

    /// The rail runs edge to edge, but what replaces it is bounded and
    /// centered: on an ultra-wide monitor an editor spanning the screen
    /// would set 400-character lines, and the empty-state slab would be a
    /// 3400-point plate for one sentence.
    static let editorMaxWidth: CGFloat = 960
    /// The width of the placeholder below the search controls.
    static let emptyStateMaxWidth: CGFloat = 680

    /// The field echoes keystrokes instantly; the controller's query only
    /// follows after the debounce, so the text must live here.
    @State private var searchText = ""
    @State private var returnToLatestRevision = 0
    @State private var hoveringReturnToLatest = false
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
                PrivacySpotlightView(store: store, actions: actions)
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
        .tint(accent)
        .environment(\.cardPopoverCoordinator, popoverCoordinator)
        .onChange(of: store.isProtected) { _, _ in searchText = "" }
    }

    private var historyBody: some View {
        let prompt = localized("Search in \(store.state.cards.count) items")
        let metrics = ClipboardSearchMetrics(prompt: prompt, expanded: searchExpanded)
        return VStack(alignment: .leading, spacing: PanelLayout.contentSpacing) {
            ClipboardSearchToolbarLayout(field: metrics) {
                HStack(spacing: 10) {
                    returnToLatestButton
                    toolbar(prompt: prompt, fieldWidth: metrics.preferredWidth)
                }
                HStack { HistoryToolbarActions(store: store, actions: actions) }
            }
            // Keep the capsule shadows within the toolbar width.
            .padding(.horizontal, scheme == .light ? 6 : 0)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: searchExpanded)
            if !store.state.filters.isEmpty {
                FilterBarView(
                    // Align to the resting card edge, independent of selection zoom.
                    horizontalMargin: PanelLayout.contentMargin + (store.zoomedCardSide - store.cardSide) / 2,
                    filters: store.state.filters,
                    tagScale: store.filterTagScale,
                    appScope: appScope,
                    cursorSuppressed: cursorOnSearch,
                    appTrigger: store.appFilterTrigger,
                    hoverEnabled: store.panelVisible && !store.cardMenuOpen,
                    isPanelVisible: store.panelVisible,
                    onSelectApp: { key in
                        guard store.panelVisible, !store.isProtected, !store.cardMenuOpen,
                            store.appFilterTrigger == .hover
                        else { return }
                        actions.selectSourceFilter(key)
                    },
                    onSelectKind: { key in
                        guard store.panelVisible, !store.isProtected, !store.cardMenuOpen,
                            store.appFilterTrigger == .hover
                        else { return }
                        actions.selectCategoryFilter(key)
                    },
                    onToggleApp: actions.toggleSourceFilter,
                    onToggleKind: actions.toggleCategoryFilter,
                    onFocusApp: { if !store.cardMenuOpen { actions.focusSourceChip($0) } },
                    onFocusKind: { if !store.cardMenuOpen { actions.focusCategoryChip($0) } }
                )
            } else if store.reservesHiddenFilterRow {
                Color.clear.frame(height: FilterTagMetrics(scale: store.filterTagScale).totalRowHeight)
                    .accessibilityHidden(true)
            }
            if !store.isPinnedWorkspace { SensitiveSessionView(session: store.sensitiveSession) }
            content
        }
        .padding(.top, PanelLayout.panelTopBand)
        .padding(.bottom, PanelLayout.bottomPadding)
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

    private var returnToLatestButton: some View {
        let title = localized("Back to latest")
        return HStack(spacing: 0) {
            Image(systemName: "arrow.left.to.line")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 36)
            if hoveringReturnToLatest {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.trailing, 12)
                    .transition(.opacity)
            }
        }
        .frame(height: 36)
        .foregroundStyle(.white)
        .background(ClipboardMaterialSurface(shape: Capsule(), material: .underWindowBackground, tint: accent))
        .contentShape(Capsule())
        .beButton { returnToLatestRevision += 1 }
        .buttonStyle(.plain)
        .disabled(store.state.cards.isEmpty || store.editing != nil)
        .accessibilityLabel(title)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                hoveringReturnToLatest = hovering
            }
        }
    }

    private func toolbar(prompt: String, fieldWidth: CGFloat) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Group {
                if store.vimEnabled && !store.searchActive {
                    // NORMAL mode leaves the persisted query readable while the field is inactive.
                    Text(
                        searchText.isEmpty
                            ? String(format: localized("Press %@ to search"), store.vimSearchKey)
                            : searchText
                    )
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .linkPointer()
                } else {
                    let promptText = Text(verbatim: prompt)
                    TextField(
                        localized("Search clipboard history"), text: queryBinding,
                        prompt: scheme == .light ? promptText.foregroundStyle(.secondary) : promptText
                    )
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                }
            }
            .font(.system(size: ClipboardSearchMetrics.fontSize))
            .frame(minWidth: 0, idealWidth: fieldWidth, maxWidth: fieldWidth, alignment: .leading)
            if store.state.stackCount > 0 {
                Label("\(store.state.stackCount)", systemImage: "square.stack.3d.up.fill")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(accent)
                    .help(localized("Paste stack — pop with the global shortcut"))
                    .accessibilityLabel(localized("\(store.state.stackCount) in the paste stack"))
            }
            if !searchText.isEmpty || (store.vimEnabled && !store.searchActive) {
                Text(store.state.countLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            if store.vimEnabled {
                Text(store.searchActive ? localized("SEARCH") : localized("NORMAL"))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(.secondary.opacity(0.4), lineWidth: 1))
                    .accessibilityLabel(store.searchActive ? localized("Search mode") : localized("Normal mode"))
            }
            SearchMatchPicker(mode: store.searchMatchMode) { mode in
                store.selectSearchMatchMode(mode, query: searchText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(ClipboardSearchBackground())
        .accessibilityIdentifier("clipboard-search")
        // The capsule lights up as it stretches: a crisp matcha rim, the
        // same language as the cards' selection ring. Plain opacity (not
        // if/else) so the outer animation carries the fade.
        .overlay {
            Capsule()
                .strokeBorder(accent.opacity(0.9), lineWidth: 1)
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
        } else {
            HistoryCardRail(
                store: store, actions: actions, keyBindings: keyBindings,
                returnToLatestRevision: returnToLatestRevision, appScope: appScope
            )
            .overlay {
                if let message = store.state.emptyMessage {
                    emptyState(message)
                        .frame(maxWidth: Self.emptyStateMaxWidth)
                        .padding(.bottom, PanelLayout.railVerticalPadding)
                        .transition(.opacity)
                }
            }
            .animation(
                reduceMotion || !store.panelVisible ? nil : .easeInOut(duration: 0.18),
                value: store.historyVisibilityRevision)
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
        .background(ClipboardMaterialSurface(shape: RoundedRectangle(cornerRadius: 22), cornerRadius: 22))
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
                .tint(accent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ClipboardMaterialSurface(shape: RoundedRectangle(cornerRadius: 22), cornerRadius: 22))
        .padding(.horizontal, 16)
    }
}

struct ClipboardSearchBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Capsule()
            .fill(Color.matcha.opacity(scheme == .light ? 0.23 : 0.30))
            .background {
                if reduceTransparency {
                    Capsule().fill(Color(nsColor: .windowBackgroundColor))
                }
            }
            .allowsHitTesting(false)
    }
}

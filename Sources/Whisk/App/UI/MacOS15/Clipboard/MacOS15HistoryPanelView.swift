// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

/// The card indices the scroll position keeps on screen, quantized to
/// whole cards so state only changes when the leading card does.
struct MacOS15HistoryPanelView: View {
    @Environment(\.interfaceTypography) private var typography

    @ObservedObject var store: HistoryViewStateStore
    let actions: PanelActions
    var keyBindings: KeyBindingsStore? = nil
    var popoverCoordinator: CardPopoverCoordinator? = nil
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    private var accent: Color { .macOS15ReadableAccent(in: scheme) }

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
                MacOS15PrivacySpotlightView(store: store, actions: actions)
            } else {
                historyBody
            }
        }
        .id(store.appearanceRevision)
        .overlay(alignment: .topLeading) {
            MacOS15AppSymbolView()
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
        let showsRail = store.editing == nil && (store.state.accessPrompt == nil || !store.state.cards.isEmpty)
        let minimum = showsRail ? min(typography.room(100), store.zoomedCardSide) : typography.room(100)
        return MacOS15HistoryPanelSections(minimumContentHeight: minimum) {
            historyControls
        } content: {
            content
        }
        .padding(.top, MacOS15PanelLayout.panelTopBand)
        .padding(.bottom, MacOS15PanelLayout.bottomPadding)
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

    private var historyControls: some View {
        let prompt = ClipboardSearchPrompt(count: store.state.cards.count, typography: typography)
        let metrics = MacOS15ClipboardSearchMetrics(
            prompt: prompt, expanded: searchExpanded)
        return VStack(alignment: .leading, spacing: MacOS15PanelLayout.contentSpacing) {
            MacOS15ClipboardSearchToolbarLayout(field: metrics) {
                HStack(spacing: 10) {
                    MacOS15ReturnToLatestButton { returnToLatestRevision += 1 }
                        .disabled(store.state.cards.isEmpty || store.editing != nil)
                    toolbar(prompt: prompt, fieldWidth: metrics.preferredWidth)
                }
                HStack { MacOS15HistoryToolbarActions(store: store, actions: actions) }
            }
            // Keep the capsule shadows within the toolbar width.
            .padding(.horizontal, scheme == .light ? 6 : 0)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: searchExpanded)
            if !store.state.filters.isEmpty {
                MacOS15FilterBarView(
                    // Align to the resting card edge, independent of selection zoom.
                    horizontalMargin: MacOS15PanelLayout.contentMargin + (store.zoomedCardSide - store.cardSide) / 2,
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
                let tags = MacOS15FilterTagMetrics(scale: store.filterTagScale, typography: typography)
                Color.clear.frame(height: tags.totalRowHeight)
                    .accessibilityHidden(true)
            }
            if !store.isPinnedWorkspace { MacOS15SensitiveSessionView(session: store.sensitiveSession) }
        }
    }

    private func toolbar(prompt: ClipboardSearchPrompt, fieldWidth: CGFloat) -> some View {
        HStack(spacing: 10) {
            MacOS15ClipboardSearchIcon()
            Group {
                if store.vimEnabled && !store.searchActive {
                    // NORMAL mode leaves the persisted query readable while the field is inactive.
                    Text(
                        searchText.isEmpty
                            ? String(format: localized("Press %@ to search"), store.vimSearchKey)
                            : searchText
                    )
                    .foregroundStyle(.secondary)
                    .lineLimit(searchText.isEmpty ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .macOS15LinkPointer()
                } else {
                    TextField(
                        localized("Search clipboard history"), text: queryBinding,
                        prompt: Text(verbatim: "")
                    )
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .macOS15ClipboardSearchPrompt(prompt, accent: accent, isVisible: searchText.isEmpty)
                }
            }
            .font(typography.font(size: ClipboardSearchPrompt.fontSize))
            .frame(minWidth: 0, idealWidth: fieldWidth, maxWidth: fieldWidth, alignment: .leading)
            .layoutPriority(1)
            if store.state.stackCount > 0 {
                Label("\(store.state.stackCount)", systemImage: "square.stack.3d.up.fill")
                    .font(typography.font(.caption, design: .monospaced))
                    .foregroundStyle(accent)
                    .help(localized("Paste stack — pop with the global shortcut"))
                    .accessibilityLabel(localized("\(store.state.stackCount) in the paste stack"))
            }
            if !searchText.isEmpty || (store.vimEnabled && !store.searchActive) {
                Text(
                    prompt.styledCount(in: store.state.countLabel, font: typography.font(.caption, design: .monospaced))
                )
                .font(typography.font(.caption))
                .foregroundStyle(.secondary)
                .fixedSize()
            }
            if store.vimEnabled {
                Text(store.searchActive ? localized("SEARCH") : localized("NORMAL"))
                    .font(typography.font(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(.secondary.opacity(0.4), lineWidth: 1))
                    .accessibilityLabel(store.searchActive ? localized("Search mode") : localized("Normal mode"))
            }
            MacOS15SearchMatchPicker(mode: store.searchMatchMode) { mode in
                store.selectSearchMatchMode(mode, query: searchText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .modifier(MacOS15ClipboardSearchSurface())
        .accessibilityIdentifier("clipboard-search")
        // The capsule lights up as it stretches: a crisp macOS15Matcha rim, the
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
            MacOS15EditItemView(
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
            MacOS15HistoryCardRail(
                store: store, actions: actions, keyBindings: keyBindings,
                returnToLatestRevision: returnToLatestRevision, appScope: appScope
            )
            .overlay {
                if let message = store.state.emptyMessage {
                    emptyState(message)
                        .frame(maxWidth: Self.emptyStateMaxWidth)
                        .padding(.bottom, MacOS15PanelLayout.railVerticalPadding)
                        .transition(.opacity)
                }
            }
            .animation(
                reduceMotion || !store.panelVisible ? nil : .easeInOut(duration: 0.18),
                value: store.historyVisibilityRevision)
        }
    }

    private func emptyState(_ message: String) -> some View {
        messageSurface {
            adaptiveMessage(message, symbol: "doc.on.clipboard")
        }
    }

    private func accessPrompt(_ prompt: AccessPromptViewState) -> some View {
        messageSurface {
            VStack(spacing: 10) {
                adaptiveMessage(prompt.message, symbol: "hand.raised")
                Button {
                    actions.requestClipboardAccess()
                } label: {
                    Label(prompt.buttonTitle, systemImage: "hand.raised")
                }
                .buttonStyle(MacOS15DialogActionStyle(prominent: true))
                .accessibilityLabel(prompt.buttonTitle)
                .layoutPriority(1)
            }
        }
    }

    private func adaptiveMessage(_ message: String, symbol: String) -> some View {
        let text = Text(message)
            .font(typography.font(.body))
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        return ViewThatFits(in: .vertical) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(typography.font(size: 24, weight: .light))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                text
            }
            .fixedSize(horizontal: false, vertical: true)
            text
            ScrollView { text.frame(maxWidth: .infinity) }
        }
    }

    private func messageSurface<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MacOS15ClipboardMaterialSurface(shape: RoundedRectangle(cornerRadius: 22), cornerRadius: 22))
            .padding(.horizontal, 16)
    }
}

struct MacOS15ClipboardSearchSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.background(MacOS15ClipboardSearchBackground())

    }
}

struct MacOS15ClipboardSearchIcon: View {
    var body: some View {
        Image(systemName: "magnifyingglass")
            .foregroundStyle(Color.secondary)
            .accessibilityHidden(true)
    }
}

private struct MacOS15ClipboardSearchBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Capsule()
            .fill(Color.macOS15Matcha.opacity(scheme == .light ? 0.23 : 0.30))
            .background {
                if reduceTransparency {
                    Capsule().fill(Color(nsColor: .windowBackgroundColor))
                }
            }
            .allowsHitTesting(false)
    }
}

struct MacOS15HistoryPanelSections<Controls: View, Content: View>: View {
    let minimumContentHeight: CGFloat
    @ViewBuilder let controls: Controls
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { geometry in
            // On short screens the controls scroll independently of the editor or card rail.
            let reserved = min(minimumContentHeight, geometry.size.height / 2)
            let spacing = MacOS15PanelLayout.contentSpacing
            VStack(alignment: .leading, spacing: spacing) {
                ScrollView(.vertical) { controls }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: max(0, geometry.size.height - reserved - spacing))
                    .fixedSize(horizontal: false, vertical: true)
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

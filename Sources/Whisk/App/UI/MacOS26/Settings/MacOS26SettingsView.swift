// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

@available(macOS 26, *)
struct MacOS26SettingsView: View {
    @ObservedObject var store: KeyBindingsStore
    @ObservedObject var general: GeneralSettingsStore
    @ObservedObject var loginItem: LoginItemManager
    @ObservedObject var vimBindings: VimBindingsStore
    @ObservedObject var privacy = PrivacyController()
    var distribution: Distribution = .current
    var clearHistory: () -> Void = {}
    var showWelcomeGuide: () -> Void = {}
    var exportDiagnostics: () async throws -> Void = {}
    var previewClipboard: (Double, Double) -> Void = { _, _ in }
    var cancelClipboardPreview: () -> Void = {}
    var buildInfo = AppBuildInfo.current

    @ObservedObject var appearance = AppearanceSettingsStore()
    @ObservedObject var updateChecker = UpdateChecker()
    @ObservedObject var search = SettingsSearchModel()
    @ObservedObject var developerMode = DeveloperModeStore()
    @State var exportingDiagnostics = false
    @State var showingDiagnosticsFailure = false
    @State var copySoundPlayer = CopySoundPlayer()
    @State var confirmingReset = false
    @State var resetCategories = Set(ShortcutResetCategory.allCases)
    @StateObject var resetUndo = ShortcutResetUndo()
    @State var confirmingClearHistory = false
    @State var cardSizeDraft = SizeSettingDraft()
    @State var tagSizeDraft = SizeSettingDraft()
    @State var systemColorScheme = AppearanceMode.systemColorScheme
    @State var detectionCoverageExpanded = false
    @State var temporarySessionsExpanded = false
    @State var selectedPage = SettingsPage.general
    @State private var selectedSection: SettingsSectionID?
    @FocusState private var focusedNavigation: NavigationDestination?
    @Namespace private var tabSelection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var accent: Color { .readableAccent(in: scheme, color: appearance.nsAccent) }
    private var navigationPrimary: Color { Color(white: scheme == .dark ? 0.92 : 0.10) }
    private var navigationSecondary: Color { Color(white: scheme == .dark ? 0.71 : 0.34) }

    private enum NavigationDestination: Hashable {
        case page(SettingsPage)
        case section(SettingsSectionID)
    }

    private var visiblePages: [SettingsPage] {
        SettingsPage.visiblePages(showsDeveloperTools: developerMode.showsTools)
    }

    var displayedPage: SettingsPage {
        visiblePages.contains(selectedPage) ? selectedPage : .about
    }

    private var sectionIDs: [SettingsSectionID] {
        displayedPage.sections(isProtected: privacy.isProtected, showsDeveloperTools: developerMode.showsTools)
    }

    var selectedSectionID: SettingsSectionID {
        if let selectedSection, sectionIDs.contains(selectedSection) { return selectedSection }
        return sectionIDs.first ?? .aboutApp
    }

    private var searchContext: SettingsSearchContext {
        SettingsSearchContext(
            isProtected: privacy.isProtected, checksForUpdates: distribution.checksForUpdates,
            customAccent: appearance.accentMode == .custom,
            normalHover: general.interactions.hover == .preview,
            privacyHover: general.privacyInteractions.hover == .preview,
            automaticProtection: privacy.automaticEnabled, vimEnabled: general.vimNavigation,
            showsDeveloperTools: developerMode.showsTools,
            showsPinnedWindowLayout: general.pinnedPresentation == .separate)
    }

    var body: some View {
        navigationLayout
            .modifier(MacOS26SettingsTitlebarClearance())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tint(accent)
            .overlay(alignment: .bottom) {
                if resetUndo.isPresented {
                    undoAccessory
                        .padding(20)
                        .transition(reduceMotion ? .identity : .opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: resetUndo.isPresented)
            .onChange(of: store.overrides) { _, _ in resetUndo.invalidateIfChanged(keys: store, vim: vimBindings) }
            .onChange(of: store.enabledGlobalActions) { _, _ in
                resetUndo.invalidateIfChanged(keys: store, vim: vimBindings)
            }
            .onChange(of: vimBindings.keys) { _, _ in resetUndo.invalidateIfChanged(keys: store, vim: vimBindings) }
            .onReceive(NotificationCenter.default.publisher(for: NSColor.systemColorsDidChangeNotification)) { _ in
                systemColorScheme = AppearanceMode.systemColorScheme
            }
            .onAppear { search.refresh(context: searchContext) }
            .onChange(of: searchContext) { _, context in
                if selectedPage != displayedPage {
                    selectedPage = displayedPage
                    selectedSection = nil
                    focusedNavigation = nil
                }
                if let selectedSection, !sectionIDs.contains(selectedSection) { self.selectedSection = nil }
                search.refresh(context: context)
            }
            .onChange(of: appearance.language) { _, _ in search.refresh(context: searchContext) }
            .alert(localized("Could not export logs"), isPresented: $showingDiagnosticsFailure) {
                Button(localized("OK"), role: .cancel) {}
            } message: {
                Text(localized("Choose a writable location and try exporting again."))
            }
            .onChange(of: search.navigationRevision) { _, _ in
                if let destination = search.destination { navigate(to: destination) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .settingsPageRequested)) { notification in
                if let destination = notification.object as? SettingsDestination {
                    search.navigate(to: destination)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .settingsWindowClosed)) { _ in
                store.endRecording()
                resetUndo.dismiss()
                cardSizeDraft.revert()
                tagSizeDraft.revert()
                cancelClipboardPreview()
                search.reset()
            }
    }

    private var sidebarMinimumWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        let longestLabel = visiblePages.map { ($0.label as NSString).size(withAttributes: [.font: font]).width }.max()
        let width = (longestLabel ?? 0) + 82
        let range = AppearanceSettingsStore.sidebarWidthRange
        return min(range.upperBound, max(range.lowerBound, width.rounded(.up)))
    }

    private var navigationLayout: some View {
        Group {
            if appearance.navigation == .top {
                topNavigation
            } else {
                GeometryReader { viewport in
                    MacOS26SettingsSidebar(
                        preferredWidth: $appearance.sidebarWidth, minimumWidth: sidebarMinimumWidth,
                        sidebar: sidebar.frame(height: viewport.size.height, alignment: .top).tint(accent),
                        detail:
                            detail
                            .modifier(MacOS26SettingsTitlebarClearance())
                            .frame(height: viewport.size.height, alignment: .top)
                            .tint(accent)
                    )
                    .frame(width: viewport.size.width, height: viewport.size.height)
                }
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                List {
                    ForEach(visiblePages) { page in
                        sidebarPage(page)
                            .id(NavigationDestination.page(page))
                        if displayedPage == page {
                            sidebarSections
                                .id(page)
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .onChange(of: selectedSectionID) { _, _ in
                    proxy.scrollTo(displayedPage)
                }
            }
            .frame(maxHeight: .infinity)

            MacOS26SettingsBrand(appearance: appearance, buildInfo: buildInfo, placement: .sidebar)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
    }

    private func sidebarPage(_ page: SettingsPage) -> some View {
        let selected = displayedPage == page
        return Button {
            select(page)
        } label: {
            Label {
                Text(page.label)
                    .font(.system(size: 14, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? navigationPrimary : navigationSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: page.symbol)
                    .foregroundStyle(selected ? accent : navigationSecondary)
                    .frame(width: 18)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focused($focusedNavigation, equals: .page(page))
        .onMoveCommand { movePage($0, from: page) }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("settingsPage.\(page.rawValue)")
        .listRowInsets(EdgeInsets(top: 0, leading: 9, bottom: 0, trailing: 10))
        .listRowBackground(
            Capsule().fill(selected ? accent.opacity(0.18) : .clear)
                .padding(.horizontal, 8))
    }

    private var sidebarSections: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(sectionIDs) { section in
                sidebarSection(section)
                    .anchorPreference(key: MacOS26SidebarSectionBounds.self, value: .bounds) { [section: $0] }
            }
        }
        .overlayPreferenceValue(MacOS26SidebarSectionBounds.self) { bounds in
            GeometryReader { geometry in
                if let anchor = bounds[selectedSectionID] {
                    let target = geometry[anchor]
                    Capsule()
                        .fill(navigationSecondary.opacity(0.28))
                        .frame(width: 2)
                        .padding(.vertical, 4)
                        .overlay(alignment: .top) {
                            Capsule()
                                .fill(accent)
                                .frame(width: 2, height: target.height)
                                .offset(y: target.minY)
                                .animation(
                                    reduceMotion || privacy.isProtected ? nil : .easeInOut(duration: 0.22),
                                    value: selectedSectionID)
                        }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 13, bottom: 0, trailing: 10))
        .listRowBackground(Color.clear)
    }

    private func sidebarSection(_ section: SettingsSectionID) -> some View {
        let selected = selectedSectionID == section
        return Button {
            selectedSection = section
        } label: {
            Text(section.title.localized)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? accent : navigationSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
                .padding(.vertical, 6)
                .frame(minHeight: 29)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focused($focusedNavigation, equals: .section(section))
        .onMoveCommand { moveSection($0, from: section) }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("settingsSection.\(section.rawValue)")
    }

    private var topNavigation: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                pageButtons.fixedSize(horizontal: true, vertical: false)
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) { pageButtons }
                        .frame(height: 30)
                        .scrollIndicators(.hidden)
                        .onChange(of: displayedPage, initial: true) { _, page in
                            proxy.scrollTo(page)
                        }
                }
            }
            .padding(4)
            .glassEffect(.regular, in: .capsule)
            .overlay {
                Capsule().strokeBorder(.primary.opacity(0.10))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .accessibilityElement(children: .contain)
            sectionTabs
            Divider()
            detail
        }
    }

    private var pageButtons: some View {
        HStack(spacing: 2) {
            ForEach(visiblePages) { page in
                let selected = displayedPage == page
                Button {
                    select(page)
                } label: {
                    Text(page.label)
                        .font(.system(size: 12, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? navigationPrimary : navigationSecondary)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background {
                            if selected {
                                Capsule().fill(accent.opacity(0.18))
                                    .matchedGeometryEffect(id: "pageSelection", in: tabSelection)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .focused($focusedNavigation, equals: .page(page))
                .onMoveCommand { movePage($0, from: page) }
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("settingsPage.\(page.rawValue)")
                .id(page)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: displayedPage)
    }

    private var sectionTabs: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    sectionButtons
                        .padding(.horizontal, 20)
                        .frame(minWidth: geometry.size.width)
                }
                .scrollIndicators(.hidden)
                .onChange(of: selectedSectionID, initial: true) { _, section in
                    proxy.scrollTo(section)
                }
            }
        }
        .frame(height: 30)
        .padding(.vertical, 6)
    }

    private var sectionButtons: some View {
        HStack(spacing: 6) {
            ForEach(sectionIDs) { section in
                let selected = selectedSectionID == section
                Button {
                    selectedSection = section
                } label: {
                    Text(section.title.localized)
                        .font(.system(size: 12, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? accent : navigationSecondary)
                        .fixedSize()
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                        .overlay(alignment: .bottom) {
                            if selected {
                                Capsule().fill(accent).frame(height: 2)
                                    .padding(.horizontal, 8)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .focused($focusedNavigation, equals: .section(section))
                .onMoveCommand { moveSection($0, from: section) }
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("settingsSection.\(section.rawValue)")
                .id(section)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(displayedPage == .about ? selectedSectionID.title.localized : displayedPage.title)
                    .font(.system(size: 24, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                if selectedSectionID != .aboutApp {
                    Text(
                        selectedSectionID == .licenses
                            ? localized("Read the licenses and notices included with WhiskyMac.")
                            : displayedPage.summary
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 14)

            if selectedSectionID == .licenses {
                MacOS26LegalSettings(search: search)
            } else {
                MacOS26SettingsForm(search: search, section: selectedSectionID) {
                    sectionContent(selectedSectionID)
                }
                .id(selectedSectionID)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .transaction { transaction in
            if privacy.isProtected { transaction.animation = nil; transaction.disablesAnimations = true }
        }
    }

    private var undoAccessory: some View {
        HStack(spacing: 12) {
            Text(localized("Shortcuts reset"))
            Button {
                resetUndo.undo(keys: store, vim: vimBindings)
            } label: {
                Label(localized("Undo reset"), systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .accessibilityHint(localized("Available for 5 seconds"))
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular.interactive())
        .accessibilityElement(children: .contain)
    }

    private func movePage(_ direction: MoveCommandDirection, from page: SettingsPage) {
        guard let nextPage = adjacent(visiblePages, to: page, direction: direction) else { return }
        focusedNavigation = .page(nextPage)
        select(nextPage)
    }

    private func moveSection(_ direction: MoveCommandDirection, from section: SettingsSectionID) {
        guard let nextSection = adjacent(sectionIDs, to: section, direction: direction) else { return }
        focusedNavigation = .section(nextSection)
        selectedSection = nextSection
    }

    private func adjacent<Item: Equatable>(_ items: [Item], to current: Item, direction: MoveCommandDirection) -> Item?
    {
        guard let index = items.firstIndex(of: current) else { return nil }
        let offset: Int
        switch (appearance.navigation, direction) {
        case (.top, .left), (.sidebar, .up): offset = -1
        case (.top, .right), (.sidebar, .down): offset = 1
        default: return nil
        }
        let nextIndex = index + offset
        return items.indices.contains(nextIndex) ? items[nextIndex] : nil
    }

    private func select(_ page: SettingsPage) {
        guard visiblePages.contains(page), page != selectedPage else { return }
        selectedPage = page
        selectedSection = nil
    }

    private func navigate(to destination: SettingsDestination) {
        guard
            let section = destination.resolvedSection(
                isProtected: privacy.isProtected, showsDeveloperTools: developerMode.showsTools)
        else { return }
        selectedPage = destination.page
        selectedSection = section
    }
}

@available(macOS 26, *)
private struct MacOS26SidebarSectionBounds: PreferenceKey {
    static let defaultValue: [SettingsSectionID: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [SettingsSectionID: Anchor<CGRect>],
        nextValue: () -> [SettingsSectionID: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, newer in newer })
    }
}

@available(macOS 26, *)
private struct MacOS26SettingsTitlebarClearance: ViewModifier {
    @State private var overlap: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(.top, overlap)
            .background {
                MacOS26SettingsContentBounds { overlap = $0 }
            }
    }
}

/// Keep the settings controls inside the AppKit window's unobscured content viewport.
@available(macOS 26, *)
private struct MacOS26SettingsContentBounds: NSViewRepresentable {
    let updateOverlap: (CGFloat) -> Void

    func makeNSView(context: Context) -> ContentBoundsView { ContentBoundsView() }

    func updateNSView(_ view: ContentBoundsView, context: Context) {
        view.updateOverlap = updateOverlap
        view.update()
    }

    final class ContentBoundsView: NSView {
        var updateOverlap: ((CGFloat) -> Void)?
        private var layoutObservation: NSKeyValueObservation?
        private var overlap: CGFloat?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            layoutObservation = window?.observe(\.contentLayoutRect, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.update() }
            }
            update()
        }

        override func layout() {
            super.layout()
            update()
        }

        override func setFrameOrigin(_ newOrigin: NSPoint) {
            super.setFrameOrigin(newOrigin)
            update()
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            update()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func update() {
            guard let window, !bounds.isEmpty else { return }
            let newOverlap = max(0, convert(bounds, to: nil).maxY - window.contentLayoutRect.maxY).rounded()
            guard newOverlap != overlap else { return }
            overlap = newOverlap
            DispatchQueue.main.async { [weak self] in
                guard let self, self.overlap == newOverlap else { return }
                self.updateOverlap?(newOverlap)
            }
        }
    }
}

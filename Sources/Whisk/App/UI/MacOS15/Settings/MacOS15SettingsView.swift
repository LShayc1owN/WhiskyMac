// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import ApplicationServices
import SwiftUI

/// The Settings window: general housekeeping plus one recorder per
/// keyboard action.
struct MacOS15SettingsView: View {
    private var typography: InterfaceTypography { appearance.interfaceTypography }

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
    @State private var exportingDiagnostics = false
    @State private var showingDiagnosticsFailure = false
    @State private var copySoundPlayer = CopySoundPlayer()
    @State private var confirmingReset = false
    @State private var resetCategories = Set(ShortcutResetCategory.allCases)
    @StateObject private var resetUndo = ShortcutResetUndo()
    @State private var confirmingClearHistory = false
    @State private var cardSizeDraft = SizeSettingDraft()
    @State private var tagSizeDraft = SizeSettingDraft()
    @State private var systemColorScheme = AppearanceMode.systemColorScheme
    @State private var selectedSection: SettingsSectionID?
    @State private var minimumSidebarWidth = AppearanceSettingsStore.sidebarWidthRange.lowerBound
    @State private var sidebarDragStart: CGFloat?
    @State private var detectionCoverageExpanded = false
    @State private var temporarySessionsExpanded = false
    @State var selectedPage = SettingsPage.general
    @SettingsAccessibility private var accessibility
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focusedNavigation: SettingsPage?
    @Namespace private var navigationNamespace
    @Namespace private var sidebarIndicatorNamespace
    @Namespace private var topSectionIndicatorNamespace

    private var accent: Color { .macOS15ReadableAccent(in: scheme, color: appearance.nsAccent) }

    private var visiblePages: [SettingsPage] {
        SettingsPage.visiblePages(showsDeveloperTools: developerMode.showsTools)
    }
    private var displayedPage: SettingsPage { visiblePages.contains(selectedPage) ? selectedPage : .about }
    private var sectionIDs: [SettingsSectionID] {
        displayedPage.sections(isProtected: privacy.isProtected, showsDeveloperTools: developerMode.showsTools)
    }
    private var selectedSectionID: SettingsSectionID {
        if let selectedSection, sectionIDs.contains(selectedSection) { return selectedSection }
        return sectionIDs[0]
    }
    private var selectedSectionIndex: Int {
        sectionIDs.firstIndex(of: selectedSectionID) ?? 0
    }
    private var searchContext: SettingsSearchContext {
        SettingsSearchContext(
            isProtected: privacy.isProtected, checksForUpdates: distribution.checksForUpdates,
            customAccent: appearance.accentMode == .custom,
            normalHover: general.interactions.hover == .preview,
            privacyHover: general.privacyInteractions.hover == .preview,
            automaticProtection: privacy.automaticEnabled, vimEnabled: general.vimNavigation,
            showsDeveloperTools: developerMode.showsTools,
            recognizesSecrets: general.secretRecognition.enabled)
    }

    var body: some View {
        ZStack {
            MacOS15SettingsWindowBackdrop()
                .ignoresSafeArea()
            VStack(spacing: 0) {
                if appearance.navigation == .top {
                    topPageNavigation
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    MacOS15SettingsDivider()
                    topNavigation
                        .transition(.opacity)
                    MacOS15SettingsDivider()
                }
                HStack(spacing: 0) {
                    if appearance.navigation == .sidebar {
                        MacOS15SettingsSidebarLayout(
                            preferredWidth: max(appearance.sidebarWidth, largeTextSidebarWidth)
                        ) {
                            sidebarNavigation
                            if typography.usesLargeLayout {
                                Color.clear.frame(height: 0).accessibilityHidden(true)
                            } else {
                                brandFooter
                            }
                            Color.clear
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                                .onGeometryChange(for: CGFloat.self) {
                                    $0.size.width
                                } action: { width in
                                    minimumSidebarWidth = width
                                }
                        }
                        .background(
                            scheme == .light ? Color.primary.opacity(0.045) : .clear,
                            ignoresSafeAreaEdges: .bottom
                        )
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                        sidebarResizeHandle
                    }

                    pageContent
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .interfaceType(typography)
        .environment(\.macOS15SettingsSearchHighlight, search.highlightedAnchor)
        .tint(accent)
        .onReceive(NotificationCenter.default.publisher(for: NSColor.systemColorsDidChangeNotification)) { _ in
            systemColorScheme = AppearanceMode.systemColorScheme
        }
        .frame(width: MacOS15SettingsWindowSize.width)
        .frame(
            minHeight: MacOS15SettingsWindowSize.minimumHeight, idealHeight: MacOS15SettingsWindowSize.height,
            maxHeight: MacOS15SettingsWindowSize.height
        )
        .animation(navigationAnimation, value: appearance.navigation)
        .animation(contentAnimation, value: selectedPage)
        .overlay(alignment: .bottom) {
            if resetUndo.isPresented {
                MacOS15ShortcutResetToast(undo: resetUndo, accent: accent) {
                    resetUndo.undo(keys: store, vim: vimBindings)
                }
                .padding(16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(accessibility.reduceMotion ? nil : .easeInOut(duration: 0.2), value: resetUndo.isPresented)
        .onChange(of: store.overrides) { _, _ in resetUndo.invalidateIfChanged(keys: store, vim: vimBindings) }
        .onChange(of: store.enabledGlobalActions) { _, _ in
            resetUndo.invalidateIfChanged(keys: store, vim: vimBindings)
        }
        .onChange(of: vimBindings.keys) { _, _ in resetUndo.invalidateIfChanged(keys: store, vim: vimBindings) }
        .onDisappear { resetUndo.dismiss() }
        .onAppear { search.refresh(context: searchContext) }
        .onChange(of: searchContext) { _, context in
            if selectedPage != displayedPage {
                selectedPage = displayedPage
                selectedSection = .aboutApp
                focusedNavigation = nil
            }
            if let selectedSection, !sectionIDs.contains(selectedSection) { self.selectedSection = sectionIDs.first }
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
            resetUndo.dismiss()
            cardSizeDraft.revert()
            tagSizeDraft.revert()
            cancelClipboardPreview()
            search.reset()
        }
    }

    private var topPageNavigation: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(visiblePages) { page in
                            Text(page.label)
                                .font(typography.font(size: 12, weight: selectedPage == page ? .semibold : .medium))
                                .foregroundStyle(selectedPage == page ? Color.primary : Color.secondary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background {
                                    if selectedPage == page { navigationSelection() }
                                }
                                .beButton { select(page) }
                                .buttonStyle(MacOS15SettingsHoverButtonStyle(isSelected: selectedPage == page))
                                .focused($focusedNavigation, equals: page)
                                .onMoveCommand { moveNavigation($0, from: page) }
                                .accessibilityValue(selectedPage == page ? localized("Selected") : "")
                                .accessibilityAddTraits(selectedPage == page ? .isSelected : [])
                                .id(page)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minWidth: geometry.size.width, alignment: .leading)
                }
                .defaultScrollAnchor(.leading)
                .onChange(of: displayedPage, initial: true) { _, page in
                    proxy.scrollTo(page)
                }
            }
        }
        .frame(height: max(34, typography.lineHeight(12) + 18))
    }

    private var topNavigation: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(sectionIDs) { section in
                        Text(section.title.localized)
                            .font(typography.font(size: 12, weight: selectedSectionID == section ? .semibold : .medium))
                            .foregroundStyle(selectedSectionID == section ? Color.primary : Color.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .overlay(alignment: .bottom) {
                                if selectedSectionID == section {
                                    Capsule()
                                        .fill(accent)
                                        .frame(height: 2)
                                        .padding(.horizontal, 8)
                                        .matchedGeometryEffect(id: selectedPage, in: topSectionIndicatorNamespace)
                                        .accessibilityHidden(true)
                                }
                            }
                            .beButton { selectedSection = section }
                            .buttonStyle(MacOS15SettingsHoverButtonStyle(isSelected: selectedSectionID == section))
                            .id(section)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                .animation(
                    accessibility.reduceMotion || privacy.isProtected ? nil : .easeInOut(duration: 0.22),
                    value: selectedSectionID)
            }
            .onChange(of: selectedSectionID, initial: true) { _, section in
                proxy.scrollTo(section)
            }
        }
    }

    private var brandFooter: some View {
        MacOS15SettingsBrandView(appearance: appearance, buildInfo: buildInfo)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            .layoutPriority(1)
    }

    private var sidebarNavigation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(visiblePages) { page in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: page.symbol)
                                .font(typography.font(size: 14))
                                .frame(width: typography.room(18))
                            Text(page.label)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .font(typography.font(size: 14, weight: selectedPage == page ? .semibold : .regular))
                        .foregroundStyle(selectedPage == page ? accent : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background {
                            if selectedPage == page {
                                RoundedRectangle(cornerRadius: MacOS15SettingsSurface.controlCornerRadius)
                                    .fill(appearance.accent.opacity(0.18))
                            }
                        }
                        .beButton { select(page) }
                        .buttonStyle(MacOS15SettingsHoverButtonStyle(isSelected: selectedPage == page))
                        .focused($focusedNavigation, equals: page)
                        .onMoveCommand { moveNavigation($0, from: page) }
                        .accessibilityValue(selectedPage == page ? localized("Selected") : "")
                        .accessibilityAddTraits(selectedPage == page ? .isSelected : [])
                        if selectedPage == page {
                            sidebarSections
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    if typography.usesLargeLayout {
                        brandFooter
                    }
                }
                .padding(12)
            }
            .onChange(of: selectedSectionID) { _, section in
                proxy.scrollTo(section)
            }
        }
    }

    private var largeTextSidebarWidth: CGFloat {
        guard typography.usesLargeLayout else { return 0 }
        let language = AppLocalization.interfaceLocale.language.languageCode?.identifier
        guard language != "ja", language != "zh" else { return 0 }

        func longestWord(in labels: [String], size: CGFloat) -> CGFloat {
            let font = NSFont.systemFont(ofSize: typography.points(size), weight: .semibold)
            return labels.flatMap { $0.split(whereSeparator: \.isWhitespace) }
                .map { (String($0) as NSString).size(withAttributes: [.font: font]).width }
                .max() ?? 0
        }

        let pageWidth = longestWord(in: visiblePages.map(\.label), size: 14) + 54 + typography.room(18)
        let sectionWidth = longestWord(in: sectionIDs.map { $0.title.localized }, size: 12) + 54
        return min(AppearanceSettingsStore.sidebarWidthRange.upperBound, ceil(max(pageWidth, sectionWidth)))
    }

    private var sidebarResizeHandle: some View {
        let visibleWidth = max(appearance.sidebarWidth, minimumSidebarWidth, largeTextSidebarWidth)
        return Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.55))
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: 12)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let start = sidebarDragStart ?? visibleWidth
                                sidebarDragStart = start
                                resizeSidebar(to: start + value.translation.width)
                            }
                            .onEnded { _ in sidebarDragStart = nil }
                    )
            }
            .accessibilityElement()
            .accessibilityLabel(localized("Sidebar width"))
            .accessibilityAdjustableAction { direction in
                let delta: CGFloat = direction == .increment ? 12 : -12
                resizeSidebar(to: visibleWidth + delta)
            }
    }

    private func resizeSidebar(to width: CGFloat) {
        let boundedWidth = min(
            AppearanceSettingsStore.sidebarWidthRange.upperBound, max(minimumSidebarWidth, largeTextSidebarWidth, width)
        )
        if boundedWidth != appearance.sidebarWidth { appearance.sidebarWidth = boundedWidth }
    }

    private var sidebarSections: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(sectionIDs) { section in
                HStack {
                    Text(section.title.localized)
                    Spacer(minLength: 0)
                }
                .font(typography.font(size: 12, weight: selectedSectionID == section ? .semibold : .regular))
                .foregroundStyle(selectedSectionID == section ? Color.primary : Color.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background {
                    if selectedSectionID == section {
                        RoundedRectangle(cornerRadius: MacOS15SettingsSurface.controlCornerRadius)
                            .fill(Color.primary.opacity(0.08))
                    }
                }
                .overlay(alignment: .leading) {
                    if selectedSectionID == section {
                        Rectangle()
                            .fill(accent)
                            .frame(width: 2)
                            .matchedGeometryEffect(id: selectedPage, in: sidebarIndicatorNamespace)
                            .offset(x: -12)
                            .accessibilityHidden(true)
                    }
                }
                .beButton { selectedSection = section }
                .buttonStyle(MacOS15SettingsHoverButtonStyle(isSelected: selectedSectionID == section))
                .id(section)
            }
        }
        .padding(.leading, 12)
        .animation(
            accessibility.reduceMotion || privacy.isProtected ? nil : .easeInOut(duration: 0.22),
            value: selectedSectionID
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.secondary.opacity(0.28))
                .frame(width: 2)
                .padding(.vertical, 6)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func navigationSelection() -> some View {
        RoundedRectangle(cornerRadius: MacOS15SettingsSurface.controlCornerRadius, style: .continuous)
            .fill(Color.primary.opacity(0.09))
            .overlay(
                RoundedRectangle(cornerRadius: MacOS15SettingsSurface.controlCornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.5)
            )
            .matchedGeometryEffect(id: "selection", in: navigationNamespace)
    }

    private var pageContent: some View {
        MacOS15SettingsSearchScrollView(search: search, section: selectedSectionID) {
            VStack(alignment: .leading, spacing: 0) {
                pageHeading
                if displayedPage == .about {
                    if selectedSectionID == .licenses {
                        MacOS15LegalSettingsView()
                    } else {
                        MacOS15AboutSettingsView(
                            section: selectedSectionID, distribution: distribution, buildInfo: buildInfo,
                            updateChecker: updateChecker,
                            general: general, developerMode: developerMode)
                    }
                } else {
                    settingsForm
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(selectedSectionID)
        .transition(pageTransition)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private var pageHeading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(contentTitle)
                .font(typography.font(size: 24, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if selectedSectionID != .aboutApp {
                Text(contentSummary)
                    .font(typography.font(.callout))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 14)
    }

    private var contentTitle: String {
        guard displayedPage == .about else { return displayedPage.title }
        switch selectedSectionID {
        case .aboutApp: return localized("About this App")
        case .aboutDeveloper: return localized("About the developer")
        default: return localized("Licenses and notices")
        }
    }

    private var contentSummary: String {
        selectedSectionID == .licenses
            ? localized("Read the licenses and notices included with WhiskyMac.") : selectedPage.summary
    }

    private var pageTransition: AnyTransition {
        accessibility.reduceMotion
            ? .identity
            : .asymmetric(
                insertion: .opacity.combined(with: .offset(y: 6)), removal: .identity)
    }

    private var navigationAnimation: Animation? {
        accessibility.reduceMotion ? nil : .easeInOut(duration: 0.24)
    }

    private var contentAnimation: Animation? {
        accessibility.reduceMotion ? nil : .easeInOut(duration: 0.2)
    }

    private func moveNavigation(_ direction: MoveCommandDirection, from page: SettingsPage) {
        let pages = visiblePages
        guard let index = pages.firstIndex(of: page) else { return }
        let delta: Int
        switch (appearance.navigation, direction) {
        case (.top, .left), (.sidebar, .up): delta = -1
        case (.top, .right), (.sidebar, .down): delta = 1
        default: return
        }
        let next = pages[min(pages.count - 1, max(0, index + delta))]
        focusedNavigation = next
        select(next)
    }

    private func select(_ page: SettingsPage) {
        guard visiblePages.contains(page), selectedPage != page else { return }
        selectedSection = nil
        selectedPage = page
    }

    private func navigate(to destination: SettingsDestination) {
        guard
            let section = destination.resolvedSection(
                isProtected: privacy.isProtected, showsDeveloperTools: developerMode.showsTools)
        else { return }
        // A search jump lays out the target before scrolling. Animating the page
        // replacement can leave the scroll request attached to the outgoing form.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedPage = destination.page
            selectedSection = section
        }
    }

    private var settingsForm: some View {
        Group(sections: sections) { pageSections in
            if displayedPage == .privacy || displayedPage == .appearance {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(pageSections) { section in
                        MacOS15SettingsSurfaceGroup(section: section)
                    }
                }
                .transition(pageTransition)
            } else if !pageSections.isEmpty {
                MacOS15SettingsSurfaceGroup(
                    section: pageSections[min(selectedSectionIndex, pageSections.count - 1)]
                )
                .transition(pageTransition)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .multilineTextAlignment(.leading)
        .animation(contentAnimation, value: appearance.accentMode)
        .animation(contentAnimation, value: general.vimNavigation)
        .animation(contentAnimation, value: general.interactions.hover)
        .animation(contentAnimation, value: general.privacyInteractions.hover)
        .animation(contentAnimation, value: selectedSectionID)
        .transaction { transaction in
            if privacy.isProtected { transaction.animation = nil; transaction.disablesAnimations = true }
        }
        .toggleStyle(MacOS15SettingsToggleStyle())
    }

    private func explanationDisclosure<Content: View>(
        _ title: String, isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup(title, isExpanded: isExpanded, content: content)
            .disclosureGroupStyle(MacOS15DisclosureRowStyle(animation: contentAnimation))
    }

    private func requestDiagnosticsExport() {
        guard developerMode.showsTools, !exportingDiagnostics else { return }
        exportingDiagnostics = true
        Task { @MainActor in
            defer { exportingDiagnostics = false }
            do {
                try await exportDiagnostics()
            } catch {
                if developerMode.showsTools { showingDiagnosticsFailure = true }
            }
        }
    }

    @ViewBuilder
    private var sections: some View {
        switch displayedPage {
        case .debug:
            Section {
                Button(localized("Show first-launch guide"), systemImage: "book") {
                    if developerMode.showsTools { showWelcomeGuide() }
                }
                .macOS15SettingsAction()
                .macOS15SettingsSearchAnchor("showWelcomeGuide")
                Button(localized("Export logs…"), systemImage: "square.and.arrow.up", action: requestDiagnosticsExport)
                    .macOS15SettingsAction()
                    .disabled(exportingDiagnostics)
                    .macOS15SettingsSearchAnchor("exportDiagnostics")
            } header: {
                Text(localized("Debug tools"))
            } footer: {
                Text(localized("Reopens the welcome guide from the beginning without resetting its completion status."))
            }
        case .general:
            generalSection
            copySoundSection
        case .appearance:
            switch selectedSectionID {
            case .statusIcons: statusIconsSection
            case .navigation: navigationSection
            case .colors: displayAndThemeSections
            case .cards: cardsSection
            case .filterTags:
                filterTagsSection
                filterCategoryOrderSection
            default: EmptyView()
            }
        case .interactions:
            interactionSection
            pinnedItemsSection
        case .history:
            recordingSettingsSection
            storageManagementSection
        case .privacy:
            switch selectedSectionID {
            case .screenSharingProtection: screenSharingProtectionSection
            case .sensitiveAccess: sensitiveAccessSection
            case .secretRecognition: secretRecognitionSection
            case .network: networkSection
            default: EmptyView()
            }
        case .shortcuts:
            shortcutsSection(global: true)
            shortcutsSection(global: false)
            vimSection
            restoreSection
        case .about:
            Section {
                Color.clear.frame(height: 0)
            } header: {
                Text(localized("About this App"))
            }
            Section {
                Color.clear.frame(height: 0)
            } header: {
                Text(localized("About the developer"))
            }
            Section {
                Color.clear.frame(height: 0)
            } header: {
                Text(localized("Licenses and notices"))
            }
        }
    }

    private var statusIconsSection: some View {
        Section {
            MacOS15StatusSymbolPickerRow(
                title: localized("Default mode icon"), selection: $appearance.defaultStatusSymbol,
                defaultName: AppSymbol.defaultStatusName
            )
            .macOS15SettingsSearchAnchor("defaultIcon")
            MacOS15StatusSymbolPickerRow(
                title: localized("Privacy mode icon"), selection: $appearance.privacyStatusSymbol,
                defaultName: AppSymbol.defaultPrivacyName
            )
            .macOS15SettingsSearchAnchor("privacyIcon")
        } header: {
            Text(localized("Menu bar icons"))
        }
    }

    private var navigationSection: some View {
        Section {
            MacOS15SettingsPicker(localized("Settings layout"), selection: $appearance.navigation, display: \.label) {
                ForEach(SettingsNavigation.allCases) { option in Text(option.label).tag(option) }
            }
            .macOS15SettingsSearchAnchor("navigation")
        } header: {
            Text(localized("Settings navigation"))
        }
    }

    @ViewBuilder private var displayAndThemeSections: some View {
        Section {
            MacOS15SettingsPicker(
                localized("Settings window appearance"), selection: $appearance.settingsAppearance, display: \.label
            ) {
                ForEach(AppearanceMode.allCases) { option in Text(option.label).tag(option) }
            }
            .macOS15SettingsSearchAnchor("settingsAppearance")
            MacOS15SettingsPicker(
                localized("Clipboard appearance"), selection: $appearance.clipboardAppearance, display: \.label
            ) {
                ForEach(AppearanceMode.allCases) { option in Text(option.label).tag(option) }
            }
            .macOS15SettingsSearchAnchor("clipboardAppearance")
        } header: {
            Text(localized("Light and dark appearance"))
        }
        Section {
            MacOS15SettingsPicker(localized("Accent color"), selection: $appearance.accentMode, display: \.label) {
                ForEach(AccentMode.allCases) { option in Text(option.label).tag(option) }
            }
            .macOS15SettingsSearchAnchor("accent")
            if appearance.accentMode == .custom {
                HStack {
                    Text(localized("Custom color"))
                    Spacer()
                    ColorPicker(
                        localized("Custom color"),
                        selection: Binding(
                            get: { Color(nsColor: appearance.customAccent.nsColor) },
                            set: { appearance.customAccent = AccentRGB(NSColor($0)) }), supportsOpacity: false
                    )
                    .labelsHidden()
                }
                .macOS15SettingsSearchAnchor("customAccent")
            }
        } header: {
            Text(localized("Theme color"))
        } footer: {
            Text(localized("The accent color also highlights the selected clipboard card."))
        }
        interfaceTextSection
    }

    private var interfaceTextSection: some View {
        let range = InterfaceTypography.percentRange
        let size = Binding(
            get: { Double(appearance.interfaceTypography.percent) },
            set: { appearance.setInterfaceFontPercent(Int($0.rounded())) })
        return Section {
            HStack(spacing: 12) {
                Slider(value: size, in: Double(range.lowerBound)...Double(range.upperBound), step: 5) {
                    Text(localized("Interface font size"))
                }
                .labelsHidden()
                Text((size.wrappedValue / 100).formatted(.percent.locale(AppLocalization.interfaceLocale)))
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 50, alignment: .trailing)
            }
            .macOS15SettingsSearchAnchor("interfaceFontSize")
            Button(localized("Restore default size")) {
                appearance.setInterfaceFontPercent(InterfaceTypography.standard.percent)
            }
            .macOS15SettingsAction()
            .disabled(appearance.interfaceTypography.isStandard)
            Toggle(
                localized("Apply interface font size to plain text"),
                isOn: Binding(
                    get: { appearance.interfaceTypography.appliesToPlainText },
                    set: appearance.setPlainTextFollowsInterface)
            )
            .macOS15SettingsSearchAnchor("interfaceFontPlainText")
        } header: {
            Text(localized("Interface font size"))
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(localized("Use Card size to resize clipboard cards."))
                Text(localized("Rich text keeps its original font sizes."))
            }
        }
    }

    private var cardsSection: some View {
        Section {
            MacOS15SizeSettingEditor(
                title: localized("Card size"), savedValue: general.cardSide,
                defaultValue: GeneralSettingsStore.defaultCardSide, range: GeneralSettingsStore.cardSideRange,
                draft: $cardSizeDraft, save: general.setCardSide, previewOnScreen: previewSizingOnScreen
            ) {
                MacOS15CardSizePreviewViewport(side: CGFloat(cardSizeDraft.value(saved: general.cardSide)))
                    .environment(\.colorScheme, appearance.clipboardAppearance.colorScheme ?? systemColorScheme)
            }
            .macOS15SettingsSearchAnchor("cardSize")
        } header: {
            Text(localized("Clipboard cards"))
        } footer: {
            Text(localized("Changes are saved only when you choose Save current setting."))
        }
    }

    private var filterTagsSection: some View {
        Section {
            MacOS15SizeSettingEditor(
                title: localized("Tag size"), savedValue: general.filterTagScale,
                defaultValue: GeneralSettingsStore.defaultFilterTagScale,
                range: GeneralSettingsStore.filterTagScaleRange,
                usesPercentage: true, draft: $tagSizeDraft, save: general.setFilterTagScale,
                previewOnScreen: previewSizingOnScreen
            ) {
                MacOS15FilterTagSizePreview(scale: tagSizeDraft.value(saved: general.filterTagScale))
                    .environment(\.colorScheme, appearance.clipboardAppearance.colorScheme ?? systemColorScheme)
            }
            .macOS15SettingsSearchAnchor("filterTagSize")
        } header: {
            Text(localized("Filter tags"))
        } footer: {
            Text(localized("Changes are saved only when you choose Save current setting."))
        }
    }

    private var filterCategoryOrderSection: some View {
        Section {
            MacOS15FilterCategoryOrderEditor(
                settings: general, previewScheme: appearance.clipboardAppearance.colorScheme ?? systemColorScheme
            )
            .macOS15SettingsSearchAnchor("filterCategoryOrder")
        } header: {
            Text(localized("Category tag order"))
        }
    }

    private func previewSizingOnScreen() {
        previewClipboard(
            cardSizeDraft.value(saved: general.cardSide), tagSizeDraft.value(saved: general.filterTagScale))
    }

    private var copySoundSection: some View {
        Section {
            Toggle(localized("Play a sound when a new copy is recorded"), isOn: $general.copySound.onCapture)
                .macOS15SettingsSearchAnchor("captureSound")
            Toggle(localized("Play a sound when copying from history"), isOn: $general.copySound.onHistoryCopy)
                .macOS15SettingsSearchAnchor("historySound")
            MacOS15SettingsPicker(localized("Copy sound"), selection: $general.copySound.sound, display: \.label) {
                ForEach(CopySound.Collection.allCases) { collection in
                    Section(collection.rawValue) {
                        ForEach(collection.sounds) { sound in Text(sound.label).tag(sound) }
                    }
                }
            }
            .macOS15SettingsSearchAnchor("copySound")
            HStack {
                Text(localized("Sound volume"))
                Slider(value: $general.copySound.volume, in: 0...1)
                    .accessibilityLabel(localized("Sound volume"))
                Button(localized("Preview sound"), systemImage: "play.fill") {
                    copySoundPlayer.preview(general.copySound)
                }
                .macOS15SettingsAction()
            }
            .macOS15SettingsSearchAnchor("volume")
        } header: {
            Text(localized("Sounds and effects"))
        } footer: {
            Text(
                localized(
                    "Paste actions stay silent. Automatic sounds are muted during Privacy Mode; sensitive and excluded copies stay silent."
                ))
        }
    }

    @ViewBuilder private var generalSection: some View {
        Section {
            Toggle(
                localized("Launch WhiskyMac at login"),
                isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) })
            )
            .toggleStyle(MacOS15SettingsToggleStyle())
            .macOS15SettingsSearchAnchor("launch")
            if let error = loginItem.lastError {
                Text(error)
                    .font(typography.font(.caption))
                    .foregroundStyle(.red)
            }
            if distribution.checksForUpdates {
                Toggle(localized("Check for updates at launch"), isOn: $general.checkForUpdates)
                    .toggleStyle(MacOS15SettingsToggleStyle())
                    .macOS15SettingsSearchAnchor("startupUpdates")
            }
            Toggle(localized("Lightweight mode"), isOn: $general.lightweightMode)
                .toggleStyle(MacOS15SettingsToggleStyle())
                .macOS15SettingsSearchAnchor("lightweightMode")
        } header: {
            Text(localized("Startup and loading"))
        } footer: {
            Text(
                localized(
                    "Lightweight mode loads thumbnails only as needed when you open the clipboard panel. Closing the panel clears the thumbnail cache to reduce memory use."
                ))
        }
        Section {
            MacOS15SettingsPicker(
                localized("Menu bar icon click"), selection: $appearance.statusClick, display: \.label
            ) {
                ForEach(StatusClickAction.allCases) { option in Text(option.label).tag(option) }
            }
            .macOS15SettingsSearchAnchor("statusClick")
            MacOS15SettingsPicker(localized("Dock icon"), selection: $appearance.dockIcon, display: \.label) {
                ForEach(DockIconMode.allCases) { option in Text(option.label).tag(option) }
            }
            .macOS15SettingsSearchAnchor("dockIcon")
        } header: {
            Text(localized("Menu bar and Dock"))
        } footer: {
            Text(
                localized(
                    "Right-click always opens the menu. Follow windows shows the Dock icon for Settings and welcome windows only."
                ))
        }
        Section {
            MacOS15SettingsPicker(localized("Language"), selection: $appearance.language, display: \.label) {
                ForEach(AppLanguage.allCases) { option in Text(option.label).tag(option) }
            }
            .macOS15SettingsSearchAnchor("language")
        } header: {
            Text(localized("Language"))
        }
    }

    @ViewBuilder private var interactionSection: some View {
        Section {
            MacOS15SettingsPicker(localized("Filter trigger"), selection: $general.appFilterTrigger, display: \.label) {
                ForEach(AppFilterTrigger.allCases) { trigger in Text(trigger.label).tag(trigger) }
            }
            .macOS15SettingsSearchAnchor("filterTrigger")
        } header: {
            Text(localized("Filters"))
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(localized("Use the tags above the clipboard cards to filter after opening the clipboard."))
                Text(
                    localized(
                        "· With hover filtering, pause the pointer over a tag to show the matching cards. You can still click tags to combine multiple filters."
                    ))
            }
        }
        interactionModeSection(title: localized("Normal mode"), bindings: $general.interactions, privacyMode: false)
        interactionModeSection(
            title: localized("Privacy mode"), bindings: $general.privacyInteractions, privacyMode: true)
    }

    private func interactionModeSection(title: String, bindings: Binding<InteractionBindings>, privacyMode: Bool)
        -> some View
    {
        Section {
            interactionPicker(
                localized("Single click"), key: \.singleClick, bindings: bindings, privacyMode: privacyMode
            )
            .macOS15SettingsSearchAnchor(privacyMode ? "private.single" : "normal.single")
            interactionPicker(
                localized("Double click"), key: \.doubleClick, bindings: bindings, privacyMode: privacyMode
            )
            .macOS15SettingsSearchAnchor(privacyMode ? "private.double" : "normal.double")
            interactionPicker(localized("Right click"), key: \.rightClick, bindings: bindings, privacyMode: privacyMode)
                .macOS15SettingsSearchAnchor(privacyMode ? "private.right" : "normal.right")
            Text(localized("Hover preview")).font(typography.font(.caption)).foregroundStyle(.secondary)
            MacOS15SettingsPicker(
                localized("Hover after a short delay"), selection: bindings.hover,
                display: { action in
                    privacyMode && action == .preview ? localized("Reveal a small area") : action.label
                }
            ) {
                Text(CardAction.none.label).tag(CardAction.none)
                Text(privacyMode ? localized("Reveal a small area") : CardAction.preview.label).tag(CardAction.preview)
            }
            .macOS15SettingsSearchAnchor(privacyMode ? "private.hover" : "normal.hover")
            if bindings.wrappedValue.hover == .preview {
                HStack {
                    Text(localized("Hover delay (seconds)"))
                    Spacer()
                    TextField("", value: bindings.hoverDelay, format: .number.precision(.fractionLength(1)))
                        .textFieldStyle(.plain)
                        .font(typography.font(.body).monospacedDigit())
                        .multilineTextAlignment(.trailing).frame(width: typography.room(48))
                    Stepper("", value: bindings.hoverDelay, in: 0.1...5, step: 0.1).labelsHidden()
                }
                .macOS15SettingsSearchAnchor(privacyMode ? "private.delay" : "normal.delay")
            }
            if privacyMode {
                spotlightControls
            }
        } header: {
            Text(title)
        } footer: {
            if privacyMode {
                Text(
                    localized(
                        "Click to copy or paste. When you turn on privacy protection, use the card menu to show the full card or hover to see a small area. Protection triggered by detection keeps cards hidden."
                    ))
            } else {
                Text(localized("Pasting needs Accessibility permission. Without it, use Command-V after copying."))
                Text(localized("Pause over a card to preview it without clicking."))
            }
        }
    }

    private func interactionPicker(
        _ title: String, key: WritableKeyPath<InteractionBindings, CardAction>,
        bindings: Binding<InteractionBindings>, privacyMode: Bool
    ) -> some View {
        func display(_ action: CardAction) -> String {
            if privacyMode && action == .preview {
                return key == \.rightClick ? localized("Show card") : localized("Reveal a small area")
            }
            return action.label
        }
        return MacOS15SettingsPicker(
            title,
            selection: Binding(
                get: { bindings.wrappedValue[keyPath: key] },
                set: { bindings.wrappedValue[keyPath: key] = $0 }
            ), display: display
        ) {
            ForEach(CardAction.allCases.filter { !privacyMode || ($0 != .edit && $0 != .split) }, id: \.rawValue) {
                action in
                Text(display(action)).tag(action)
            }
        }
    }

    @ViewBuilder private var screenSharingProtectionSection: some View {
        Section {
            Toggle(
                localized("Privacy protection"),
                isOn: Binding(get: { privacy.isManuallyProtected }, set: { privacy.setProtected($0) })
            )
            .macOS15SettingsSearchAnchor("manualPrivacy")
            Toggle(
                localized("Turn on protection when screen sharing is detected"),
                isOn: Binding(get: { privacy.automaticEnabled }, set: { privacy.setAutomaticEnabled($0) })
            )
            .macOS15SettingsSearchAnchor("automaticPrivacy")
            sharingProtectionStatus
            explanationDisclosure(localized("Detection coverage"), isExpanded: $detectionCoverageExpanded) {
                Text(
                    localized(
                        "Uses Accessibility to detect Zoom and Teams sharing toolbars. Detection may vary by app version and language. System screen sharing, remote desktop, screen recording and browser tabs are outside its scope. Turn on privacy protection before sharing sensitive content."
                    )
                )
                .font(typography.font(.callout))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .macOS15SettingsSearchAnchor("detection")
            if privacy.automaticEnabled {
                HStack(spacing: 10) {
                    SettingsRowLabel(
                        localized("Allow Accessibility for toolbar detection…"), symbol: "accessibility",
                        tint: accent
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right")
                        .font(typography.font(.caption).weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
                .beButton {
                    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                    _ = AXIsProcessTrustedWithOptions(options)
                }
                .buttonStyle(MacOS15SettingsHoverButtonStyle())
                .macOS15SettingsSearchAnchor("accessibility")
            }
        } header: {
            Text(SettingsSectionID.screenSharingProtection.title.localized)
        }

        Section {
            Toggle(localized("Allow search in Privacy Mode"), isOn: $privacy.allowSearchWhileProtected)
                .macOS15SettingsSearchAnchor("privacySearch")
            Toggle(
                localized("Allow type and tag filtering in Privacy Mode"), isOn: $privacy.allowFilteringWhileProtected
            )
            .macOS15SettingsSearchAnchor("privacyFilters")
            Toggle(localized("Allow app filtering in Privacy Mode"), isOn: $privacy.allowAppFilteringWhileProtected)
                .macOS15SettingsSearchAnchor("privacyAppFilters")
            Toggle(
                localized("Allow Handoff filtering in Privacy Mode"), isOn: $privacy.allowHandoffFilteringWhileProtected
            )
            .macOS15SettingsSearchAnchor("privacyHandoffFilters")
            Text(
                localized(
                    "App filters show application names in the filter bar, independently of source labels on cards. Clipboard content stays hidden."
                )
            )
            .font(typography.font(.caption))
            .foregroundStyle(.secondary)
            Toggle(localized("Show source apps in Privacy Mode"), isOn: $privacy.showSourceAppsWhileProtected)
                .macOS15SettingsSearchAnchor("privacySources")
        } header: {
            Text(localized("Protection mode options"))
        } footer: {
            Text(
                localized(
                    "These options apply whenever protection is on. Search terms and allowed app names are visible on screen and accessible to assistive technologies. Clipboard content stays hidden. Protection triggered by detection blocks hover reveals."
                )
            )
        }
    }

    private var sharingProtectionStatus: some View {
        let hasNoDetectedToolbar =
            privacy.automaticEnabled && !privacy.isProtected && privacy.report.state == .clearWithinCoverage
        return privacyNotice(
            symbol: privacy.isProtected ? "lock.shield.fill" : "shield",
            tint: privacy.isProtected ? accent : .secondary,
            fill: privacy.isProtected ? accent.opacity(0.10) : Color.primary.opacity(0.05),
            showsDashedBorder: hasNoDetectedToolbar
        ) {
            Text(privacy.statusText)
            if hasNoDetectedToolbar {
                Text(
                    localized(
                        "Automatic detection is limited. Turn on privacy protection before sharing sensitive content.")
                )
                .font(typography.font(.caption))
                .foregroundStyle(.secondary)
            }
        }
    }

    private func privacyNotice<Content: View>(
        symbol: String, tint: Color, fill: Color = Color.primary.opacity(0.05),
        showsDashedBorder: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(typography.font(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: typography.room(22))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4, content: content)
                .font(typography.font(.callout).weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(fill, in: shape)
        .overlay {
            if showsDashedBorder {
                shape.strokeBorder(
                    Color.secondary.opacity(0.7), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [4, 3])
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    private func spotlightPoints(_ value: Double) -> String {
        let points = Int(value)
        return localized("\(points) pt")
    }

    private var spotlightControls: some View {
        Group {
            Text(localized("Hover reveal area"))
                .font(typography.font(.subheadline).weight(.semibold))
                .padding(.top, 20)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(localized("Diameter"))
                    Spacer()
                    MacOS15NumericField(
                        title: localized("Diameter"), value: $privacy.spotlight.diameter, format: { String(Int($0)) },
                        parse: SpotlightPreferences.points(from:))
                    Text(localized("pt")).foregroundStyle(.secondary)
                }
                Slider(value: $privacy.spotlight.diameter, in: SpotlightPreferences.diameterRange, step: 10)
                    .accessibilityLabel(localized("Diameter"))
                    .accessibilityValue(spotlightPoints(privacy.spotlight.diameter))
            }
            .macOS15SettingsSearchAnchor("diameter")
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(localized("Edge blur radius"))
                    Spacer()
                    MacOS15NumericField(
                        title: localized("Edge blur radius"), value: $privacy.spotlight.blurRadius,
                        format: { String(Int($0)) }, parse: SpotlightPreferences.points(from:))
                    Text(localized("pt")).foregroundStyle(.secondary)
                }
                Slider(value: $privacy.spotlight.blurRadius, in: privacy.spotlight.blurRange, step: 1)
                    .accessibilityLabel(localized("Edge blur radius"))
                    .accessibilityValue(spotlightPoints(privacy.spotlight.blurRadius))
            }
            .macOS15SettingsSearchAnchor("blur")
            Button(localized("Restore default values"), systemImage: "arrow.counterclockwise") {
                privacy.spotlight = SpotlightPreferences()
            }
            .macOS15SettingsAction()
            .disabled(privacy.spotlight == SpotlightPreferences())
            .macOS15SettingsSearchAnchor("resetSpotlight")

            Text(
                localized(
                    "Applies when you turn on privacy protection and set Hover to Preview. Blur softens the edge of the visible area. Screen recordings can capture that area. Protection triggered by detection keeps all content hidden."
                )
            )
            .font(typography.font(.caption)).foregroundStyle(.secondary)
        }
    }

    private var networkSection: some View {
        Section {
            Toggle(localized("Fetch link previews"), isOn: $general.linkPreviews)
                .toggleStyle(MacOS15SettingsToggleStyle())
                .macOS15SettingsSearchAnchor("linkPreviews")
        } header: {
            Text(localized("Online content"))
        } footer: {
            Text(localized("A copied link is looked up once for its title and image. Off, nothing leaves this Mac."))
        }
    }

    private var recordingSettingsSection: some View {
        Section {
            MacOS15SettingsPicker(localized("Keep history for"), selection: $general.retentionPeriod, display: \.label)
            {
                ForEach(RetentionPeriodOption.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .macOS15SettingsSearchAnchor("retention")
        } header: {
            Text(localized("Recording settings"))
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(localized("Pinned items are never expired or evicted."))
                Text(
                    localized(
                        "Handoff labels use a system pasteboard marker. Missing markers do not prove a local copy; existing history cannot be reclassified."
                    ))
            }
        }
    }

    private var storageManagementSection: some View {
        Section {
            MacOS15SettingsPicker(
                localized("History capacity"), selection: $general.capacity, display: GeneralSettingsStore.capacityLabel
            ) {
                ForEach(GeneralSettingsStore.capacityChoices, id: \.self) { choice in
                    Text(GeneralSettingsStore.capacityLabel(choice)).tag(choice)
                }
            }
            .macOS15SettingsSearchAnchor("capacity")
            Button(localized("Clear Unpinned Items"), systemImage: "trash", role: .destructive) {
                confirmingClearHistory = true
            }
            .macOS15SettingsAction()
            .alert(localized("Clear Unpinned Items"), isPresented: $confirmingClearHistory) {
                Button(localized("Cancel"), role: .cancel) {}
                Button(localized("Clear Unpinned Items"), role: .destructive) { clearHistory() }
            }
            .macOS15SettingsSearchAnchor("clearHistory")
        } header: {
            Text(localized("Storage management"))
        } footer: {
            Text(localized("Pinned items are never expired or evicted."))
        }
    }

    private var pinnedItemsSection: some View {
        Section {
            MacOS15SettingsPicker(
                localized("Pinned items presentation"), selection: $general.pinnedPresentation, display: \.label
            ) {
                ForEach(PinnedPresentation.allCases) { Text($0.label).tag($0) }
            }.macOS15SettingsSearchAnchor("pinnedPresentation")
            if general.pinnedPresentation == .separate {
                MacOS15SettingsPicker(
                    localized("Pinned window layout"), selection: $general.pinnedWindowStyle, display: \.label
                ) {
                    ForEach(PinnedWindowStyle.allCases) { Text($0.label).tag($0) }
                }.macOS15SettingsSearchAnchor("pinnedWindowStyle")
            }
            Text(
                localized(
                    "Use the pinned-items shortcut or menu item. In the clipboard panel it selects Pinned; a separate window only shows pinned items."
                )
            )
            .font(typography.font(.caption)).foregroundStyle(.secondary)
        } header: {
            Text(localized("Pinned items"))
        }
    }

    private var secretRecognitionSection: some View {
        Section {
            Toggle(localized("Automatically recognize secrets"), isOn: $general.secretRecognition.enabled)
                .macOS15SettingsSearchAnchor("recognizeSecrets")
            if general.secretRecognition.enabled {
                Toggle(localized("Secret masking"), isOn: $general.secretRecognition.mask)
                    .macOS15SettingsSearchAnchor("maskSecrets")
                Toggle(localized("Categorize secrets"), isOn: $general.secretRecognition.classify)
                    .macOS15SettingsSearchAnchor("classifySecrets")
            }
            Text(localized("Recognition runs on this Mac and looks for common key, cookie, hash, and token formats."))
                .font(typography.font(.caption)).foregroundStyle(.secondary)
        } header: {
            Text(localized("Secret Recognition"))
        }
    }

    @ViewBuilder private var sensitiveAccessSection: some View {
        Section {
            privacyNotice(symbol: "lock.shield", tint: accent) {
                Text(localized("Copies are kept temporarily, then deleted from WhiskyMac without undo."))
            }
            .macOS15SettingsSearchAnchor("sensitiveApps")
            sensitiveRetentionRow
                .macOS15SettingsSearchAnchor("sensitiveRetention")
            sensitiveAppRows($general.sensitiveApps, emptyMessage: localized("No sensitive apps added."))
            addPrivacyAppButton(localized("Add sensitive app…"), sensitive: true)
        } header: {
            Text(localized("Sensitive apps"))
        }

        Section {
            privacyNotice(symbol: "hand.raised.fill", tint: accent) {
                Text(localized("Copies from excluded apps are never recorded."))
            }
            .macOS15SettingsSearchAnchor("excludedApps")
            sensitiveAppRows($general.excludedApps, emptyMessage: localized("No excluded apps added."))
            addPrivacyAppButton(localized("Add App…"), sensitive: false)
        } header: {
            Text(localized("Excluded apps"))
        }

        Section {
            explanationDisclosure(localized("How sensitive access works"), isExpanded: $temporarySessionsExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        localized(
                            "Sensitive copies stay in memory, outside disk history, search and undo. They start hidden and can be shown for 10 seconds. They expire at the selected limit or sooner when the app quits, the Mac sleeps or the memory limit is reached. Expiration does not clear the system clipboard or copies held by other apps."
                        ))
                    Text(
                        localized(
                            "Explicit no-record markers and excluded apps always win. Existing normal history is not reclassified. An app can belong to only one list; adding it moves it from the other list. Source attribution is best effort."
                        ))
                }
                .font(typography.font(.callout))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sensitiveRetentionRow: some View {
        let layout =
            typography.usesLargeLayout
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 10))
        return VStack(alignment: .leading, spacing: 6) {
            layout {
                Text(localized("Keep sensitive copies for"))
                    .fixedSize(horizontal: false, vertical: true)
                if !typography.usesLargeLayout { Spacer(minLength: 8) }
                HStack(spacing: 6) {
                    MacOS15NumericField(
                        title: localized("Keep sensitive copies for"), value: $general.sensitiveRetentionMinutes,
                        format: { String($0) }, parse: SensitiveRetention.minutes(from:))
                    Text(localized("minutes")).foregroundStyle(.secondary)
                    Stepper("", value: $general.sensitiveRetentionMinutes, in: SensitiveRetention.minutesRange)
                        .labelsHidden()
                        .accessibilityLabel(localized("Keep sensitive copies for"))
                }
                .fixedSize()
            }
            Text(
                localized(
                    "Enter 1–1440 minutes. Shortening the limit also applies to existing sensitive copies; increasing it only affects new copies."
                )
            )
            .font(typography.font(.caption))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sensitiveAppRows(_ apps: Binding<[ExcludedApp]>, emptyMessage: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if apps.wrappedValue.isEmpty {
                Text(emptyMessage)
                    .font(typography.font(.callout))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            ForEach(apps.wrappedValue) { app in
                VStack(spacing: 0) {
                    if app.id != apps.wrappedValue.first?.id {
                        Divider().padding(.vertical, 10)
                    }
                    HStack(spacing: 10) {
                        Group {
                            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                                    .resizable()
                                    .scaledToFit()
                            } else {
                                Image(systemName: "macwindow")
                                    .font(typography.font(.body))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: typography.room(24), height: typography.room(24))
                        .accessibilityHidden(true)
                        Text(app.name)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button(localized("Remove"), systemImage: "xmark.circle.fill") {
                            apps.wrappedValue.removeAll { $0.id == app.id }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .font(typography.font(.body))
                        .foregroundStyle(.secondary)
                        .help(localized("Remove"))
                    }
                }
                .transition(
                    .asymmetric(
                        insertion: .opacity
                            .combined(with: .scale(scale: 0.96, anchor: .leading))
                            .combined(with: .offset(y: 8)),
                        removal: .opacity)
                )
            }
        }
    }

    private func addPrivacyAppButton(_ title: String, sensitive: Bool) -> some View {
        SettingsRowLabel(title, symbol: "plus", tint: accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .beButton { addExcludedApp(sensitive: sensitive) }
            .buttonStyle(MacOS15SettingsHoverButtonStyle())
    }

    private var vimSection: some View {
        Section {
            Toggle(localized("Vim navigation in the panel"), isOn: $general.vimNavigation)
                .toggleStyle(MacOS15SettingsToggleStyle())
                .macOS15SettingsSearchAnchor("vim")
            if general.vimNavigation {
                ForEach(VimAction.allCases) { action in
                    HStack(spacing: 10) {
                        Text(action.displayName)
                        Spacer()
                        if vimBindings.duplicatedActions.contains(action) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                                .help(localized("This shortcut is used by another action"))
                        }
                        MacOS15VimKeyField(action: action, store: vimBindings)
                        Image(systemName: "arrow.uturn.backward")
                            .beButton { vimBindings.reset(action) }
                            .buttonStyle(.borderless)
                            .disabled(!vimBindings.isCustomized(action))
                            .help(localized("Reset to default"))
                    }
                    .macOS15SettingsSearchAnchor("vim.\(action.rawValue)")
                }
            }
        } header: {
            Text(localized("Vim Keybindings"))
        } footer: {
            if general.vimNavigation {
                Text(
                    localized(
                        "One or two characters — a two-character binding like gg runs on the double tap. Esc, Tab, / and 1–9 are fixed."
                    )
                )
            } else {
                Text(
                    String(
                        format: localized(
                            "The panel opens with letters as commands: %@ to search, %@ to move, %@ to paste, %@ to preview, %@ to close."
                        ),
                        vimBindings.key(for: .search),
                        vimBindings.key(for: .previousCard) + vimBindings.key(for: .rowDown)
                            + vimBindings.key(for: .rowUp) + vimBindings.key(for: .nextCard),
                        vimBindings.key(for: .paste),
                        vimBindings.key(for: .preview),
                        vimBindings.key(for: .closePanel)
                    )
                )
            }
        }
    }

    private func shortcutsSection(global: Bool) -> some View {
        Section {
            ForEach(KeyAction.allCases.filter { $0.isGlobal == global }) { action in
                HStack(spacing: 10) {
                    Text(action.displayName)
                    if action.isGlobal {
                        Text(localized("global"))
                            .font(typography.font(.caption2))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.quaternary))
                        Toggle(
                            localized("Enable"),
                            isOn: Binding(
                                get: { store.isGlobalEnabled(action) },
                                set: { store.setGlobalEnabled($0, for: action) }
                            )
                        )
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .help(localized("Enable this global shortcut"))
                    }
                    Spacer()
                    if store.duplicatedActions.contains(action) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .help(localized("This shortcut is used by another action"))
                    }
                    if store.registrationFailures.contains(action) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help(localized("This global shortcut could not be registered. Choose another binding."))
                    }
                    MacOS15ShortcutRecorder(action: action, store: store)
                    Image(systemName: "arrow.uturn.backward")
                        .beButton { store.reset(action) }
                        .buttonStyle(.borderless)
                        .disabled(!store.isCustomized(action))
                        .help(localized("Reset to default"))
                }
                .macOS15SettingsSearchAnchor("shortcut.\(action.rawValue)")
            }
        } header: {
            Text(global ? localized("Global shortcuts") : localized("Inside the clipboard panel"))
        } footer: {
            VStack(alignment: .leading, spacing: 3) {
                if global { Text(localized("Global shortcuts are off until enabled here or recorded.")) }
                Text(localized("Click a shortcut to record a new one — press Escape to cancel recording."))
                Text(localized("⌘1…⌘9 paste the matching card directly."))
                if !store.duplicatedActions.isEmpty {
                    Label(
                        localized("Two actions share the same shortcut."),
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.yellow)
                }
            }
        }
    }

    private var restoreSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(localized("Reset category")).font(typography.font(.headline))
                ForEach(ShortcutResetCategory.allCases) { category in
                    Toggle(
                        isOn: Binding(
                            get: { resetCategories.contains(category) },
                            set: { selected in
                                if selected {
                                    resetCategories.insert(category)
                                } else {
                                    resetCategories.remove(category)
                                }
                            })
                    ) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(category.label)
                            Text(category.explanation).font(typography.font(.caption)).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .macOS15SettingsSearchAnchor("resetCategory")
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localized("Reset keyboard shortcuts"))
                    Text(localized("Only selected categories are reset."))
                        .font(typography.font(.caption)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(localized("Reset…"), systemImage: "arrow.counterclockwise", role: .destructive) {
                    confirmingReset = true
                }
                .macOS15SettingsAction()
                .disabled(resetCategories.isEmpty)
            }
            .macOS15SettingsSearchAnchor("resetShortcuts")
            .alert(localized("Reset keyboard shortcuts?"), isPresented: $confirmingReset) {
                Button(localized("Cancel"), role: .cancel) {}
                Button(localized("Restore Defaults"), role: .destructive) {
                    resetUndo.reset(resetCategories, keys: store, vim: vimBindings)
                }
            } message: {
                Text(
                    ShortcutResetCategory.allCases.filter { resetCategories.contains($0) }.map {
                        "\($0.label) — \($0.explanation)"
                    }.joined(separator: "\n\n"))
            }
        } header: {
            Text(localized("Reset"))
        }
    }

    private func addExcludedApp(sensitive: Bool) {
        PrivacyAppPicker.present { apps in
            guard !privacy.isProtected else { return }
            let add = sensitive ? general.addSensitiveApp : general.excludeApp
            withAnimation(accessibility.reduceMotion ? nil : .smooth(duration: 0.32)) {
                apps.forEach(add)
            }
        }
    }
}

/// Keep the user's preferred width while giving the footer its natural size when it needs more room.
private struct MacOS15SettingsSidebarLayout: Layout {
    let preferredWidth: CGFloat

    private func minimumWidth(_ footer: LayoutSubview) -> CGFloat {
        let limits = AppearanceSettingsStore.sidebarWidthRange
        return min(limits.upperBound, max(limits.lowerBound, footer.sizeThatFits(.unspecified).width.rounded(.up)))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 3 else { return .zero }
        let minimum = minimumWidth(subviews[1])
        let width = min(AppearanceSettingsStore.sidebarWidthRange.upperBound, max(preferredWidth, minimum))
        let footerHeight = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        let navProposal = ProposedViewSize(width: width, height: proposal.height.map { max(0, $0 - footerHeight) })
        return CGSize(width: width, height: subviews[0].sizeThatFits(navProposal).height + footerHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let footerProposal = ProposedViewSize(width: bounds.width, height: nil)
        let footerHeight = subviews[1].sizeThatFits(footerProposal).height
        let navHeight = max(0, bounds.height - footerHeight)
        subviews[0].place(
            at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: navHeight))
        subviews[1].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + navHeight), anchor: .topLeading, proposal: footerProposal)
        // Report the intrinsic minimum to the resize handle even when the sidebar is wider.
        subviews[2].place(
            at: bounds.origin, anchor: .topLeading,
            proposal: ProposedViewSize(width: minimumWidth(subviews[1]), height: 1))
    }
}

private struct MacOS15SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.55))
            .frame(height: 0.5)
            .accessibilityHidden(true)
    }
}

private struct MacOS15SettingsSurfaceGroup: View {
    @Environment(\.interfaceTypography) private var typography

    let section: SectionConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !section.header.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(section.header) { header in
                        header
                    }
                }
                .font(typography.font(.headline))
                .padding(.leading, 4)
            }
            VStack(spacing: 0) {
                IndexedForEach(section.content) { index, row in
                    if index > 0 {
                        MacOS15SettingsDivider()
                            .padding(.leading, 16)
                    }
                    row
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .id(row.containerValues.macOS15SettingsSearchAnchorID ?? "settings-row-\(index)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .macOS15SettingsSurface(
                in: RoundedRectangle(cornerRadius: MacOS15SettingsSurface.groupCornerRadius, style: .continuous)
            )
            if !section.footer.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(section.footer) { footer in
                        footer
                    }
                }
                .font(typography.font(.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A vim binding is typed, not recorded: one or two plain characters,
/// committed on Return or when the focus leaves; junk falls back to the
/// action's default.
private struct MacOS15VimKeyField: View {
    @Environment(\.interfaceTypography) private var typography

    let action: VimAction
    @ObservedObject var store: VimBindingsStore
    @State private var text = ""
    @FocusState private var focused: Bool
    @SettingsAccessibility private var accessibility

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(typography.font(.body, design: .monospaced))
            .multilineTextAlignment(.center)
            .frame(width: max(44, typography.points(24)))
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .macOS15SettingsSurface(in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(focused ? Color.macOS15Matcha : .clear, lineWidth: 1.5)
            )
            .focused($focused)
            .animation(accessibility.reduceMotion ? nil : .easeOut(duration: 0.12), value: focused)
            .onAppear { text = store.key(for: action) }
            .onSubmit { commit() }
            .onChange(of: focused) { _, isFocused in
                if !isFocused {
                    commit()
                }
            }
            .onChange(of: store.keys) { _, _ in
                if !focused {
                    text = store.key(for: action)
                }
            }
    }

    private func commit() {
        store.set(text, for: action)
        text = store.key(for: action)
    }
}

/// Click to arm, then the next key press becomes the binding. Recording
/// state lives in the store, so at most one recorder is armed at a time.
private struct MacOS15ShortcutRecorder: View {
    @Environment(\.interfaceTypography) private var typography

    let action: KeyAction
    @ObservedObject var store: KeyBindingsStore
    @SettingsAccessibility private var accessibility
    @State private var isHovering = false

    private var isRecording: Bool {
        store.recordingAction == action
    }

    var body: some View {
        Text(isRecording ? localized("Type shortcut…") : store.label(for: action))
            .font(typography.font(.body, design: .rounded).weight(.medium))
            .frame(minWidth: 76)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .macOS15SettingsSurface(in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .background(
                Color.macOS15Matcha.opacity(isRecording ? 0.2 : (isHovering ? 0.055 : 0)),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isRecording ? Color.macOS15Matcha : .clear, lineWidth: 1.5)
            )
            .beButton {
                isRecording ? store.endRecording() : store.beginRecording(action)
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .animation(accessibility.reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
            .animation(accessibility.reduceMotion ? nil : .easeOut(duration: 0.12), value: isRecording)
            .onDisappear {
                if isRecording {
                    store.endRecording()
                }
            }
    }
}

struct MacOS15SettingsToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 16) {
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .labelsHidden()
                .toggleStyle(.switch)
                .fixedSize()
        }
    }
}

struct MacOS15SettingsPicker<Selection: Hashable, Options: View>: View {
    @Environment(\.interfaceTypography) private var typography
    let title: String
    @Binding var selection: Selection
    let display: (Selection) -> String
    @ViewBuilder let options: () -> Options

    init(
        _ title: String, selection: Binding<Selection>, display: @escaping (Selection) -> String,
        @ViewBuilder options: @escaping () -> Options
    ) {
        self.title = title
        _selection = selection
        self.display = display
        self.options = options
    }

    var body: some View {
        if typography.isStandard {
            HStack(spacing: 16) {
                Text(title).fixedSize(horizontal: false, vertical: true).accessibilityHidden(true)
                Spacer(minLength: 8)
                picker.labelsHidden().pickerStyle(.menu).fixedSize()
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    Text(title).fixedSize().accessibilityHidden(true)
                    Spacer(minLength: 0)
                    menuButton.fixedSize()
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).fixedSize(horizontal: false, vertical: true).accessibilityHidden(true)
                    menuButton
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var picker: some View {
        Picker(title, selection: $selection, content: options)
    }

    private var menuButton: some View {
        MenuButton(title: title, value: display(selection), options: picker.pickerStyle(.inline))
    }

    private struct MenuButton<MenuOptions: View>: View {
        @Environment(\.interfaceTypography) private var typography
        @State private var presenter = SettingsMenuPresenter()
        let title: String
        let value: String
        let options: MenuOptions

        var body: some View {
            Button {
                presenter.present(options, typography: typography)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: value)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(typography.font(size: 9, weight: .semibold))
                        .accessibilityHidden(true)
                }
                .font(typography.font(.body))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.fill.secondary, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .background(MenuAnchor(presenter: presenter).allowsHitTesting(false).accessibilityHidden(true))
            .accessibilityLabel(title)
            .accessibilityValue(value)
        }
    }

    private struct MenuAnchor: NSViewRepresentable {
        let presenter: SettingsMenuPresenter

        func makeNSView(context: Context) -> NSView { NSView() }

        func updateNSView(_ view: NSView, context: Context) {
            presenter.anchor = view
        }
    }
}

/// Commit completed numbers so intermediate keystrokes never clamp the value.
struct MacOS15NumericField<Value: Equatable>: View {
    @Environment(\.interfaceTypography) private var typography
    let title: String
    @Binding var value: Value
    let format: (Value) -> String
    let parse: (String) -> Value?
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: $draft)
            .textFieldStyle(.plain)
            .font(typography.font(.body).monospacedDigit())
            .multilineTextAlignment(.trailing)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(width: typography.room(72))
            .background(.background, in: RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5).strokeBorder(focused ? Color.accentColor : .secondary.opacity(0.35))
            )
            .accessibilityLabel(title)
            .focused($focused)
            .onAppear { sync() }
            .onSubmit { commit() }
            .onChange(of: focused) { _, active in if !active { commit() } }
            .onChange(of: value) { _, _ in sync() }
    }

    private func sync() { draft = format(value) }
    private func commit() {
        if draft != format(value), let parsed = parse(draft) { value = parsed }
        sync()
    }
}

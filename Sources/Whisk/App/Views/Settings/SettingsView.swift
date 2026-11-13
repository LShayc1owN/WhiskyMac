// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import ApplicationServices
import SwiftUI

/// The Settings window: general housekeeping plus one recorder per
/// keyboard action.
struct SettingsView: View {
    @ObservedObject var store: KeyBindingsStore
    @ObservedObject var general: GeneralSettingsStore
    @ObservedObject var loginItem: LoginItemManager
    @ObservedObject var vimBindings: VimBindingsStore
    @ObservedObject var privacy = PrivacyController()
    var distribution: Distribution = .current
    var clearHistory: () -> Void = {}

    @ObservedObject var appearance = AppearanceSettingsStore()
    @ObservedObject var updateChecker = UpdateChecker()
    @ObservedObject var search = SettingsSearchModel()
    @State private var copySoundPlayer = CopySoundPlayer()
    @State private var confirmingReset = false
    @State private var resetCategories = Set(ShortcutResetCategory.allCases)
    @StateObject private var resetUndo = ShortcutResetUndo()
    @State private var confirmingClearHistory = false
    @State private var draftCardSide: Double?
    @State private var previewedCardSide = GeneralSettingsStore.defaultCardSide
    @State private var showingCardSizePreview = false
    @State private var cardSizePreviewDeadline = Date.distantPast
    @State private var cardSizePreviewTask: Task<Void, Never>?
    @State private var selectedSection: SettingsSectionID?
    @State private var sidebarDragStart: CGFloat?
    @State private var detectionCoverageExpanded = false
    @State private var temporarySessionsExpanded = false
    @State var selectedPage = SettingsPage.general
    @SettingsAccessibility private var accessibility
    @FocusState private var focusedNavigation: SettingsPage?
    @Namespace private var navigationNamespace
    @Namespace private var sidebarIndicatorNamespace
    @Namespace private var topSectionIndicatorNamespace

    private var sectionIDs: [SettingsSectionID] { selectedPage.sections(isProtected: privacy.isProtected) }
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
            automaticProtection: privacy.automaticEnabled, vimEnabled: general.vimNavigation)
    }

    var body: some View {
        ZStack {
            SettingsWindowBackdrop()
                .ignoresSafeArea()
            VStack(spacing: 0) {
                if appearance.navigation == .top {
                    topPageNavigation
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    SettingsDivider()
                    topNavigation
                        .transition(.opacity)
                    SettingsDivider()
                }
                HStack(spacing: 0) {
                    if appearance.navigation == .sidebar {
                        sidebarNavigation
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                        sidebarResizeHandle
                    }

                    pageContent
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .environment(\.settingsSearchHighlight, search.highlightedAnchor)
        .tint(appearance.accent)
        .frame(width: SettingsWindowSize.width)
        .frame(
            minHeight: SettingsWindowSize.minimumHeight, idealHeight: SettingsWindowSize.height,
            maxHeight: SettingsWindowSize.height
        )
        .animation(navigationAnimation, value: appearance.navigation)
        .animation(contentAnimation, value: selectedPage)
        .overlay(alignment: .bottom) {
            if resetUndo.isPresented {
                ShortcutResetToast(undo: resetUndo, accent: appearance.accent) {
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
            if let selectedSection, !sectionIDs.contains(selectedSection) { self.selectedSection = sectionIDs.first }
            search.refresh(context: context)
        }
        .onChange(of: appearance.language) { _, _ in search.refresh(context: searchContext) }
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
            discardCardSizePreview()
            search.reset()
        }
        .sheet(isPresented: $showingCardSizePreview, onDismiss: discardCardSizePreview) {
            cardSizePreviewSheet
        }
    }

    private var topPageNavigation: some View {
        HStack(spacing: 4) {
            ForEach(SettingsPage.allCases) { page in
                Text(page.label)
                    .font(.system(size: 12, weight: selectedPage == page ? .semibold : .medium))
                    .foregroundStyle(selectedPage == page ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background {
                        if selectedPage == page { navigationSelection() }
                    }
                    .beButton { select(page) }
                    .buttonStyle(SettingsHoverButtonStyle(isSelected: selectedPage == page))
                    .focused($focusedNavigation, equals: page)
                    .onMoveCommand { moveNavigation($0, from: page) }
                    .accessibilityValue(selectedPage == page ? localized("Selected") : "")
                    .accessibilityAddTraits(selectedPage == page ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var topNavigation: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(sectionIDs) { section in
                    Text(section.title.localized)
                        .font(.system(size: 12, weight: selectedSectionID == section ? .semibold : .medium))
                        .foregroundStyle(selectedSectionID == section ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            if selectedSectionID == section {
                                Capsule()
                                    .fill(appearance.accent)
                                    .frame(height: 2)
                                    .padding(.horizontal, 8)
                                    .matchedGeometryEffect(id: selectedPage, in: topSectionIndicatorNamespace)
                                    .accessibilityHidden(true)
                            }
                        }
                        .beButton { selectedSection = section }
                        .buttonStyle(SettingsHoverButtonStyle(isSelected: selectedSectionID == section))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .animation(
                accessibility.reduceMotion || privacy.isProtected ? nil : .easeInOut(duration: 0.22),
                value: selectedSectionID)
        }
    }

    private var sidebarNavigation: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(SettingsPage.allCases) { page in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: page.symbol)
                            .frame(width: 18)
                        Text(page.label)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 14, weight: selectedPage == page ? .semibold : .regular))
                    .foregroundStyle(selectedPage == page ? appearance.accent : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background {
                        if selectedPage == page {
                            RoundedRectangle(cornerRadius: SettingsSurface.controlCornerRadius)
                                .fill(appearance.accent.opacity(0.18))
                        }
                    }
                    .beButton { select(page) }
                    .buttonStyle(SettingsHoverButtonStyle(isSelected: selectedPage == page))
                    .focused($focusedNavigation, equals: page)
                    .onMoveCommand { moveNavigation($0, from: page) }
                    .accessibilityValue(selectedPage == page ? localized("Selected") : "")
                    .accessibilityAddTraits(selectedPage == page ? .isSelected : [])
                    if selectedPage == page {
                        sidebarSections
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .padding(12)
        }
        .frame(width: appearance.sidebarWidth)
    }

    private var sidebarResizeHandle: some View {
        Rectangle()
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
                                if sidebarDragStart == nil { sidebarDragStart = appearance.sidebarWidth }
                                let width = (sidebarDragStart ?? appearance.sidebarWidth) + value.translation.width
                                appearance.sidebarWidth = min(
                                    AppearanceSettingsStore.sidebarWidthRange.upperBound,
                                    max(AppearanceSettingsStore.sidebarWidthRange.lowerBound, width))
                            }
                            .onEnded { _ in sidebarDragStart = nil }
                    )
                    .accessibilityLabel(localized("Sidebar width"))
                    .accessibilityAdjustableAction { direction in
                        let delta: CGFloat = direction == .increment ? 12 : -12
                        appearance.sidebarWidth = min(
                            AppearanceSettingsStore.sidebarWidthRange.upperBound,
                            max(AppearanceSettingsStore.sidebarWidthRange.lowerBound, appearance.sidebarWidth + delta))
                    }
            }
    }

    private var sidebarSections: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(sectionIDs) { section in
                HStack {
                    Text(section.title.localized)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 12, weight: selectedSectionID == section ? .semibold : .regular))
                .foregroundStyle(selectedSectionID == section ? Color.primary : Color.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background {
                    if selectedSectionID == section {
                        RoundedRectangle(cornerRadius: SettingsSurface.controlCornerRadius)
                            .fill(Color.primary.opacity(0.08))
                    }
                }
                .overlay(alignment: .leading) {
                    if selectedSectionID == section {
                        Rectangle()
                            .fill(appearance.accent)
                            .frame(width: 2)
                            .matchedGeometryEffect(id: selectedPage, in: sidebarIndicatorNamespace)
                            .offset(x: -12)
                            .accessibilityHidden(true)
                    }
                }
                .beButton { selectedSection = section }
                .buttonStyle(SettingsHoverButtonStyle(isSelected: selectedSectionID == section))
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
        RoundedRectangle(cornerRadius: SettingsSurface.controlCornerRadius, style: .continuous)
            .fill(Color.primary.opacity(0.09))
            .overlay(
                RoundedRectangle(cornerRadius: SettingsSurface.controlCornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.5)
            )
            .matchedGeometryEffect(id: "selection", in: navigationNamespace)
    }

    private var pageContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(contentTitle).font(.system(size: 24, weight: .semibold))
                if selectedSectionID == .aboutApp {
                    aboutAppSummary
                } else {
                    Text(contentSummary).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 14)
            if selectedPage == .about {
                if selectedSectionID == .licenses {
                    LegalSettingsView().settingsSearchAnchor("licenses")
                } else {
                    AboutSettingsView(
                        section: selectedSectionID, updateChecker: updateChecker, general: general,
                        search: search)
                }
            } else {
                settingsForm
            }
        }
        .id(selectedPage)
        .transition(pageTransition)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private var aboutAppSummary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            aboutRepositoryLink("WhiskyMac", url: "https://github.com/LShayc1owN/WhiskyMac")
            Text(localized(" is a clipboard app based on "))
            aboutRepositoryLink("Whisk", url: "https://github.com/nathan-poncet/whisk")
            Text(localized(" that aims to do as much as possible, making input on your Mac easier and simpler."))
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private func aboutRepositoryLink(_ name: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 2) {
                Text(name)
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.semibold))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(appearance.accent)
    }

    private var contentTitle: String {
        guard selectedPage == .about else { return selectedPage.title }
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
        let pages = SettingsPage.allCases
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
        guard selectedPage != page else { return }
        selectedSection = nil
        selectedPage = page
    }

    private func navigate(to destination: SettingsDestination) {
        guard let section = destination.resolvedSection(isProtected: privacy.isProtected) else { return }
        selectedPage = destination.page
        selectedSection = section
    }

    private var settingsForm: some View {
        SettingsSearchScrollView(search: search, section: selectedSectionID) {
            Group(sections: sections) { pageSections in
                if !pageSections.isEmpty {
                    SettingsSurfaceGroup(section: pageSections[min(selectedSectionIndex, pageSections.count - 1)])
                        .transition(pageTransition)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .id(selectedSectionID)
        .multilineTextAlignment(.leading)
        .animation(contentAnimation, value: appearance.accentMode)
        .animation(contentAnimation, value: general.vimNavigation)
        .animation(contentAnimation, value: general.interactions.hover)
        .animation(contentAnimation, value: general.privacyInteractions.hover)
        .animation(contentAnimation, value: selectedSectionID)
        .transaction { transaction in
            if privacy.isProtected { transaction.animation = nil; transaction.disablesAnimations = true }
        }
        .toggleStyle(SettingsToggleStyle())
    }

    private func explanationDisclosure<Content: View>(
        _ title: String, isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .beButton { isExpanded.wrappedValue.toggle() }
            .buttonStyle(.plain)
            if isExpanded.wrappedValue {
                content()
            }
        }
        .animation(contentAnimation, value: isExpanded.wrappedValue)
    }

    @ViewBuilder
    private var sections: some View {
        switch selectedPage {
        case .general:
            generalSection
            copySoundSection
        case .appearance: appearanceSection
        case .interactions:
            interactionSection
            pinnedItemsSection
        case .history:
            recordingSettingsSection
            storageManagementSection
        case .privacy:
            privacySection
            if !privacy.isProtected {
                sensitiveAccessSection
            }
            networkSection
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

    @ViewBuilder private var appearanceSection: some View {
        Section {
            StatusSymbolPickerRow(
                title: localized("Default mode icon"), selection: $appearance.defaultStatusSymbol,
                defaultName: "WhiskyMac"
            )
            .settingsSearchAnchor("defaultIcon")
            StatusSymbolPickerRow(
                title: localized("Privacy mode icon"), selection: $appearance.privacyStatusSymbol,
                defaultName: "LemonSlice"
            )
            .settingsSearchAnchor("privacyIcon")
        } header: {
            Text(localized("Menu bar icons"))
        }
        Section {
            SettingsPicker(localized("Settings layout"), selection: $appearance.navigation) {
                ForEach(SettingsNavigation.allCases) { option in Text(option.label).tag(option) }
            }
            .settingsSearchAnchor("navigation")
        } header: {
            Text(localized("Settings navigation"))
        }
        Section {
            SettingsPicker(localized("Accent color"), selection: $appearance.accentMode) {
                ForEach(AccentMode.allCases) { option in Text(option.label).tag(option) }
            }
            .settingsSearchAnchor("accent")
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
                .settingsSearchAnchor("customAccent")
            }
        } header: {
            Text(localized("Colors"))
        } footer: {
            Text(localized("The accent color also highlights the selected clipboard card."))
        }
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    SettingsRowLabel(localized("Card size"), symbol: "rectangle.3.group", tint: .indigo)
                    Spacer(minLength: 12)
                    Slider(
                        value: Binding(
                            get: { draftCardSide ?? general.cardSide },
                            set: { draftCardSide = GeneralSettingsStore.boundedCardSide($0) }),
                        in: GeneralSettingsStore.cardSideRange
                    )
                    .frame(minWidth: 130, maxWidth: 220)
                    .accessibilityLabel(localized("Card size"))
                    Text("\(Int((draftCardSide ?? general.cardSide).rounded())) \(localized("pt"))")
                        .monospacedDigit()
                        .frame(width: 54, alignment: .trailing)
                }
                HStack(spacing: 12) {
                    Button(localized("Preview size…")) {
                        beginCardSizePreview(draftCardSide ?? general.cardSide)
                    }
                    if general.cardSide != GeneralSettingsStore.defaultCardSide {
                        Button(localized("Restore default size")) {
                            draftCardSide = GeneralSettingsStore.defaultCardSide
                            beginCardSizePreview(GeneralSettingsStore.defaultCardSide)
                        }
                    }
                }
            }
            .settingsSearchAnchor("cardSize")
        } header: {
            Text(localized("Clipboard cards"))
        } footer: {
            Text(localized("Preview a size, then save it to keep the change."))
        }
    }

    private var cardSizePreviewSheet: some View {
        VStack(spacing: 18) {
            Text(localized("Card size"))
                .font(.title3.weight(.semibold))
            CardSizePreview(side: CGFloat(previewedCardSide))
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let seconds = max(0, Int(ceil(cardSizePreviewDeadline.timeIntervalSince(timeline.date))))
                Text(String(format: localized("Reverting in %d seconds"), seconds))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack {
                Spacer()
                Button(localized("Cancel")) { discardCardSizePreview() }
                    .keyboardShortcut(.cancelAction)
                Button(localized("Save")) { saveCardSizePreview() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    private func beginCardSizePreview(_ side: Double) {
        cardSizePreviewTask?.cancel()
        previewedCardSide = GeneralSettingsStore.boundedCardSide(side)
        cardSizePreviewDeadline = Date().addingTimeInterval(15)
        general.beginCardSizePreview(previewedCardSide)
        showingCardSizePreview = true
        cardSizePreviewTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            discardCardSizePreview()
        }
    }

    private func saveCardSizePreview() {
        cardSizePreviewTask?.cancel()
        cardSizePreviewTask = nil
        general.saveCardSizePreview()
        draftCardSide = nil
        showingCardSizePreview = false
    }

    private func discardCardSizePreview() {
        cardSizePreviewTask?.cancel()
        cardSizePreviewTask = nil
        general.cancelCardSizePreview()
        draftCardSide = nil
        showingCardSizePreview = false
    }

    private var copySoundSection: some View {
        Section {
            Toggle(localized("Play a sound when a new copy is recorded"), isOn: $general.copySound.onCapture)
                .settingsSearchAnchor("captureSound")
            Toggle(localized("Play a sound when copying from history"), isOn: $general.copySound.onHistoryCopy)
                .settingsSearchAnchor("historySound")
            SettingsPicker(localized("Copy sound"), selection: $general.copySound.sound) {
                ForEach(CopySound.Collection.allCases) { collection in
                    Section(collection.rawValue) {
                        ForEach(collection.sounds) { sound in Text(sound.label).tag(sound) }
                    }
                }
            }
            .settingsSearchAnchor("copySound")
            HStack {
                Text(localized("Sound volume"))
                Slider(value: $general.copySound.volume, in: 0...1)
                    .accessibilityLabel(localized("Sound volume"))
                Button(localized("Preview sound")) { copySoundPlayer.preview(general.copySound) }
            }
            .settingsSearchAnchor("volume")
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
            Toggle(isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) })) {
                SettingsRowLabel(localized("Launch WhiskyMac at login"), symbol: "power", tint: .green)
            }
            .toggleStyle(SettingsToggleStyle())
            .settingsSearchAnchor("launch")
            if let error = loginItem.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if distribution.checksForUpdates {
                Toggle(isOn: $general.checkForUpdates) {
                    SettingsRowLabel(
                        localized("Check for updates at launch"), symbol: "arrow.triangle.2.circlepath", tint: .blue)
                }
                .toggleStyle(SettingsToggleStyle())
                .settingsSearchAnchor("startupUpdates")
            }
        } header: {
            Text(localized("Startup"))
        }
        Section {
            SettingsPicker(localized("Menu bar icon click"), selection: $appearance.statusClick) {
                ForEach(StatusClickAction.allCases) { option in Text(option.label).tag(option) }
            }
            .settingsSearchAnchor("statusClick")
            SettingsPicker(localized("Dock icon"), selection: $appearance.dockIcon) {
                ForEach(DockIconMode.allCases) { option in Text(option.label).tag(option) }
            }
            .settingsSearchAnchor("dockIcon")
        } header: {
            Text(localized("Menu bar and Dock"))
        } footer: {
            Text(
                localized(
                    "Right-click always opens the menu. Follow windows shows the Dock icon for Settings and welcome windows only."
                ))
        }
        Section {
            SettingsPicker(localized("Language"), selection: $appearance.language) {
                ForEach(AppLanguage.allCases) { option in Text(option.label).tag(option) }
            }
            .settingsSearchAnchor("language")
        } header: {
            Text(localized("Language"))
        }
    }

    @ViewBuilder private var interactionSection: some View {
        Section {
            SettingsPicker(localized("Application filter trigger"), selection: $general.appFilterTrigger) {
                ForEach(AppFilterTrigger.allCases) { trigger in Text(trigger.label).tag(trigger) }
            }
            .settingsSearchAnchor("filterTrigger")
        } header: {
            Text(localized("Filters"))
        } footer: {
            Text(
                localized(
                    "Hover switches to one app after a brief pause. Click still toggles filters; All clears app, type and pinned filters without clearing search."
                ))
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
            .settingsSearchAnchor(privacyMode ? "private.single" : "normal.single")
            interactionPicker(
                localized("Double click"), key: \.doubleClick, bindings: bindings, privacyMode: privacyMode
            )
            .settingsSearchAnchor(privacyMode ? "private.double" : "normal.double")
            interactionPicker(localized("Right click"), key: \.rightClick, bindings: bindings, privacyMode: privacyMode)
                .settingsSearchAnchor(privacyMode ? "private.right" : "normal.right")
            Text(localized("Hover preview")).font(.caption).foregroundStyle(.secondary)
            SettingsPicker(localized("Hover after a short delay"), selection: bindings.hover) {
                Text(CardAction.none.label).tag(CardAction.none)
                Text(privacyMode ? localized("Reveal a small area") : CardAction.preview.label).tag(CardAction.preview)
            }
            .settingsSearchAnchor(privacyMode ? "private.hover" : "normal.hover")
            if bindings.wrappedValue.hover == .preview {
                HStack {
                    Text(localized("Hover delay (seconds)"))
                    Spacer()
                    TextField("", value: bindings.hoverDelay, format: .number.precision(.fractionLength(1)))
                        .multilineTextAlignment(.trailing).frame(width: 64)
                    Stepper("", value: bindings.hoverDelay, in: 0.1...5, step: 0.1).labelsHidden()
                }
                .settingsSearchAnchor(privacyMode ? "private.delay" : "normal.delay")
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
                        "Copy and paste require an explicit click. Full preview and editing stay disabled. Local reveal works only in manual privacy; automatic protection stays masked."
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
        SettingsPicker(
            title,
            selection: Binding(
                get: { bindings.wrappedValue[keyPath: key] },
                set: { bindings.wrappedValue[keyPath: key] = $0 }
            )
        ) {
            ForEach(CardAction.allCases.filter { !privacyMode || ($0 != .edit && $0 != .split) }, id: \.rawValue) {
                action in
                Text(privacyMode && action == .preview ? localized("Reveal a small area") : action.label).tag(action)
            }
        }
    }

    @ViewBuilder private var privacySection: some View {
        Section {
            Toggle(
                localized("Manual Privacy Mode"),
                isOn: Binding(
                    get: { privacy.isManuallyProtected }, set: { privacy.setProtected($0) })
            )
            .settingsSearchAnchor("manualPrivacy")
            Toggle(
                localized("Automatic protection (limited detection)"),
                isOn: Binding(get: { privacy.automaticEnabled }, set: { privacy.setAutomaticEnabled($0) })
            )
            .settingsSearchAnchor("automaticPrivacy")
            VStack(alignment: .leading, spacing: 8) {
                Label(privacy.statusText, systemImage: privacy.isProtected ? "lock.shield.fill" : "shield")
                    .font(.callout).foregroundStyle(privacy.isProtected ? Color.accentColor : Color.secondary)
                Text(localized("Automatic detection is limited. Use manual protection before important sharing."))
                    .font(.caption).foregroundStyle(.secondary)
                explanationDisclosure(localized("Detection coverage"), isExpanded: $detectionCoverageExpanded) {
                    Text(
                        localized(
                            "Checks Zoom and Teams sharing toolbar titles using Accessibility. Client versions and languages may not match. System sharing, remote desktop, recording and browser tabs are not covered. Enable manual protection before important sharing."
                        )
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            .settingsSearchAnchor("detection")
            if privacy.automaticEnabled {
                Button(localized("Allow Accessibility for toolbar detection…")) {
                    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                    _ = AXIsProcessTrustedWithOptions(options)
                }
                .settingsSearchAnchor("accessibility")
            }
        } header: {
            Text(localized("Screen privacy"))
        }
        Section {
            Toggle(localized("Allow search in Privacy Mode"), isOn: $privacy.allowSearchWhileProtected)
                .settingsSearchAnchor("privacySearch")
            Toggle(localized("Allow filtering in Privacy Mode"), isOn: $privacy.allowFilteringWhileProtected)
                .settingsSearchAnchor("privacyFilters")
            Text(
                localized(
                    "Filtering keeps content hidden. Application filters require Show source apps in Privacy Mode.")
            )
            .font(.caption).foregroundStyle(.secondary)
            Toggle(localized("Show source apps in Privacy Mode"), isOn: $privacy.showSourceAppsWhileProtected)
                .settingsSearchAnchor("privacySources")
        } header: {
            Text(localized("Visible during protection"))
        } footer: {
            Text(
                localized(
                    "Applies to manual and automatic protection. Search terms and enabled app names are visible on screen and in accessibility. Clipboard content stays hidden; automatic protection still blocks hover reveals."
                ))
        }
    }

    private func spotlightPoints(_ value: Double) -> String {
        let points = Int(value)
        return localized("\(points) pt")
    }

    private var spotlightControls: some View {
        Group {
            Text(localized("Hover reveal area"))
                .font(.subheadline.weight(.semibold))
                .padding(.top, 20)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(localized("Diameter"))
                    Spacer()
                    SpotlightPointField(title: localized("Diameter"), value: $privacy.spotlight.diameter)
                    Text(localized("pt")).foregroundStyle(.secondary)
                }
                Slider(value: $privacy.spotlight.diameter, in: SpotlightPreferences.diameterRange, step: 10)
                    .accessibilityLabel(localized("Diameter"))
                    .accessibilityValue(spotlightPoints(privacy.spotlight.diameter))
            }
            .settingsSearchAnchor("diameter")
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(localized("Edge blur radius"))
                    Spacer()
                    SpotlightPointField(title: localized("Edge blur radius"), value: $privacy.spotlight.blurRadius)
                    Text(localized("pt")).foregroundStyle(.secondary)
                }
                Slider(value: $privacy.spotlight.blurRadius, in: privacy.spotlight.blurRange, step: 1)
                    .accessibilityLabel(localized("Edge blur radius"))
                    .accessibilityValue(spotlightPoints(privacy.spotlight.blurRadius))
            }
            .settingsSearchAnchor("blur")
            Button(localized("Restore default values")) { privacy.spotlight = SpotlightPreferences() }
                .disabled(privacy.spotlight == SpotlightPreferences())
                .settingsSearchAnchor("resetSpotlight")

            Text(
                localized(
                    "Applies to manual privacy with Hover set to Preview. The blur softens the reveal edge. Revealed content can be recorded; automatic protection stays fully masked."
                )
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var networkSection: some View {
        Section {
            Toggle(isOn: $general.linkPreviews) {
                SettingsRowLabel(localized("Fetch link previews"), symbol: "link", tint: .teal)
            }
            .toggleStyle(SettingsToggleStyle())
            .settingsSearchAnchor("linkPreviews")
        } header: {
            Text(localized("Online content"))
        } footer: {
            Text(localized("A copied link is looked up once for its title and image. Off, nothing leaves this Mac."))
        }
    }

    private var recordingSettingsSection: some View {
        Section {
            SettingsPicker(selection: $general.retentionPeriod) {
                ForEach(RetentionPeriodOption.allCases) { option in
                    Text(option.label).tag(option)
                }
            } label: {
                SettingsRowLabel(localized("Keep history for"), symbol: "clock", tint: .orange)
            }
            .settingsSearchAnchor("retention")
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
            SettingsPicker(selection: $general.capacity) {
                ForEach(GeneralSettingsStore.capacityChoices, id: \.self) { choice in
                    Text(GeneralSettingsStore.capacityLabel(choice)).tag(choice)
                }
            } label: {
                SettingsRowLabel(localized("History capacity"), symbol: "tray.full", tint: .purple)
            }
            .settingsSearchAnchor("capacity")
            Button(localized("Clear Unpinned Items"), role: .destructive) {
                confirmingClearHistory = true
            }
            .alert(localized("Clear Unpinned Items"), isPresented: $confirmingClearHistory) {
                Button(localized("Cancel"), role: .cancel) {}
                Button(localized("Clear Unpinned Items"), role: .destructive) { clearHistory() }
            }
            .settingsSearchAnchor("clearHistory")
        } header: {
            Text(localized("Storage management"))
        } footer: {
            Text(localized("Pinned items are never expired or evicted."))
        }
    }

    private var pinnedItemsSection: some View {
        Section {
            SettingsPicker(localized("Pinned items presentation"), selection: $general.pinnedPresentation) {
                ForEach(PinnedPresentation.allCases) { Text($0.label).tag($0) }
            }.settingsSearchAnchor("pinnedPresentation")
            if general.pinnedPresentation == .separate {
                SettingsPicker(localized("Pinned window layout"), selection: $general.pinnedWindowStyle) {
                    ForEach(PinnedWindowStyle.allCases) { Text($0.label).tag($0) }
                }.settingsSearchAnchor("pinnedWindowStyle")
            }
            Text(
                localized(
                    "Use the pinned-items shortcut or menu item. In the clipboard panel it selects Pinned; a separate window only shows pinned items."
                )
            )
            .font(.caption).foregroundStyle(.secondary)
        } header: {
            Text(localized("Pinned items"))
        }
    }

    private var sensitiveAccessSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text(localized("Sensitive apps")).font(.headline)
                    .settingsSearchAnchor("sensitiveApps")
                Text(localized("Copies are kept temporarily, then deleted from WhiskyMac without undo."))
                    .font(.caption).foregroundStyle(.secondary)
                if general.sensitiveApps.isEmpty {
                    Text(localized("No sensitive apps added.")).foregroundStyle(.secondary)
                }
                ForEach(general.sensitiveApps) { app in
                    HStack {
                        Text(app.name)
                        Spacer()
                        Button(localized("Remove")) { general.sensitiveApps.removeAll { $0.bundleID == app.bundleID } }
                            .buttonStyle(.borderless)
                    }
                }
                Button(localized("Add sensitive app…")) { addExcludedApp(sensitive: true) }
                HStack {
                    Text(localized("Keep sensitive copies for"))
                    Spacer()
                    SensitiveRetentionField(value: $general.sensitiveRetentionMinutes)
                    Text(localized("minutes")).foregroundStyle(.secondary)
                    Stepper("", value: $general.sensitiveRetentionMinutes, in: SensitiveRetention.minutesRange)
                        .labelsHidden()
                        .accessibilityLabel(localized("Keep sensitive copies for"))
                }
                .settingsSearchAnchor("sensitiveRetention")
                Text(
                    localized(
                        "Enter 1–1440 minutes. Shortening the limit also applies to existing sensitive copies; increasing it only affects new copies."
                    )
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text(localized("Excluded apps")).font(.headline)
                    .settingsSearchAnchor("excludedApps")
                Text(localized("Copies from excluded apps are never recorded."))
                    .font(.caption).foregroundStyle(.secondary)
                if general.excludedApps.isEmpty {
                    Text(localized("No excluded apps added.")).foregroundStyle(.secondary)
                }
                ForEach(general.excludedApps) { app in
                    HStack(spacing: 9) {
                        if let icon = SourceAppStyle.resolve(bundleID: app.bundleID).icon {
                            Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                        }
                        Text(app.name)
                        Spacer()
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .beButton { general.excludedApps.removeAll { $0.bundleID == app.bundleID } }
                            .buttonStyle(.borderless)
                    }
                }
                SettingsRowLabel(localized("Add App…"), symbol: "hand.raised.fill", tint: .red)
                    .beButton { addExcludedApp() }
                    .buttonStyle(.plain)
            }
        } header: {
            Text(localized("Sensitive access"))
        } footer: {
            explanationDisclosure(localized("How sensitive access works"), isExpanded: $temporarySessionsExpanded) {
                Text(
                    localized(
                        "Sensitive copies stay in memory, outside disk history, search and undo. They start hidden and can be shown for 10 seconds. They expire at the selected limit or sooner when the app quits, the Mac sleeps or the memory limit is reached. Expiration does not clear the system clipboard or copies held by other apps."
                    ))
                Text(
                    localized(
                        "Explicit no-record markers and excluded apps always win. Existing normal history is not reclassified. An app can belong to only one list; adding it moves it from the other list. Source attribution is best effort."
                    ))
            }
        }
    }

    private var vimSection: some View {
        Section {
            Toggle(isOn: $general.vimNavigation) {
                SettingsRowLabel(localized("Vim navigation in the panel"), symbol: "keyboard", tint: .matcha)
            }
            .toggleStyle(SettingsToggleStyle())
            .settingsSearchAnchor("vim")
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
                        VimKeyField(action: action, store: vimBindings)
                        Image(systemName: "arrow.uturn.backward")
                            .beButton { vimBindings.reset(action) }
                            .buttonStyle(.borderless)
                            .disabled(!vimBindings.isCustomized(action))
                            .help(localized("Reset to default"))
                    }
                    .settingsSearchAnchor("vim.\(action.rawValue)")
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
                            .font(.caption2)
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
                    ShortcutRecorder(action: action, store: store)
                    Image(systemName: "arrow.uturn.backward")
                        .beButton { store.reset(action) }
                        .buttonStyle(.borderless)
                        .disabled(!store.isCustomized(action))
                        .help(localized("Reset to default"))
                }
                .settingsSearchAnchor("shortcut.\(action.rawValue)")
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
                Text(localized("Reset category")).font(.headline)
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
                            Text(category.explanation).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .settingsSearchAnchor("resetCategory")
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localized("Reset keyboard shortcuts"))
                    Text(localized("Only selected categories are reset."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(localized("Reset…"), role: .destructive) { confirmingReset = true }
                    .disabled(resetCategories.isEmpty)
            }
            .settingsSearchAnchor("resetShortcuts")
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

    private func addExcludedApp(sensitive: Bool = false) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { continue }
            let name =
                (bundle.infoDictionary?["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
            let app = ExcludedApp(bundleID: bundleID, name: name)
            if sensitive {
                general.addSensitiveApp(app)
            } else {
                general.excludeApp(app)
            }
        }
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.55))
            .frame(height: 0.5)
            .accessibilityHidden(true)
    }
}

private struct SettingsSurfaceGroup: View {
    let section: SectionConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !section.header.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(section.header) { header in
                        header
                    }
                }
                .font(.headline)
                .padding(.leading, 4)
            }
            VStack(spacing: 0) {
                IndexedForEach(section.content) { index, row in
                    if index > 0 {
                        SettingsDivider()
                            .padding(.leading, 16)
                    }
                    row
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .id(row.containerValues.settingsSearchAnchorID ?? "settings-row-\(index)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingsSurface(
                in: RoundedRectangle(cornerRadius: SettingsSurface.groupCornerRadius, style: .continuous)
            )
            if !section.footer.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(section.footer) { footer in
                        footer
                    }
                }
                .font(.caption)
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
private struct VimKeyField: View {
    let action: VimAction
    @ObservedObject var store: VimBindingsStore
    @State private var text = ""
    @FocusState private var focused: Bool
    @SettingsAccessibility private var accessibility

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(.system(.body, design: .monospaced))
            .multilineTextAlignment(.center)
            .frame(width: 44)
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .settingsSurface(in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(focused ? Color.matcha : .clear, lineWidth: 1.5)
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
private struct ShortcutRecorder: View {
    let action: KeyAction
    @ObservedObject var store: KeyBindingsStore
    @SettingsAccessibility private var accessibility
    @State private var isHovering = false

    private var isRecording: Bool {
        store.recordingAction == action
    }

    var body: some View {
        Text(isRecording ? localized("Type shortcut…") : store.label(for: action))
            .font(.system(.body, design: .rounded).weight(.medium))
            .frame(minWidth: 76)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .settingsSurface(in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .background(
                Color.matcha.opacity(isRecording ? 0.2 : (isHovering ? 0.055 : 0)),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isRecording ? Color.matcha : .clear, lineWidth: 1.5)
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

private struct SettingsToggleStyle: ToggleStyle {
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

private struct SettingsPicker<Selection: Hashable, Content: View, Label: View>: View {
    @Binding var selection: Selection
    let content: Content
    let label: Label

    init(selection: Binding<Selection>, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        _selection = selection
        self.content = content()
        self.label = label()
    }

    init(_ title: String, selection: Binding<Selection>, @ViewBuilder content: () -> Content) where Label == Text {
        self.init(selection: selection, content: content, label: { Text(title) })
    }

    var body: some View {
        HStack(spacing: 16) {
            label.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Picker(selection: $selection) {
                content
            } label: {
                label
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }
}

/// Keep an editable draft separate from the clamped preference binding.
private struct SpotlightPointField: View {
    let title: String
    @Binding var value: Double
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: $draft)
            .textFieldStyle(.roundedBorder)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .frame(width: 72)
            .accessibilityLabel(title)
            .focused($focused)
            .onAppear { sync() }
            .onSubmit { commit() }
            .onChange(of: focused) { _, active in if !active { commit() } }
            .onChange(of: value) { _, _ in sync() }
    }

    private func sync() { draft = String(Int(value)) }
    private func commit() {
        if let parsed = SpotlightPreferences.points(from: draft) { value = parsed }
        sync()
    }
}

/// Commit whole minutes on Enter/focus loss; do not clamp a half-typed number.
private struct SensitiveRetentionField: View {
    @Binding var value: Int
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(localized("Keep sensitive copies for"), text: $draft)
            .textFieldStyle(.roundedBorder)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .frame(width: 72)
            .accessibilityLabel(localized("Keep sensitive copies for"))
            .focused($focused)
            .onAppear { sync() }
            .onSubmit { commit() }
            .onChange(of: focused) { _, active in if !active { commit() } }
            .onChange(of: value) { _, _ in sync() }
    }

    private func sync() { draft = String(value) }
    private func commit() {
        if let minutes = SensitiveRetention.minutes(from: draft) { value = minutes }
        sync()
    }
}

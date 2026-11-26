// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import ApplicationServices
import SwiftUI

@available(macOS 26, *)
extension MacOS26SettingsView {
    @ViewBuilder
    func sectionContent(_ section: SettingsSectionID) -> some View {
        switch section {
        case .debugging:
            debugSection
        case .startup:
            startupSection
        case .menuAndDock:
            menuAndDockSection
        case .language:
            languageSection
        case .sounds:
            copySoundSection
        case .statusIcons:
            statusIconsSection
        case .navigation:
            navigationSection
        case .colors:
            displayAndThemeSections
        case .cards:
            cardsSection
        case .filterTags:
            filterTagsSection
            filterCategoryOrderSection
        case .retention:
            recordingSettingsSection
        case .clearHistory:
            storageManagementSection
        case .filters:
            filtersSection
        case .normalInteractions:
            interactionModeSection(title: localized("Normal mode"), bindings: $general.interactions, privacyMode: false)
        case .privacyInteractions:
            interactionModeSection(
                title: localized("Privacy mode"), bindings: $general.privacyInteractions, privacyMode: true)
        case .pinnedItems:
            pinnedItemsSection
        case .screenSharingProtection:
            screenSharingProtectionSection
        case .sensitiveAccess:
            sensitiveAccessSection
        case .secretRecognition:
            secretRecognitionSection
        case .network:
            networkSection
        case .globalShortcuts:
            shortcutsSection(global: true)
        case .panelShortcuts:
            shortcutsSection(global: false)
        case .vim:
            vimSection
        case .resetShortcuts:
            restoreSection
        case .aboutApp:
            MacOS26AboutSettings(
                distribution: distribution, updateChecker: updateChecker, general: general,
                developerMode: developerMode, buildInfo: buildInfo)
        case .aboutDeveloper:
            MacOS26DeveloperSettings(distribution: distribution)
        case .licenses:
            EmptyView()
        }
    }

    private var debugSection: some View {
        Section {
            Button(localized("Show first-launch guide"), systemImage: "book") {
                if developerMode.showsTools { showWelcomeGuide() }
            }
            .macOS26SettingsAction()
            .macOS26SettingsSearchAnchor("showWelcomeGuide")
            Button(localized("Export logs…"), systemImage: "square.and.arrow.up", action: requestDiagnosticsExport)
                .macOS26SettingsAction()
                .disabled(exportingDiagnostics)
                .macOS26SettingsSearchAnchor("exportDiagnostics")
        } header: {
            Text(localized("Debug tools"))
        } footer: {
            Text(localized("Reopens the welcome guide from the beginning without resetting its completion status."))
        }
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

    private var startupSection: some View {
        Section {
            Toggle(
                localized("Launch WhiskyMac at login"),
                isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) })
            )
            .macOS26SettingsSearchAnchor("launch")
            if let error = loginItem.lastError {
                Text(error)
                    .font(typography.font(.caption))
                    .foregroundStyle(.red)
            }
            if distribution.checksForUpdates {
                Toggle(localized("Check for updates at launch"), isOn: $general.checkForUpdates)
                    .macOS26SettingsSearchAnchor("startupUpdates")
            }
            Toggle(localized("Lightweight mode"), isOn: $general.lightweightMode)
                .macOS26SettingsSearchAnchor("lightweightMode")
        } header: {
            Text(localized("Startup and loading"))
        } footer: {
            Text(
                localized(
                    "Lightweight mode loads thumbnails only as needed when you open the clipboard panel. Closing the panel clears the thumbnail cache to reduce memory use."
                ))
        }
    }

    private var menuAndDockSection: some View {
        Section {
            MacOS26MenuRow(localized("Menu bar icon click"), selection: $appearance.statusClick, display: \.label) {
                ForEach(StatusClickAction.allCases) { option in Text(option.label).tag(option) }
            }
            .macOS26SettingsSearchAnchor("statusClick")
            MacOS26MenuRow(localized("Dock icon"), selection: $appearance.dockIcon, display: \.label) {
                ForEach(DockIconMode.allCases) { option in Text(option.label).tag(option) }
            }
            .macOS26SettingsSearchAnchor("dockIcon")
        } header: {
            Text(localized("Menu bar and Dock"))
        } footer: {
            Text(
                localized(
                    "Right-click always opens the menu. Follow windows shows the Dock icon for Settings and welcome windows only."
                ))
        }
    }

    private var languageSection: some View {
        Section {
            MacOS26MenuRow(localized("Language"), selection: $appearance.language, display: \.label) {
                ForEach(AppLanguage.allCases) { option in Text(option.label).tag(option) }
            }
            .macOS26SettingsSearchAnchor("language")
        } header: {
            Text(localized("Language"))
        }
    }

    private var copySoundSection: some View {
        Section {
            Toggle(localized("Play a sound when a new copy is recorded"), isOn: $general.copySound.onCapture)
                .macOS26SettingsSearchAnchor("captureSound")
            Toggle(localized("Play a sound when copying from history"), isOn: $general.copySound.onHistoryCopy)
                .macOS26SettingsSearchAnchor("historySound")
            MacOS26MenuRow(localized("Copy sound"), selection: $general.copySound.sound, display: \.label) {
                ForEach(CopySound.Collection.allCases) { collection in
                    Section(collection.rawValue) {
                        ForEach(collection.sounds) { sound in Text(sound.label).tag(sound) }
                    }
                }
            }
            .macOS26SettingsSearchAnchor("copySound")
            HStack {
                Text(localized("Sound volume"))
                Slider(value: $general.copySound.volume, in: 0...1)
                    .accessibilityLabel(localized("Sound volume"))
                Button(localized("Preview sound"), systemImage: "play.fill") {
                    copySoundPlayer.preview(general.copySound)
                }
                .macOS26SettingsAction()
            }
            .macOS26SettingsSearchAnchor("volume")
        } header: {
            Text(localized("Sounds and effects"))
        } footer: {
            Text(
                localized(
                    "Paste actions stay silent. Automatic sounds are muted during Privacy Mode; sensitive and excluded copies stay silent."
                ))
        }
    }

    private var statusIconsSection: some View {
        Section {
            MacOS26StatusSymbolPickerRow(
                title: localized("Default mode icon"), selection: $appearance.defaultStatusSymbol,
                defaultName: AppSymbol.defaultStatusName
            )
            .macOS26SettingsSearchAnchor("defaultIcon")
            MacOS26StatusSymbolPickerRow(
                title: localized("Privacy mode icon"), selection: $appearance.privacyStatusSymbol,
                defaultName: AppSymbol.defaultPrivacyName
            )
            .macOS26SettingsSearchAnchor("privacyIcon")
        } header: {
            Text(localized("Menu bar icons"))
        }
    }

    private var navigationSection: some View {
        Section {
            MacOS26MenuRow(localized("Settings layout"), selection: $appearance.navigation, display: \.label) {
                ForEach(SettingsNavigation.allCases) { option in Text(option.label).tag(option) }
            }
            .macOS26SettingsSearchAnchor("navigation")
        } header: {
            Text(localized("Settings navigation"))
        }
    }

    @ViewBuilder private var displayAndThemeSections: some View {
        Section {
            MacOS26MenuRow(
                localized("Settings window appearance"), selection: $appearance.settingsAppearance, display: \.label
            ) {
                ForEach(AppearanceMode.allCases) { option in Text(option.label).tag(option) }
            }
            .macOS26SettingsSearchAnchor("settingsAppearance")
            MacOS26MenuRow(
                localized("Clipboard appearance"), selection: $appearance.clipboardAppearance, display: \.label
            ) {
                ForEach(AppearanceMode.allCases) { option in Text(option.label).tag(option) }
            }
            .macOS26SettingsSearchAnchor("clipboardAppearance")
        } header: {
            Text(localized("Light and dark appearance"))
        }
        Section {
            MacOS26MenuRow(localized("Accent color"), selection: $appearance.accentMode, display: \.label) {
                ForEach(AccentMode.allCases) { option in Text(option.label).tag(option) }
            }
            .macOS26SettingsSearchAnchor("accent")
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
                .macOS26SettingsSearchAnchor("customAccent")
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
            .macOS26SettingsSearchAnchor("interfaceFontSize")
            Button(localized("Restore default size")) {
                appearance.setInterfaceFontPercent(InterfaceTypography.standard.percent)
            }
            .macOS26SettingsAction()
            .disabled(appearance.interfaceTypography.isStandard)
            Toggle(
                localized("Apply interface font size to plain text"),
                isOn: Binding(
                    get: { appearance.interfaceTypography.appliesToPlainText },
                    set: appearance.setPlainTextFollowsInterface)
            )
            .macOS26SettingsSearchAnchor("interfaceFontPlainText")
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
            MacOS26SizeSettingEditor(
                title: localized("Card size"), savedValue: general.cardSide,
                defaultValue: GeneralSettingsStore.defaultCardSide, range: GeneralSettingsStore.cardSideRange,
                draft: $cardSizeDraft, save: general.setCardSide, previewOnScreen: previewSizingOnScreen
            ) {
                MacOS26CardSizeSample(side: CGFloat(cardSizeDraft.value(saved: general.cardSide)))
                    .interfaceType(.standard)
                    .environment(\.colorScheme, appearance.clipboardAppearance.colorScheme ?? systemColorScheme)
            }
            .macOS26SettingsSearchAnchor("cardSize")
        } header: {
            Text(localized("Clipboard cards"))
        } footer: {
            Text(localized("Changes are saved only when you choose Save current setting."))
        }
    }

    private var filterTagsSection: some View {
        Section {
            MacOS26SizeSettingEditor(
                title: localized("Tag size"), savedValue: general.filterTagScale,
                defaultValue: GeneralSettingsStore.defaultFilterTagScale,
                range: GeneralSettingsStore.filterTagScaleRange,
                usesPercentage: true, draft: $tagSizeDraft, save: general.setFilterTagScale,
                previewOnScreen: previewSizingOnScreen
            ) {
                MacOS26FilterTagSizeSample(scale: tagSizeDraft.value(saved: general.filterTagScale))
                    .environment(\.colorScheme, appearance.clipboardAppearance.colorScheme ?? systemColorScheme)
            }
            .macOS26SettingsSearchAnchor("filterTagSize")
        } header: {
            Text(localized("Filter tags"))
        } footer: {
            Text(localized("Changes are saved only when you choose Save current setting."))
        }
    }

    private var filterCategoryOrderSection: some View {
        Section {
            MacOS26FilterCategoryOrderEditor(
                settings: general, previewScheme: appearance.clipboardAppearance.colorScheme ?? systemColorScheme
            )
            .macOS26SettingsSearchAnchor("filterCategoryOrder")
        } header: {
            Text(localized("Category tag order"))
        }
    }

    private func previewSizingOnScreen() {
        previewClipboard(
            cardSizeDraft.value(saved: general.cardSide), tagSizeDraft.value(saved: general.filterTagScale))
    }

    private var filtersSection: some View {
        Section {
            MacOS26MenuRow(localized("Filter trigger"), selection: $general.appFilterTrigger, display: \.label) {
                ForEach(AppFilterTrigger.allCases) { trigger in Text(trigger.label).tag(trigger) }
            }
            .macOS26SettingsSearchAnchor("filterTrigger")
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
    }

    private func interactionModeSection(title: String, bindings: Binding<InteractionBindings>, privacyMode: Bool)
        -> some View
    {
        Section {
            interactionPicker(
                localized("Single click"), key: \.singleClick, bindings: bindings, privacyMode: privacyMode
            )
            .macOS26SettingsSearchAnchor(privacyMode ? "private.single" : "normal.single")
            interactionPicker(
                localized("Double click"), key: \.doubleClick, bindings: bindings, privacyMode: privacyMode
            )
            .macOS26SettingsSearchAnchor(privacyMode ? "private.double" : "normal.double")
            interactionPicker(localized("Right click"), key: \.rightClick, bindings: bindings, privacyMode: privacyMode)
                .macOS26SettingsSearchAnchor(privacyMode ? "private.right" : "normal.right")
            Text(localized("Hover preview")).font(typography.font(.caption)).foregroundStyle(.secondary)
            MacOS26MenuRow(
                localized("Hover after a short delay"), selection: bindings.hover,
                display: { action in
                    privacyMode && action == .preview ? localized("Reveal a small area") : action.label
                }
            ) {
                Text(CardAction.none.label).tag(CardAction.none)
                Text(privacyMode ? localized("Reveal a small area") : CardAction.preview.label).tag(CardAction.preview)
            }
            .macOS26SettingsSearchAnchor(privacyMode ? "private.hover" : "normal.hover")
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
                .macOS26SettingsSearchAnchor(privacyMode ? "private.delay" : "normal.delay")
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
        return MacOS26MenuRow(
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
            .macOS26SettingsSearchAnchor("manualPrivacy")
            Toggle(
                localized("Turn on protection when screen sharing is detected"),
                isOn: Binding(get: { privacy.automaticEnabled }, set: { privacy.setAutomaticEnabled($0) })
            )
            .macOS26SettingsSearchAnchor("automaticPrivacy")
            sharingProtectionStatus
            DisclosureGroup(localized("Detection coverage"), isExpanded: $detectionCoverageExpanded) {
                Text(
                    localized(
                        "Uses Accessibility to detect Zoom and Teams sharing toolbars. Detection may vary by app version and language. System screen sharing, remote desktop, screen recording and browser tabs are outside its scope. Turn on privacy protection before sharing sensitive content."
                    )
                )
                .font(typography.font(.callout))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .disclosureGroupStyle(MacOS26DisclosureRowStyle())
            .macOS26SettingsSearchAnchor("detection")
            if privacy.automaticEnabled {
                HStack(spacing: 10) {
                    MacOS26SettingLabel(
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
                .buttonStyle(.plain)
                .macOS26SettingsSearchAnchor("accessibility")
            }
        } header: {
            Text(SettingsSectionID.screenSharingProtection.title.localized)
        }

        Section {
            Toggle(localized("Allow search in Privacy Mode"), isOn: $privacy.allowSearchWhileProtected)
                .macOS26SettingsSearchAnchor("privacySearch")
            Toggle(
                localized("Allow type and tag filtering in Privacy Mode"), isOn: $privacy.allowFilteringWhileProtected
            )
            .macOS26SettingsSearchAnchor("privacyFilters")
            Toggle(localized("Allow app filtering in Privacy Mode"), isOn: $privacy.allowAppFilteringWhileProtected)
                .macOS26SettingsSearchAnchor("privacyAppFilters")
            Toggle(
                localized("Allow Handoff filtering in Privacy Mode"), isOn: $privacy.allowHandoffFilteringWhileProtected
            )
            .macOS26SettingsSearchAnchor("privacyHandoffFilters")
            Text(
                localized(
                    "App filters show application names in the filter bar, independently of source labels on cards. Clipboard content stays hidden."
                )
            )
            .font(typography.font(.caption)).foregroundStyle(.secondary)
            Toggle(localized("Show source apps in Privacy Mode"), isOn: $privacy.showSourceAppsWhileProtected)
                .macOS26SettingsSearchAnchor("privacySources")
        } header: {
            Text(localized("Protection mode options"))
        } footer: {
            Text(
                localized(
                    "These options apply whenever protection is on. Search terms and allowed app names are visible on screen and accessible to assistive technologies. Clipboard content stays hidden. Protection triggered by detection blocks hover reveals."
                ))
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
                    MacOS26NumericField(
                        title: localized("Diameter"), value: $privacy.spotlight.diameter, format: { String(Int($0)) },
                        parse: SpotlightPreferences.points(from:))
                    Text(localized("pt")).foregroundStyle(.secondary)
                }
                Slider(value: $privacy.spotlight.diameter, in: SpotlightPreferences.diameterRange, step: 10)
                    .accessibilityLabel(localized("Diameter"))
                    .accessibilityValue(spotlightPoints(privacy.spotlight.diameter))
            }
            .macOS26SettingsSearchAnchor("diameter")
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(localized("Edge blur radius"))
                    Spacer()
                    MacOS26NumericField(
                        title: localized("Edge blur radius"), value: $privacy.spotlight.blurRadius,
                        format: { String(Int($0)) }, parse: SpotlightPreferences.points(from:))
                    Text(localized("pt")).foregroundStyle(.secondary)
                }
                Slider(value: $privacy.spotlight.blurRadius, in: privacy.spotlight.blurRange, step: 1)
                    .accessibilityLabel(localized("Edge blur radius"))
                    .accessibilityValue(spotlightPoints(privacy.spotlight.blurRadius))
            }
            .macOS26SettingsSearchAnchor("blur")
            Button(localized("Restore default values"), systemImage: "arrow.counterclockwise") {
                privacy.spotlight = SpotlightPreferences()
            }
            .macOS26SettingsAction()
            .disabled(privacy.spotlight == SpotlightPreferences())
            .macOS26SettingsSearchAnchor("resetSpotlight")

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
                .macOS26SettingsSearchAnchor("linkPreviews")
        } header: {
            Text(localized("Online content"))
        } footer: {
            Text(localized("A copied link is looked up once for its title and image. Off, nothing leaves this Mac."))
        }
    }

    private var recordingSettingsSection: some View {
        Section {
            MacOS26MenuRow(localized("Keep history for"), selection: $general.retentionPeriod, display: \.label) {
                ForEach(RetentionPeriodOption.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .macOS26SettingsSearchAnchor("retention")
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
            MacOS26MenuRow(
                localized("History capacity"), selection: $general.capacity, display: GeneralSettingsStore.capacityLabel
            ) {
                ForEach(GeneralSettingsStore.capacityChoices, id: \.self) { choice in
                    Text(GeneralSettingsStore.capacityLabel(choice)).tag(choice)
                }
            }
            .macOS26SettingsSearchAnchor("capacity")
            Button(localized("Clear Unpinned Items"), systemImage: "trash", role: .destructive) {
                confirmingClearHistory = true
            }
            .macOS26SettingsAction()
            .alert(localized("Clear Unpinned Items"), isPresented: $confirmingClearHistory) {
                Button(localized("Cancel"), role: .cancel) {}
                Button(localized("Clear Unpinned Items"), role: .destructive) { clearHistory() }
            }
            .macOS26SettingsSearchAnchor("clearHistory")
        } header: {
            Text(localized("Storage management"))
        } footer: {
            Text(localized("Pinned items are never expired or evicted."))
        }
    }

    private var pinnedItemsSection: some View {
        Section {
            MacOS26MenuRow(
                localized("Pinned items presentation"), selection: $general.pinnedPresentation, display: \.label
            ) {
                ForEach(PinnedPresentation.allCases) { Text($0.label).tag($0) }
            }
            .macOS26SettingsSearchAnchor("pinnedPresentation")
            if general.pinnedPresentation == .separate {
                MacOS26MenuRow(
                    localized("Pinned window layout"), selection: $general.pinnedWindowStyle, display: \.label
                ) {
                    ForEach(PinnedWindowStyle.allCases) { Text($0.label).tag($0) }
                }
                .macOS26SettingsSearchAnchor("pinnedWindowStyle")
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
                .macOS26SettingsSearchAnchor("recognizeSecrets")
            if general.secretRecognition.enabled {
                Toggle(localized("Secret masking"), isOn: $general.secretRecognition.mask)
                    .macOS26SettingsSearchAnchor("maskSecrets")
                Toggle(localized("Categorize secrets"), isOn: $general.secretRecognition.classify)
                    .macOS26SettingsSearchAnchor("classifySecrets")
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
            .macOS26SettingsSearchAnchor("sensitiveApps")
            sensitiveRetentionRow
                .macOS26SettingsSearchAnchor("sensitiveRetention")
            sensitiveAppRows($general.sensitiveApps, emptyMessage: localized("No sensitive apps added."))
            addPrivacyAppButton(localized("Add sensitive app…"), sensitive: true)
        } header: {
            Text(localized("Sensitive apps"))
        }

        Section {
            privacyNotice(symbol: "hand.raised.fill", tint: accent) {
                Text(localized("Copies from excluded apps are never recorded."))
            }
            .macOS26SettingsSearchAnchor("excludedApps")
            sensitiveAppRows($general.excludedApps, emptyMessage: localized("No excluded apps added."))
            addPrivacyAppButton(localized("Add App…"), sensitive: false)
        } header: {
            Text(localized("Excluded apps"))
        }

        Section {
            DisclosureGroup(localized("How sensitive access works"), isExpanded: $temporarySessionsExpanded) {
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
            .disclosureGroupStyle(MacOS26DisclosureRowStyle())
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
                    MacOS26NumericField(
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
        MacOS26SettingLabel(title, symbol: "plus", tint: accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .beButton {
                addExcludedApp(sensitive: sensitive)
            }
            .buttonStyle(.plain)
    }

    private var vimSection: some View {
        Section {
            Toggle(localized("Vim navigation in the panel"), isOn: $general.vimNavigation)
                .macOS26SettingsSearchAnchor("vim")
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
                        MacOS26VimKeyField(action: action, store: vimBindings)
                        Button(localized("Reset to default"), systemImage: "arrow.uturn.backward") {
                            vimBindings.reset(action)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .disabled(!vimBindings.isCustomized(action))
                        .help(localized("Reset to default"))
                    }
                    .macOS26SettingsSearchAnchor("vim.\(action.rawValue)")
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
                            .background(.fill.tertiary, in: .capsule)
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
                    MacOS26ShortcutRecorder(action: action, store: store)
                    Button(localized("Reset to default"), systemImage: "arrow.uturn.backward") { store.reset(action) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .disabled(!store.isCustomized(action))
                        .help(localized("Reset to default"))
                }
                .macOS26SettingsSearchAnchor("shortcut.\(action.rawValue)")
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
            .macOS26SettingsSearchAnchor("resetCategory")
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
                .macOS26SettingsAction()
                .disabled(resetCategories.isEmpty)
            }
            .macOS26SettingsSearchAnchor("resetShortcuts")
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
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) {
                apps.forEach(add)
            }
        }
    }
}

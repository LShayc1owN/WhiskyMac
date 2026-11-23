// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import ApplicationServices
import SwiftUI
import UniformTypeIdentifiers

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
            colorsSection
        case .cards:
            cardsSection
        case .filterTags:
            filterTagsSection
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
        case .screenPrivacy:
            screenPrivacySection
        case .privacyVisibility:
            privacyVisibilitySection
        case .sensitiveAccess:
            sensitiveAccessSection
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
            MacOS26DeveloperSettings()
        case .licenses:
            EmptyView()
        }
    }

    private var debugSection: some View {
        Section {
            Button(localized("Show first-launch guide")) {
                if developerMode.showsTools { showWelcomeGuide() }
            }
            .macOS26SettingsSearchAnchor("showWelcomeGuide")
            Button(localized("Export logs…"), action: requestDiagnosticsExport)
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
            Toggle(isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) })) {
                MacOS26SettingLabel(localized("Launch WhiskyMac at login"), symbol: "power", tint: .green)
            }
            .macOS26SettingsSearchAnchor("launch")
            if let error = loginItem.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if distribution.checksForUpdates {
                Toggle(isOn: $general.checkForUpdates) {
                    MacOS26SettingLabel(
                        localized("Check for updates at launch"), symbol: "arrow.triangle.2.circlepath", tint: .blue)
                }
                .macOS26SettingsSearchAnchor("startupUpdates")
            }
            Toggle(isOn: $general.lightweightMode) {
                MacOS26SettingLabel(localized("Lightweight mode"), symbol: "leaf", tint: .green)
            }
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
            MacOS26MenuRow(localized("Menu bar icon click"), selection: $appearance.statusClick) {
                ForEach(StatusClickAction.allCases) { option in Text(option.label).tag(option) }
            }
            .macOS26SettingsSearchAnchor("statusClick")
            MacOS26MenuRow(localized("Dock icon"), selection: $appearance.dockIcon) {
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
            MacOS26MenuRow(localized("Language"), selection: $appearance.language) {
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
            MacOS26MenuRow(localized("Copy sound"), selection: $general.copySound.sound) {
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
                Button(localized("Preview sound")) { copySoundPlayer.preview(general.copySound) }
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
            MacOS26MenuRow(localized("Settings layout"), selection: $appearance.navigation) {
                ForEach(SettingsNavigation.allCases) { option in Text(option.label).tag(option) }
            }
            .macOS26SettingsSearchAnchor("navigation")
        } header: {
            Text(localized("Settings navigation"))
        }
    }

    private var colorsSection: some View {
        Section {
            MacOS26MenuRow(localized("Settings window appearance"), selection: $appearance.settingsAppearance) {
                ForEach(AppearanceMode.allCases) { option in Text(option.label).tag(option) }
            }
            .macOS26SettingsSearchAnchor("settingsAppearance")
            MacOS26MenuRow(localized("Clipboard appearance"), selection: $appearance.clipboardAppearance) {
                ForEach(AppearanceMode.allCases) { option in Text(option.label).tag(option) }
            }
            .macOS26SettingsSearchAnchor("clipboardAppearance")
            MacOS26MenuRow(localized("Accent color"), selection: $appearance.accentMode) {
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
            Text(localized("Colors"))
        } footer: {
            Text(localized("The accent color also highlights the selected clipboard card."))
        }
    }

    private var cardsSection: some View {
        Section {
            MacOS26SizeSettingEditor(
                title: localized("Card size"), symbol: "rectangle.3.group", savedValue: general.cardSide,
                defaultValue: GeneralSettingsStore.defaultCardSide, range: GeneralSettingsStore.cardSideRange,
                draft: $cardSizeDraft, save: general.setCardSide, previewOnScreen: previewSizingOnScreen
            ) {
                MacOS26CardSizeSample(side: CGFloat(cardSizeDraft.value(saved: general.cardSide)))
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
                title: localized("Tag size"), symbol: "tag", savedValue: general.filterTagScale,
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

    private func previewSizingOnScreen() {
        previewClipboard(
            cardSizeDraft.value(saved: general.cardSide), tagSizeDraft.value(saved: general.filterTagScale))
    }

    private var filtersSection: some View {
        Section {
            MacOS26MenuRow(localized("Filter trigger"), selection: $general.appFilterTrigger) {
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
            Text(localized("Hover preview")).font(.caption).foregroundStyle(.secondary)
            MacOS26MenuRow(localized("Hover after a short delay"), selection: bindings.hover) {
                Text(CardAction.none.label).tag(CardAction.none)
                Text(privacyMode ? localized("Reveal a small area") : CardAction.preview.label).tag(CardAction.preview)
            }
            .macOS26SettingsSearchAnchor(privacyMode ? "private.hover" : "normal.hover")
            if bindings.wrappedValue.hover == .preview {
                HStack {
                    Text(localized("Hover delay (seconds)"))
                    Spacer()
                    TextField("", value: bindings.hoverDelay, format: .number.precision(.fractionLength(1)))
                        .multilineTextAlignment(.trailing).frame(width: 64)
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
        MacOS26MenuRow(
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

    private var screenPrivacySection: some View {
        Section {
            Toggle(
                localized("Manual Privacy Mode"),
                isOn: Binding(
                    get: { privacy.isManuallyProtected }, set: { privacy.setProtected($0) })
            )
            .macOS26SettingsSearchAnchor("manualPrivacy")
            Toggle(
                localized("Automatic protection (limited detection)"),
                isOn: Binding(get: { privacy.automaticEnabled }, set: { privacy.setAutomaticEnabled($0) })
            )
            .macOS26SettingsSearchAnchor("automaticPrivacy")
            VStack(alignment: .leading, spacing: 8) {
                Label(privacy.statusText, systemImage: privacy.isProtected ? "lock.shield.fill" : "shield")
                    .font(.callout).foregroundStyle(privacy.isProtected ? Color.accentColor : Color.secondary)
                Text(localized("Automatic detection is limited. Use manual protection before important sharing."))
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup(localized("Detection coverage"), isExpanded: $detectionCoverageExpanded) {
                    Text(
                        localized(
                            "Checks Zoom and Teams sharing toolbar titles using Accessibility. Client versions and languages may not match. System sharing, remote desktop, recording and browser tabs are not covered. Enable manual protection before important sharing."
                        )
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            .macOS26SettingsSearchAnchor("detection")
            if privacy.automaticEnabled {
                Button(localized("Allow Accessibility for toolbar detection…")) {
                    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                    _ = AXIsProcessTrustedWithOptions(options)
                }
                .macOS26SettingsSearchAnchor("accessibility")
            }
        } header: {
            Text(localized("Screen privacy"))
        }
    }

    private var privacyVisibilitySection: some View {
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
            .font(.caption).foregroundStyle(.secondary)
            Toggle(localized("Show source apps in Privacy Mode"), isOn: $privacy.showSourceAppsWhileProtected)
                .macOS26SettingsSearchAnchor("privacySources")
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
            Button(localized("Restore default values")) { privacy.spotlight = SpotlightPreferences() }
                .disabled(privacy.spotlight == SpotlightPreferences())
                .macOS26SettingsSearchAnchor("resetSpotlight")

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
                MacOS26SettingLabel(localized("Fetch link previews"), symbol: "link", tint: .teal)
            }
            .macOS26SettingsSearchAnchor("linkPreviews")
        } header: {
            Text(localized("Online content"))
        } footer: {
            Text(localized("A copied link is looked up once for its title and image. Off, nothing leaves this Mac."))
        }
    }

    private var recordingSettingsSection: some View {
        Section {
            MacOS26MenuRow(selection: $general.retentionPeriod) {
                ForEach(RetentionPeriodOption.allCases) { option in
                    Text(option.label).tag(option)
                }
            } label: {
                MacOS26SettingLabel(localized("Keep history for"), symbol: "clock", tint: .orange)
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
            MacOS26MenuRow(selection: $general.capacity) {
                ForEach(GeneralSettingsStore.capacityChoices, id: \.self) { choice in
                    Text(GeneralSettingsStore.capacityLabel(choice)).tag(choice)
                }
            } label: {
                MacOS26SettingLabel(localized("History capacity"), symbol: "tray.full", tint: .purple)
            }
            .macOS26SettingsSearchAnchor("capacity")
            Button(localized("Clear Unpinned Items"), role: .destructive) {
                confirmingClearHistory = true
            }
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
            MacOS26MenuRow(localized("Pinned items presentation"), selection: $general.pinnedPresentation) {
                ForEach(PinnedPresentation.allCases) { Text($0.label).tag($0) }
            }
            .macOS26SettingsSearchAnchor("pinnedPresentation")
            if general.pinnedPresentation == .separate {
                MacOS26MenuRow(localized("Pinned window layout"), selection: $general.pinnedWindowStyle) {
                    ForEach(PinnedWindowStyle.allCases) { Text($0.label).tag($0) }
                }
                .macOS26SettingsSearchAnchor("pinnedWindowStyle")
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
                    .macOS26SettingsSearchAnchor("sensitiveApps")
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
                    MacOS26NumericField(
                        title: localized("Keep sensitive copies for"), value: $general.sensitiveRetentionMinutes,
                        format: { String($0) }, parse: SensitiveRetention.minutes(from:))
                    Text(localized("minutes")).foregroundStyle(.secondary)
                    Stepper("", value: $general.sensitiveRetentionMinutes, in: SensitiveRetention.minutesRange)
                        .labelsHidden()
                        .accessibilityLabel(localized("Keep sensitive copies for"))
                }
                .macOS26SettingsSearchAnchor("sensitiveRetention")
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
                    .macOS26SettingsSearchAnchor("excludedApps")
                Text(localized("Copies from excluded apps are never recorded."))
                    .font(.caption).foregroundStyle(.secondary)
                if general.excludedApps.isEmpty {
                    Text(localized("No excluded apps added.")).foregroundStyle(.secondary)
                }
                ForEach(general.excludedApps) { app in
                    HStack(spacing: 9) {
                        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                                .resizable()
                                .frame(width: 22, height: 22)
                                .accessibilityHidden(true)
                        }
                        Text(app.name)
                        Spacer()
                        Button(localized("Remove"), systemImage: "xmark.circle.fill") {
                            general.excludedApps.removeAll { $0.bundleID == app.bundleID }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                }
                Button(localized("Add App…"), systemImage: "plus") { addExcludedApp() }
            }
        } header: {
            Text(localized("Sensitive access"))
        } footer: {
            DisclosureGroup(localized("How sensitive access works"), isExpanded: $temporarySessionsExpanded) {
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
                MacOS26SettingLabel(localized("Vim navigation in the panel"), symbol: "keyboard", tint: .matcha)
            }
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
                            .font(.caption2)
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
            .macOS26SettingsSearchAnchor("resetCategory")
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

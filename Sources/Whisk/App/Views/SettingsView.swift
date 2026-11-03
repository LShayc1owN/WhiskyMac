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

    @ObservedObject var appearance = AppearanceSettingsStore()
    @State private var copySoundPlayer = CopySoundPlayer()
    @State private var confirmingReset = false
    @State var selectedPage = SettingsPage.general
    @SettingsAccessibility private var accessibility
    @FocusState private var focusedNavigation: SettingsPage?
    @Namespace private var navigationNamespace

    var body: some View {
        settingsGlassContainer(spacing: 16) {
            ZStack {
                SettingsWindowBackdrop().ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    SettingsDivider()
                    if appearance.navigation == .top {
                        topNavigation
                            .transition(.opacity)
                        SettingsDivider()
                    }
                    HStack(spacing: 0) {
                        if appearance.navigation == .sidebar {
                            sidebarNavigation
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                            Divider().opacity(0.55)
                        }
                        pageContent
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .tint(appearance.accent)
        .frame(width: SettingsWindowSize.width)
        .frame(
            minHeight: SettingsWindowSize.minimumHeight, idealHeight: SettingsWindowSize.height,
            maxHeight: SettingsWindowSize.height
        )
        .animation(navigationAnimation, value: appearance.navigation)
        .animation(contentAnimation, value: selectedPage)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                appearance.navigation = appearance.navigation == .top ? .sidebar : .top
            } label: {
                Label(
                    appearance.navigation == .top
                        ? localized("Use sidebar navigation") : localized("Use top navigation"),
                    systemImage: appearance.navigation == .top ? "sidebar.left" : "rectangle.topthird.inset.filled"
                )
                .labelStyle(.iconOnly)
                .font(.system(size: 14))
            }
            .buttonStyle(SettingsGlassButtonStyle())
            .help(
                appearance.navigation == .top
                    ? localized("Use sidebar navigation") : localized("Use top navigation")
            )
            .accessibilityLabel(
                appearance.navigation == .top
                    ? localized("Use sidebar navigation") : localized("Use top navigation")
            )
            .keyboardShortcut("s", modifiers: [.control, .command])
            AppSymbolView(pointSize: 22)
                .foregroundStyle(appearance.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(AppIdentity.displayName).font(.system(size: 17, weight: .semibold))
                Text(localized("Settings")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.leading, 24)
        .padding(.trailing, 24)
        .padding(.vertical, 14)
        .frame(minHeight: 56)
    }

    private var topNavigation: some View {
        HStack(spacing: 4) {
            ForEach(SettingsPage.allCases) { page in
                Button {
                    select(page)
                } label: {
                    Label(page.label, systemImage: page.symbol)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if selectedPage == page {
                                navigationSelection()
                            }
                        }
                }
                .buttonStyle(SettingsHoverButtonStyle(isSelected: selectedPage == page))
                .focused($focusedNavigation, equals: page)
                .onMoveCommand { moveNavigation($0, from: page) }
                .accessibilityValue(selectedPage == page ? localized("Selected") : "")
                .accessibilityAddTraits(selectedPage == page ? .isSelected : [])
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var sidebarNavigation: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsPage.allCases) { page in
                Button {
                    select(page)
                } label: {
                    Label(page.label, systemImage: page.symbol)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background {
                            if selectedPage == page {
                                navigationSelection()
                            }
                        }
                }
                .buttonStyle(SettingsHoverButtonStyle(isSelected: selectedPage == page))
                .focused($focusedNavigation, equals: page)
                .onMoveCommand { moveNavigation($0, from: page) }
                .accessibilityValue(selectedPage == page ? localized("Selected") : "")
                .accessibilityAddTraits(selectedPage == page ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 184)
    }

    @ViewBuilder
    private func navigationSelection() -> some View {
        if #available(macOS 26.0, *) {
            Color.clear
                .settingsGlass(
                    in: RoundedRectangle(cornerRadius: SettingsGlass.controlCornerRadius, style: .continuous),
                    interactive: true
                )
                .settingsGlassID("selection", in: navigationNamespace)
                .matchedGeometryEffect(id: "selection", in: navigationNamespace)
        } else {
            RoundedRectangle(cornerRadius: SettingsGlass.controlCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsGlass.controlCornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.5)
                )
                .matchedGeometryEffect(id: "selection", in: navigationNamespace)
        }
    }

    private var pageContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(selectedPage.label).font(.system(size: 24, weight: .semibold))
                Text(selectedPage.summary).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 14)
            settingsForm
        }
        .id(selectedPage)
        .transition(pageTransition)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
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
        selectedPage = page
    }

    private var settingsForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(sections: sections) { section in
                    SettingsGlassGroup(section: section)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .multilineTextAlignment(.leading)
        .animation(contentAnimation, value: appearance.accentMode)
        .animation(contentAnimation, value: general.vimNavigation)
        .animation(contentAnimation, value: general.interactions.hover)
        .transaction { transaction in
            if privacy.isProtected { transaction.animation = nil; transaction.disablesAnimations = true }
        }
        .toggleStyle(SettingsToggleStyle())
    }

    @ViewBuilder
    private var sections: some View {
        switch selectedPage {
        case .general:
            generalSection
            copySoundSection
        case .appearance: appearanceSection
        case .interactions: interactionSection
        case .history: historySection
        case .privacy:
            privacySection
            if !privacy.isProtected {
                sensitiveSection
                excludedSection
            }
            networkSection
        case .shortcuts:
            shortcutsSection(global: true)
            shortcutsSection(global: false)
            vimSection
            restoreSection
        }
    }

    @ViewBuilder private var appearanceSection: some View {
        Section {
            SettingsPicker(localized("Settings layout"), selection: $appearance.navigation) {
                ForEach(SettingsNavigation.allCases) { option in Text(option.label).tag(option) }
            }
        } header: {
            Text(localized("Settings navigation"))
        }
        Section {
            SettingsPicker(localized("Accent color"), selection: $appearance.accentMode) {
                ForEach(AccentMode.allCases) { option in Text(option.label).tag(option) }
            }
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
            }
        } header: {
            Text(localized("Colors"))
        } footer: {
            Text(localized("The accent color also highlights the selected clipboard card."))
        }
        Section {
            SettingsPicker(selection: $general.cardSize) {
                ForEach(CardSize.allCases) { size in Text(size.label).tag(size) }
            } label: {
                SettingsRowLabel(localized("Card size"), symbol: "rectangle.3.group", tint: .indigo)
            }
        } header: {
            Text(localized("Clipboard cards"))
        }
    }

    private var copySoundSection: some View {
        Section {
            Toggle(localized("Play a sound when a new copy is recorded"), isOn: $general.copySound.onCapture)
            Toggle(localized("Play a sound when copying from history"), isOn: $general.copySound.onHistoryCopy)
            SettingsPicker(localized("Copy sound"), selection: $general.copySound.sound) {
                ForEach(CopySound.allCases) { sound in Text(sound.rawValue).tag(sound) }
            }
            HStack {
                Text(localized("Sound volume"))
                Slider(value: $general.copySound.volume, in: 0...1)
                    .accessibilityLabel(localized("Sound volume"))
                Button(localized("Preview sound")) { copySoundPlayer.preview(general.copySound) }
            }
        } header: {
            Text(localized("Copy sound"))
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
            }
        } header: {
            Text(localized("Startup"))
        }
        Section {
            SettingsPicker(localized("Menu bar icon click"), selection: $appearance.statusClick) {
                ForEach(StatusClickAction.allCases) { option in Text(option.label).tag(option) }
            }
            SettingsPicker(localized("Dock icon"), selection: $appearance.dockIcon) {
                ForEach(DockIconMode.allCases) { option in Text(option.label).tag(option) }
            }
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
        } header: {
            Text(localized("Language"))
        }
    }

    @ViewBuilder private var interactionSection: some View {
        Section {
            SettingsPicker(localized("Application filter trigger"), selection: $general.appFilterTrigger) {
                ForEach(AppFilterTrigger.allCases) { trigger in Text(trigger.label).tag(trigger) }
            }
        } header: {
            Text(localized("Application filters"))
        } footer: {
            Text(
                localized(
                    "Hover switches to one app after a brief pause. Click still toggles filters; All clears app, type and pinned filters without clearing search."
                ))
        }
        Section {
            interactionPicker(localized("Single click"), key: \.singleClick)
            interactionPicker(localized("Double click"), key: \.doubleClick)
            interactionPicker(localized("Right click"), key: \.rightClick)
        } header: {
            Text(localized("Click actions"))
        } footer: {
            Text(localized("Pasting needs Accessibility permission. Without it, use Command-V after copying."))
        }
        Section {
            SettingsPicker(localized("Hover after a short delay"), selection: $general.interactions.hover) {
                Text(CardAction.none.label).tag(CardAction.none)
                Text(CardAction.preview.label).tag(CardAction.preview)
            }
            if general.interactions.hover == .preview {
                HStack {
                    Text(localized("Hover delay (seconds)"))
                    Spacer()
                    TextField(
                        "", value: $general.interactions.hoverDelay,
                        format: .number.precision(.fractionLength(1))
                    )
                    .multilineTextAlignment(.trailing).frame(width: 64)
                    Stepper("", value: $general.interactions.hoverDelay, in: 0.1...5, step: 0.1)
                        .labelsHidden()
                }
            }
        } header: {
            Text(localized("Hover preview"))
        } footer: {
            Text(localized("Pause over a card to preview it without clicking."))
        }
    }

    private func interactionPicker(_ title: String, key: WritableKeyPath<InteractionBindings, CardAction>) -> some View
    {
        SettingsPicker(
            title,
            selection: Binding(
                get: { general.interactions[keyPath: key] },
                set: { general.interactions[keyPath: key] = $0 }
            )
        ) {
            ForEach(CardAction.allCases, id: \.rawValue) { action in
                Text(action.label).tag(action)
            }
        }
    }

    @ViewBuilder private var privacySection: some View {
        Section {
            Toggle(
                localized("Manual Privacy Mode"),
                isOn: Binding(
                    get: { privacy.isManuallyProtected }, set: { privacy.setProtected($0) }))
            Toggle(
                localized("Automatic protection (limited detection)"),
                isOn: Binding(get: { privacy.automaticEnabled }, set: { privacy.setAutomaticEnabled($0) }))
            VStack(alignment: .leading, spacing: 8) {
                Label(privacy.statusText, systemImage: privacy.isProtected ? "lock.shield.fill" : "shield")
                    .font(.callout).foregroundStyle(privacy.isProtected ? Color.accentColor : Color.secondary)
                Text(localized("Automatic detection is limited. Use manual protection before important sharing."))
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup(localized("Detection coverage")) {
                    Text(
                        localized(
                            "Checks Zoom and Teams sharing toolbar titles using Accessibility. Client versions and languages may not match. System sharing, remote desktop, recording and browser tabs are not covered. Enable manual protection before important sharing."
                        )
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            if privacy.automaticEnabled {
                Button(localized("Allow Accessibility for toolbar detection…")) {
                    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                    _ = AXIsProcessTrustedWithOptions(options)
                }
            }
        } header: {
            Text(localized("Screen privacy"))
        }
        Section {
            Toggle(localized("Allow search in Privacy Mode"), isOn: $privacy.allowSearchWhileProtected)
            Toggle(localized("Show source apps in Privacy Mode"), isOn: $privacy.showSourceAppsWhileProtected)
        } header: {
            Text(localized("Visible during protection"))
        } footer: {
            Text(
                localized(
                    "Applies to manual and automatic protection. Search terms and enabled app names are visible on screen and in accessibility. Clipboard content stays hidden; automatic protection still blocks hover reveals."
                ))
        }
    }

    private var networkSection: some View {
        Section {
            Toggle(isOn: $general.linkPreviews) {
                SettingsRowLabel(localized("Fetch link previews"), symbol: "link", tint: .teal)
            }
            .toggleStyle(SettingsToggleStyle())
        } header: {
            Text(localized("Online content"))
        } footer: {
            Text(localized("A copied link is looked up once for its title and image. Off, nothing leaves this Mac."))
        }
    }

    private var historySection: some View {
        Section {
            SettingsPicker(selection: $general.retentionPeriod) {
                ForEach(RetentionPeriodOption.allCases) { option in
                    Text(option.label).tag(option)
                }
            } label: {
                SettingsRowLabel(localized("Keep history for"), symbol: "clock", tint: .orange)
            }
            SettingsPicker(selection: $general.capacity) {
                ForEach(GeneralSettingsStore.capacityChoices, id: \.self) { choice in
                    Text(GeneralSettingsStore.capacityLabel(choice)).tag(choice)
                }
            } label: {
                SettingsRowLabel(localized("History capacity"), symbol: "tray.full", tint: .purple)
            }
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

    private var sensitiveSection: some View {
        Section {
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
            Toggle(
                localized("Keep unmarked sensitive copies in memory for 2 minutes"),
                isOn: $general.retainSensitiveCopies)
        } header: {
            Text(localized("Sensitive apps"))
        } footer: {
            Text(localized("Copies from these apps are ignored unless temporary memory sessions are enabled."))
            DisclosureGroup(localized("How temporary sessions work")) {
                Text(
                    localized(
                        "Selected apps are ignored by default. Optional sessions expire after 2 minutes and reveal for 10 seconds. Rich text is previewed as plain text; images can only be copied. No search, editing, disk history or preview cache. Source attribution is best effort. Explicit no-record markers and excluded apps always win. Existing history is not reclassified."
                    ))
            }
        }
    }

    private var excludedSection: some View {
        Section {
            if general.excludedApps.isEmpty {
                Text(localized("No excluded apps added.")).foregroundStyle(.secondary)
            }
            ForEach(general.excludedApps) { app in
                HStack(spacing: 9) {
                    if let icon = SourceAppStyle.resolve(bundleID: app.bundleID).icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 22, height: 22)
                    }
                    Text(app.name)
                    Spacer()
                    Button {
                        general.excludedApps.removeAll { $0.bundleID == app.bundleID }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button {
                addExcludedApp()
            } label: {
                SettingsRowLabel(localized("Add App…"), symbol: "hand.raised.fill", tint: .red)
            }
            .buttonStyle(.plain)
        } header: {
            Text(localized("Excluded apps"))
        } footer: {
            Text(localized("Copies from excluded apps are never recorded."))
        }
    }

    private var vimSection: some View {
        Section {
            Toggle(isOn: $general.vimNavigation) {
                SettingsRowLabel(localized("Vim navigation in the panel"), symbol: "keyboard", tint: .matcha)
            }
            .toggleStyle(SettingsToggleStyle())
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
                        Button {
                            vimBindings.reset(action)
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .buttonStyle(.borderless)
                        .disabled(!vimBindings.isCustomized(action))
                        .help(localized("Reset to default"))
                    }
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
                    Button {
                        store.reset(action)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!store.isCustomized(action))
                    .help(localized("Reset to default"))
                }
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
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localized("Reset keyboard shortcuts"))
                    Text(localized("Resets all keyboard shortcuts and Vim bindings."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(localized("Reset…"), role: .destructive) { confirmingReset = true }
            }
            .alert(localized("Reset keyboard shortcuts?"), isPresented: $confirmingReset) {
                Button(localized("Cancel"), role: .cancel) {}
                Button(localized("Restore Defaults"), role: .destructive) {
                    store.resetAll()
                    vimBindings.resetAll()
                }
            } message: {
                Text(localized("Resets all keyboard shortcuts and Vim bindings."))
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
                if !general.sensitiveApps.contains(where: { $0.bundleID == bundleID }) {
                    general.sensitiveApps.append(app)
                }
            } else if !general.excludedApps.contains(where: { $0.bundleID == bundleID }) {
                general.excludedApps.append(app)
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

private struct SettingsGlassGroup: View {
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
                ForEach(Array(section.content.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        SettingsDivider()
                            .padding(.leading, 16)
                    }
                    row
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingsGlass(
                in: RoundedRectangle(cornerRadius: SettingsGlass.groupCornerRadius, style: .continuous)
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

/// The iOS-Settings row anatomy: the symbol on its rounded color tile,
/// the title beside it.
private struct SettingsRowLabel: View {
    let title: String
    let symbol: String
    let tint: Color

    init(_ title: String, symbol: String, tint: Color) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(
                    tint.opacity(0.13),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
            Text(title)
        }
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
            .settingsGlass(in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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
        Button {
            isRecording ? store.endRecording() : store.beginRecording(action)
        } label: {
            Text(isRecording ? localized("Type shortcut…") : store.label(for: action))
                .font(.system(.body, design: .rounded).weight(.medium))
                .frame(minWidth: 76)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .settingsGlass(in: RoundedRectangle(cornerRadius: 6, style: .continuous), interactive: true)
                .background(
                    Color.matcha.opacity(isRecording ? 0.2 : (isHovering ? 0.055 : 0)),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isRecording ? Color.matcha : .clear, lineWidth: 1.5)
                )
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

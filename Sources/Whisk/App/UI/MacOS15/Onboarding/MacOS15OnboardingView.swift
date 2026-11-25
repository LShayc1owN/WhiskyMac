// WhiskyMac: modified or added 2026-11-18 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

struct MacOS15OnboardingView: View {
    @ObservedObject var state: OnboardingState
    @ObservedObject var bindings: KeyBindingsStore
    @ObservedObject var general: GeneralSettingsStore
    @ObservedObject var appearance: AppearanceSettingsStore
    @ObservedObject var loginItem: LoginItemManager
    var actions = OnboardingActions()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stepOffset = MacOS15OnboardingMotion.stepDistance
    @State private var hasRevealedCover = false
    @State private var permissionChecks = 0

    private var typography: InterfaceTypography { appearance.interfaceTypography }

    private let contentWidth: CGFloat = 720
    private let contentInset: CGFloat = 28

    var body: some View {
        ZStack {
            if state.page == .welcome {
                welcomeCover
                    .transition(MacOS15OnboardingMotion.enter())
            } else {
                walkthrough
                    .transition(MacOS15OnboardingMotion.enter())
            }
        }
        .animation(MacOS15OnboardingMotion.page, value: state.page == .welcome)
        .frame(
            minWidth: 780, idealWidth: 980, maxWidth: .infinity,
            minHeight: 480, idealHeight: 700, maxHeight: .infinity
        )
        .interfaceType(typography)
        .background { MacOS15OnboardingStyle.paper.ignoresSafeArea(.container, edges: .top) }
        .tint(MacOS15OnboardingStyle.green)
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .onAppear { state.refreshPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.refreshPermissions()
        }
        .task {
            while !Task.isCancelled {
                state.refreshPermissions()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .background(
            MacOS15OnboardingWindowEvents {
                bindings.endRecording()
            }
        )
        .onDisappear {
            bindings.endRecording()
        }
    }

    @ViewBuilder private var walkthrough: some View {
        if typography.usesLargeLayout {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    stepNavigation(horizontal: true)
                        .fixedSize(horizontal: false, vertical: true)
                    languageMenu(iconOnly: true)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                Divider()
                walkthroughContent
            }
        } else {
            HStack(spacing: 0) {
                sidebar
                Rectangle().fill(.primary.opacity(0.07)).frame(width: 1)
                    .ignoresSafeArea(.container, edges: .top)
                walkthroughContent
            }
        }
    }

    private var walkthroughContent: some View {
        VStack(spacing: 0) {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        heading
                        pageContent
                    }
                    .frame(maxWidth: contentWidth, alignment: .leading)
                    .padding(.horizontal, contentInset)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.visible)
                .defaultScrollAnchor(.topLeading, for: .initialOffset)
                .id(state.page)
                .transition(MacOS15OnboardingMotion.enter(x: stepOffset))
            }
            .clipped()
            .animation(MacOS15OnboardingMotion.page, value: state.page)
            .padding(.top, 24)
            footer
        }
    }

    private func stepNavigation(horizontal: Bool = false) -> some View {
        MacOS15OnboardingStepNavigation(
            current: state.page,
            permissionsComplete: state.clipboardAccess == .granted && state.accessibilityGranted,
            allowsArrowNavigation: bindings.recordingAction == nil,
            horizontal: horizontal,
            select: navigate(to:))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                MacOS15AppSymbolView(pointSize: 28).foregroundStyle(MacOS15OnboardingStyle.green)
                Text("WhiskyMac").font(.system(size: 18, weight: .semibold, design: .rounded))
            }
            .padding(.bottom, 24)
            stepNavigation()
            Spacer(minLength: 12)
            languagePicker
        }
        .padding(22)
        .frame(width: 206)
        .background { MacOS15OnboardingStyle.green.opacity(0.035).ignoresSafeArea(.container, edges: .top) }
    }

    private var languagePicker: some View {
        languageMenu(iconOnly: false)
    }

    private func languageMenu(iconOnly: Bool) -> some View {
        Menu {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    appearance.language = language
                } label: {
                    if language == appearance.language {
                        Label(language.label, systemImage: "checkmark")
                    } else {
                        Text(language.label)
                    }
                }
            }
        } label: {
            if iconOnly {
                Image(systemName: "globe")
                    .font(typography.font(.callout))
            } else {
                Text(appearance.language.label)
                    .font(typography.font(.callout))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: iconOnly, vertical: true)
        .accessibilityLabel(localized("Language"))
        .accessibilityValue(appearance.language.label)
        .help(localized("Language"))
    }

    private var textSizePicker: some View {
        let range = InterfaceTypography.percentRange
        let choices = Set(stride(from: range.lowerBound, through: range.upperBound, by: 5))
            .union([typography.percent]).sorted()
        let locale = AppLocalization.interfaceLocale
        return optionMenu(
            localized("Interface font size"),
            options: choices,
            selection: Binding(get: { typography.percent }, set: appearance.setInterfaceFontPercent)
        ) { percent in
            (Double(percent) / 100).formatted(.percent.locale(locale))
        }
        .accessibilityIdentifier("onboarding.textSize")
    }

    private func optionMenu<Option: Hashable>(
        _ title: String,
        options: [Option],
        selection: Binding<Option>,
        label: (Option) -> String
    ) -> some View {
        let selected = label(selection.wrappedValue)
        let values = options.map { ($0, label($0)) }
        let menu = Menu {
            ForEach(values, id: \.0) { option, name in
                Button {
                    selection.wrappedValue = option
                } label: {
                    if option == selection.wrappedValue {
                        Label(name, systemImage: "checkmark")
                    } else {
                        Text(name)
                    }
                }
            }
        } label: {
            Text(selected)
                .font(typography.font(size: 14, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 28)
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel(title)
        .accessibilityValue(selected)

        let heading = Text(title)
            .font(typography.font(size: 14))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                heading.fixedSize()
                Spacer(minLength: 12)
                menu.fixedSize()
            }
            VStack(alignment: .leading, spacing: 4) {
                heading
                menu
            }
        }
    }

    private var heading: some View {
        Text(state.page.label)
            .font(typography.font(size: 28, weight: .semibold, design: .rounded))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                backButton.fixedSize()
                Spacer(minLength: 8)
                forwardButton.fixedSize()
            }
            VStack(alignment: .trailing, spacing: 6) {
                forwardButton
                backButton
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: contentWidth)
        .background { MacOS15OnboardingFrostedSurface(cornerRadius: 15) }
        .padding(.horizontal, contentInset)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
    }

    private var backButton: some View {
        Label(localized("Back"), systemImage: "chevron.left")
            .fixedSize(horizontal: false, vertical: true)
            .font(typography.font(size: 13, weight: .medium))
            .padding(.horizontal, 8)
            .frame(minHeight: 42)
            .beButton {
                if let previous = state.page.advanced(by: -1) { navigate(to: previous) }
            }
            .buttonStyle(MacOS15OnboardingButtonStyle(treatment: .quiet))
    }

    private var forwardButton: some View {
        HStack(spacing: 8) {
            Text(state.page == .ready ? localized("Open my clipboard") : localized("Continue"))
                .contentTransition(.opacity)
            Image(systemName: state.page == .ready ? "arrow.up.right" : "arrow.right")
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
        }
        .animation(MacOS15OnboardingMotion.detail, value: state.page == .ready)
        .beButton {
            if state.page == .ready {
                bindings.endRecording()
                state.complete()
                actions.finish()
            } else if let next = state.page.advanced(by: 1) {
                navigate(to: next)
            }
        }
        .buttonStyle(MacOS15OnboardingButtonStyle(treatment: .primary))
        .keyboardShortcut(.defaultAction)
        .disabled(bindings.recordingAction != nil)
        .accessibilityIdentifier("onboarding.continue")
    }

    private func navigate(to page: OnboardingPage) {
        bindings.endRecording()
        guard page != state.page else { return }
        stepOffset =
            page.stepNumber > state.page.stepNumber
            ? MacOS15OnboardingMotion.stepDistance : -MacOS15OnboardingMotion.stepDistance
        state.select(page)
    }

    @ViewBuilder private var pageContent: some View {
        switch state.page {
        case .welcome: EmptyView()
        case .basicSettings: basicSettings
        case .permissions: permissions
        case .practice: practice
        case .tools: tools
        case .privacy: privacy
        case .preferences: preferences
        case .guide: guide
        case .ready: ready
        }
    }

    private var welcomeCover: some View {
        VStack(spacing: 0) {
            GeometryReader { viewport in
                let compact = viewport.size.height < 500
                ScrollView {
                    VStack(spacing: 16) {
                        if typography.usesLargeLayout { welcomePreferences }
                        welcomeIntroduction(compact: compact)
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, compact ? 12 : 20)
                    .frame(maxWidth: .infinity)
                }
                .defaultScrollAnchor(.center, for: .alignment)
            }

            Group {
                if typography.usesLargeLayout {
                    welcomeActions
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .bottom, spacing: 16) {
                            languagePicker.frame(width: 156)
                            Spacer(minLength: 0)
                            welcomeActions.fixedSize()
                            Spacer(minLength: 0)
                            textSizePicker.fixedSize()
                        }
                        VStack(spacing: 12) {
                            welcomeActions
                            welcomePreferences
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
    }

    private var welcomePreferences: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                languagePicker.fixedSize()
                textSizePicker.fixedSize()
            }
            VStack(alignment: .leading, spacing: 12) {
                languagePicker
                textSizePicker
            }
        }
    }

    private var welcomeActions: some View {
        VStack(spacing: 12) {
            Label(localized("Start setup"), systemImage: "arrow.right")
                .beButton { navigate(to: .basicSettings) }
                .buttonStyle(MacOS15OnboardingButtonStyle(treatment: .primary))
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("onboarding.start")
            Button(localized("Set up later"), action: actions.later)
                .buttonStyle(MacOS15OnboardingButtonStyle(treatment: .quiet))
                .foregroundStyle(.secondary)
                .font(typography.font(.body))
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 32)
        }
    }

    private func welcomeIntroduction(compact: Bool) -> some View {
        VStack(spacing: compact ? 14 : 20) {
            HStack(spacing: 9) {
                MacOS15AppSymbolView(pointSize: compact ? 24 : 28).accessibilityHidden(true)
                Text(AppIdentity.displayName)
                    .font(typography.font(size: 17, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(MacOS15OnboardingStyle.green)

            VStack(spacing: 10) {
                Text(OnboardingPage.welcomeTitle)
                    .font(typography.font(size: compact ? 30 : 36, weight: .semibold, design: .rounded))
                    .accessibilityAddTraits(.isHeader)
                intro(
                    localized(
                        "Find and reuse anything you copy."
                    )
                )
                .frame(maxWidth: 560)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            MacOS15OnboardingIllustration(scene: .welcome, menuSymbol: appearance.defaultStatusSymbol)
                .frame(height: compact ? 168 : 248)
                .scaleEffect(hasRevealedCover || reduceMotion ? 1 : 0.975)
                .opacity(hasRevealedCover || reduceMotion ? 1 : 0.72)
                .animation(MacOS15OnboardingMotion.cover, value: hasRevealedCover)
                .onAppear { hasRevealedCover = true }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { welcomeBenefits }.fixedSize(horizontal: true, vertical: false)
                VStack(spacing: 8) { welcomeBenefits }
            }
        }
        .frame(maxWidth: 730)
    }

    @ViewBuilder private var welcomeBenefits: some View {
        welcomeBenefit("magnifyingglass", localized("Search and filter"))
        welcomeBenefit("pin", localized("Pin favorites"))
        welcomeBenefit("internaldrive", localized("Local history"))
    }

    private func welcomeBenefit(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(typography.font(size: 15, weight: .medium))
                .foregroundStyle(MacOS15OnboardingStyle.green)
                .accessibilityHidden(true)
            Text(title)
                .font(typography.font(size: 13, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 46)
        .background { MacOS15OnboardingFrostedSurface(cornerRadius: 12) }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 16) {
            MacOS15OnboardingPermissionCard(
                symbol: "doc.on.clipboard",
                title: localized("Clipboard access"),
                explanation: state.clipboardAccess == .granted
                    ? localized("New copies can be saved to your history.")
                    : localized(
                        "Save new copies to your history. If prompted, choose Allow Paste, then set WhiskyMac to Allow in Paste from Other Apps."
                    ),
                granted: state.clipboardAccess == .granted,
                actionTitle: localized("Allow Clipboard Access"),
                action: actions.allowClipboard)
            MacOS15OnboardingPermissionCard(
                symbol: "accessibility",
                title: localized("Accessibility"),
                explanation: state.accessibilityGranted
                    ? localized("You can paste directly into the active app.")
                    : localized(
                        "Optional. Turn on WhiskyMac in Accessibility to paste directly, or copy a card and press ⌘V."
                    ),
                granted: state.accessibilityGranted,
                actionTitle: localized("Open Accessibility settings"),
                isOptional: true,
                action: actions.allowAccessibility)
            permissionFooter
        }
    }

    private var permissionFooter: some View {
        let needsPermission = state.clipboardAccess != .granted || !state.accessibilityGranted
        let hint = detail(localized("You can continue and grant permissions later."))
        let recheck = HStack(spacing: 7) {
            Image(systemName: "arrow.clockwise")
                .symbolEffect(.rotate, options: .nonRepeating, value: reduceMotion ? 0 : permissionChecks)
                .accessibilityHidden(true)
            Text(localized("Check permissions again"))
        }
        .beButton {
            state.refreshPermissions()
            permissionChecks += 1
        }
        .buttonStyle(MacOS15OnboardingButtonStyle(treatment: .secondary))

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                if needsPermission { hint.fixedSize() }
                Spacer(minLength: 0)
                recheck.fixedSize()
            }
            VStack(alignment: .leading, spacing: 12) {
                if needsPermission { hint }
                recheck.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var practice: some View {
        VStack(alignment: .leading, spacing: 16) {
            if state.clipboardAccess != .granted {
                MacOS15OnboardingPracticeAccess {
                    navigate(to: .permissions)
                }
            }
            MacOS15OnboardingShortcutSettings(bindings: bindings, includesPanelActions: true)
            MacOS15OnboardingPractice(bindings: bindings, canPasteDirectly: state.accessibilityGranted)
        }
    }

    private var tools: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 0) {
                feature(
                    "pin", localized("Pin favorites"),
                    localized(
                        "Pin from a card’s menu. Pinned items stay when you clear history."
                    ), section: .pinnedItems)
                feature(
                    "square.stack.3d.up", localized("Paste in order"),
                    localized(
                        "Add cards to the paste stack and enable its shortcut to paste them in order."
                    ), section: .globalShortcuts)
                feature(
                    "scissors", localized("Edit and split text"),
                    localized(
                        "Use a text card’s menu to edit or split its contents."
                    ), section: .normalInteractions)
                feature(
                    "line.3.horizontal.decrease", localized("Search and filter"),
                    localized(
                        "Filter your history by app, type or tag."
                    ), section: .filters)
            }
            .background(MacOS15OnboardingStyle.card, in: RoundedRectangle(cornerRadius: 18))
            MacOS15OnboardingIllustration(scene: .tools, menuSymbol: appearance.defaultStatusSymbol).frame(height: 165)
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 18) {
            MacOS15OnboardingSurface {
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text(localized("Know what protection covers"))
                    } icon: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(MacOS15OnboardingStyle.orange)
                    }
                    .font(typography.font(size: 15, weight: .semibold))
                    detail(
                        localized(
                            "Automatic detection covers only supported Zoom and Teams screen sharing sessions."
                        ))
                }
            }
            feature(
                "eye.slash", localized("Screen sharing"),
                localized(
                    "Turn on Privacy Mode before sharing. Revealed or pasted content can still appear on screen."
                ), section: .screenSharingProtection)
            feature(
                "timer", localized("Sensitive apps"),
                localized(
                    "New copies stay in memory briefly. Excluded apps aren’t recorded. Existing history is kept."
                ), section: .sensitiveAccess)
            MacOS15OnboardingDisclosure(localized("Fine-tune what stays visible")) {
                VStack(alignment: .leading, spacing: 10) {
                    detail(
                        localized(
                            "Manage what stays visible and which clicks are allowed."
                        ))
                    settingLink(localized("Privacy mode"), section: .privacyInteractions)
                    settingLink(
                        localized("Visible during protection"), section: .screenSharingProtection,
                        anchor: "privacySearch")
                }.padding(.top, 8)
            }.font(typography.font(.callout))
            MacOS15OnboardingPrivacyDiagram()
        }
    }

    private var basicSettings: some View {
        MacOS15OnboardingSurface {
            VStack(alignment: .leading, spacing: 10) {
                textSizePicker
                Divider()
                optionMenu(
                    localized("Settings window appearance"), options: AppearanceMode.allCases,
                    selection: $appearance.settingsAppearance, label: \.label)
                optionMenu(
                    localized("Clipboard appearance"), options: AppearanceMode.allCases,
                    selection: $appearance.clipboardAppearance, label: \.label)
                optionMenu(
                    localized("Accent color"), options: AccentMode.allCases, selection: $appearance.accentMode
                ) {
                    $0.label
                }
                if appearance.accentMode == .custom {
                    ColorPicker(
                        localized("Custom color"),
                        selection: Binding(
                            get: { Color(nsColor: appearance.customAccent.nsColor) },
                            set: { appearance.customAccent = AccentRGB(NSColor($0)) }),
                        supportsOpacity: false
                    )
                    .transition(MacOS15OnboardingMotion.enter(y: 3))
                }
            }
        }
        .animation(MacOS15OnboardingMotion.detail, value: appearance.accentMode)
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 16) {
            MacOS15OnboardingSurface {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(
                        localized("Launch at login"),
                        isOn: Binding(
                            get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) })
                    )
                    .toggleStyle(.switch)
                    if let error = loginItem.lastError {
                        Text(error).font(typography.font(.caption)).foregroundStyle(.orange)
                    }
                }
            }
            MacOS15OnboardingDisclosure(localized("Optional settings")) {
                VStack(alignment: .leading, spacing: 14) {
                    MacOS15OnboardingShortcutSettings(bindings: bindings)
                    MacOS15OnboardingSurface {
                        VStack(alignment: .leading, spacing: 12) {
                            optionMenu(
                                localized("History capacity"), options: GeneralSettingsStore.capacityChoices,
                                selection: $general.capacity, label: GeneralSettingsStore.capacityLabel)
                            optionMenu(
                                localized("Keep history for"), options: RetentionPeriodOption.allCases,
                                selection: $general.retentionPeriod
                            ) { $0.label }
                            detail(
                                localized(
                                    "Lower limits can remove unpinned history immediately."
                                ))
                        }
                    }
                    settingLink(localized("Appearance and card size"), section: .cards)
                    settingLink(localized("Sounds and effects"), section: .sounds)
                    settingLink(localized("Online content"), section: .network)
                    settingLink(localized("Menu bar and Dock"), section: .menuAndDock)
                    settingLink(localized("Menu bar icons"), section: .statusIcons)
                    settingLink(SettingsSectionID.colors.title.localized, section: .colors)
                    settingLink(localized("Pinned items"), section: .pinnedItems)
                    settingLink(localized("About this App"), section: .aboutApp)
                }
                .padding(.top, 12)
            }
        }
    }

    private var guide: some View {
        VStack(alignment: .leading, spacing: 16) {
            MacOS15OnboardingSurface {
                VStack(spacing: 12) {
                    ForEach([KeyAction.togglePanel, .copySelection, .pasteSelection], id: \.self) {
                        shortcutRow($0)
                    }
                }
            }
            MacOS15OnboardingDisclosure(localized("More shortcuts")) {
                VStack(spacing: 12) {
                    ForEach(
                        [
                            KeyAction.togglePinned, .pasteNextFromStack, .togglePrivacy,
                            .pastePlain, .previewSelection, .pinSelection, .stackSelection, .editSelection,
                            .undoLastChange,
                            .previousCard, .nextCard, .rowUp, .rowDown, .switchChipGroup,
                            .deleteSelection, .openSelection, .revealSelection, .saveSelection,
                            .excludeSelectionSource, .deleteSelectionSource,
                        ], id: \.self
                    ) { shortcutRow($0) }
                    HStack {
                        Text(localized("Close the panel")).font(typography.font(.body))
                        Spacer()
                        MacOS15OnboardingKeycap(text: "esc")
                    }
                    settingLink(localized("Customize all shortcuts and Vim navigation"), section: .panelShortcuts)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 10)
            }
            MacOS15OnboardingDisclosure(localized("Nothing is appearing in my history")) {
                detail(
                    localized(
                        "Copy something new. If it doesn’t appear, check clipboard access, capture status and app exclusions."
                    )
                )
                .padding(.top, 8)
            }
            MacOS15OnboardingDisclosure(localized("A card copies, but does not paste")) {
                detail(
                    localized(
                        "Focus a field in the destination app and check Accessibility. You can also copy the card and press ⌘V."
                    )
                )
                .padding(.top, 8)
            }
            MacOS15OnboardingDisclosure(localized("Where are settings and my pinned items?")) {
                detail(
                    localized(
                        "Right-click the menu bar icon for settings and pinned items."
                    )
                )
                .padding(.top, 8)
            }
        }
        .font(typography.font(.callout))
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 20) {
            if state.clipboardAccess == .granted {
                intro(localized("Copy something, then open your history."))
            }
            MacOS15OnboardingSurface {
                VStack(spacing: 14) {
                    readinessRow(
                        localized("Clipboard access"),
                        value: state.clipboardAccess == .granted ? localized("Ready") : localized("Set up when ready"),
                        ready: state.clipboardAccess == .granted)
                    readinessRow(
                        localized("Direct paste"),
                        value: state.accessibilityGranted
                            ? localized("Ready") : localized("Manual Command-V available"),
                        ready: state.accessibilityGranted)
                    readinessRow(
                        localized("History shortcut"),
                        value: bindings.isGlobalEnabled(.togglePanel)
                            && !bindings.registrationFailures.contains(.togglePanel)
                            ? bindings.label(for: .togglePanel) : localized("Use the menu bar"),
                        ready: bindings.isGlobalEnabled(.togglePanel)
                            && !bindings.registrationFailures.contains(.togglePanel))
                }
            }
            if state.clipboardAccess != .granted {
                Button(localized("Review permissions")) { navigate(to: .permissions) }
                    .buttonStyle(MacOS15OnboardingButtonStyle(treatment: .secondary))
            }
            MacOS15OnboardingIllustration(scene: .ready, menuSymbol: appearance.defaultStatusSymbol).frame(height: 180)
        }
    }

    private func intro(_ text: String) -> some View {
        Text(text).font(typography.font(size: 15)).foregroundStyle(.secondary).lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func detail(_ text: String) -> some View {
        Text(text).font(typography.font(size: 14)).foregroundStyle(.secondary).lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func shortcutRow(_ action: KeyAction) -> some View {
        let title = Text(action.displayName)
            .font(typography.font(size: 14))
            .fixedSize(horizontal: false, vertical: true)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                title.fixedSize()
                Spacer(minLength: 0)
                shortcutValue(action).fixedSize()
            }
            VStack(alignment: .leading, spacing: 4) {
                title
                shortcutValue(action)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func shortcutValue(_ action: KeyAction) -> some View {
        if action.isGlobal && (!bindings.isGlobalEnabled(action) || bindings.registrationFailures.contains(action)) {
            Text(action == .togglePanel ? localized("Use the menu bar") : localized("Off"))
                .font(typography.font(.body))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            MacOS15OnboardingKeycap(text: bindings.label(for: action))
        }
    }

    private func feature(_ symbol: String, _ title: String, _ text: String, section: SettingsSectionID) -> some View {
        let iconSide = max(36, typography.points(25))
        return HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(typography.font(size: 16, weight: .medium))
                .foregroundStyle(MacOS15OnboardingStyle.green)
                .frame(width: iconSide, height: iconSide)
                .background(MacOS15OnboardingStyle.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(typography.font(size: 16, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                detail(text)
            }
            Spacer(minLength: 12)
            Image(systemName: "arrow.up.right")
                .font(typography.font(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(12)
        .contentShape(Rectangle())
        .beButton {
            bindings.endRecording()
            actions.openSettings(SettingsDestination(section: section))
        }
        .buttonStyle(MacOS15OnboardingButtonStyle(treatment: .quiet))
        .help(localized("View in Settings"))
        .accessibilityHint(localized("View in Settings"))
    }

    private func settingLink(_ title: String, section: SettingsSectionID, anchor: String? = nil) -> some View {
        HStack(spacing: 4) {
            Text(title).fixedSize(horizontal: false, vertical: true)
            Image(systemName: "arrow.up.right").font(typography.font(size: 9, weight: .semibold))
        }
        .font(typography.font(size: 13, weight: .medium))
        .frame(minHeight: 30)
        .beButton {
            bindings.endRecording()
            actions.openSettings(SettingsDestination(section: section, anchor: anchor))
        }
        .buttonStyle(MacOS15OnboardingButtonStyle(treatment: .quiet))
        .foregroundStyle(MacOS15OnboardingStyle.green)
    }

    private func readinessRow(_ title: String, value: String, ready: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ready ? "checkmark.circle.fill" : "circle.dashed")
                .contentTransition(.symbolEffect(.replace))
                .font(typography.font(size: 17, weight: .medium))
                .foregroundStyle(ready ? MacOS15OnboardingStyle.green : .secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(typography.font(.body).weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Text(value)
                .font(typography.font(.body).weight(.medium))
                .foregroundStyle(ready ? MacOS15OnboardingStyle.green : .primary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
        }
        .accessibilityElement(children: .combine)
        .animation(MacOS15OnboardingMotion.detail, value: value)
        .animation(MacOS15OnboardingMotion.detail, value: ready)
    }
}

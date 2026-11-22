// WhiskyMac: modified or added 2026-11-18 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var state: OnboardingState
    @ObservedObject var bindings: KeyBindingsStore
    @ObservedObject var general: GeneralSettingsStore
    @ObservedObject var appearance: AppearanceSettingsStore
    @ObservedObject var loginItem: LoginItemManager
    var actions = OnboardingActions()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stepOffset = OnboardingMotion.stepDistance
    @State private var hasRevealedCover = false

    var body: some View {
        ZStack {
            if state.page == .welcome {
                welcomeCover
                    .transition(OnboardingMotion.enter())
            } else {
                walkthrough
                    .transition(OnboardingMotion.enter())
            }
        }
        .animation(OnboardingMotion.page, value: state.page == .welcome)
        .frame(
            minWidth: 780, idealWidth: 980, maxWidth: .infinity,
            minHeight: 480, idealHeight: 700, maxHeight: .infinity
        )
        .background { OnboardingStyle.paper.ignoresSafeArea(.container, edges: .top) }
        .tint(OnboardingStyle.green)
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
            OnboardingWindowEvents {
                bindings.endRecording()
                state.practice.cancelTransient()
            }
        )
        .onDisappear {
            bindings.endRecording()
            state.practice.cancelTransient()
        }
    }

    private var walkthrough: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(.primary.opacity(0.07)).frame(width: 1)
                .ignoresSafeArea(.container, edges: .top)
            VStack(spacing: 0) {
                ZStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            heading
                            pageContent
                        }
                        .frame(maxWidth: 660, alignment: .leading)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 32)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.visible)
                    .defaultScrollAnchor(.topLeading, for: .initialOffset)
                    .id(state.page)
                    .transition(OnboardingMotion.enter(x: stepOffset))
                }
                .clipped()
                .animation(OnboardingMotion.page, value: state.page)
                .padding(.top, 24)
                footer
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                AppSymbolView(pointSize: 28).foregroundStyle(OnboardingStyle.green)
                Text("WhiskyMac").font(.system(size: 18, weight: .semibold, design: .rounded))
            }
            .padding(.bottom, 24)
            OnboardingStepNavigation(current: state.page, select: navigate(to:))
            Spacer(minLength: 12)
            languagePicker
        }
        .padding(22)
        .frame(width: 206)
        .background { OnboardingStyle.green.opacity(0.035).ignoresSafeArea(.container, edges: .top) }
    }

    private var languagePicker: some View {
        Picker(localized("Language"), selection: $appearance.language) {
            ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
        }
        .labelsHidden()
        .controlSize(.small)
    }

    private var heading: some View {
        Text(state.page.label)
            .font(.system(size: 32, weight: .semibold, design: .rounded))
            .tracking(-0.65)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            HStack(spacing: 16) {
                Button(localized("Back")) {
                    if let previous = OnboardingPage(rawValue: state.page.rawValue - 1) { navigate(to: previous) }
                }
                .buttonStyle(OnboardingButtonStyle(treatment: .quiet)).foregroundStyle(.secondary)
                Spacer()
                Text("\(state.page.rawValue) / \(OnboardingPage.steps.count)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: Double(state.page.rawValue)))
                    .animation(OnboardingMotion.detail, value: state.page)
                Button {
                    if state.page == .ready {
                        bindings.endRecording()
                        state.complete()
                        actions.finish()
                    } else if let next = OnboardingPage(rawValue: state.page.rawValue + 1) {
                        navigate(to: next)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(state.page == .ready ? localized("Open my clipboard") : localized("Continue"))
                            .contentTransition(.opacity)
                        Image(systemName: state.page == .ready ? "arrow.up.right" : "arrow.right")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .animation(OnboardingMotion.detail, value: state.page == .ready)
                }
                .buttonStyle(OnboardingButtonStyle(treatment: .primary))
                .keyboardShortcut(.defaultAction)
                .disabled(bindings.recordingAction != nil)
                .accessibilityIdentifier("onboarding.continue")
            }
            .padding(.horizontal, 32).padding(.vertical, 18)
        }
        .background(OnboardingStyle.paper)
    }

    private func navigate(to page: OnboardingPage) {
        bindings.endRecording()
        guard page != state.page else { return }
        stepOffset =
            page.rawValue > state.page.rawValue ? OnboardingMotion.stepDistance : -OnboardingMotion.stepDistance
        state.select(page)
    }

    @ViewBuilder private var pageContent: some View {
        switch state.page {
        case .welcome: EmptyView()
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
                    welcomeIntroduction(compact: compact)
                        .padding(.horizontal, 40)
                        .padding(.vertical, compact ? 12 : 20)
                        .frame(maxWidth: .infinity)
                }
                .defaultScrollAnchor(.center, for: .alignment)
            }

            VStack(spacing: 12) {
                Button {
                    navigate(to: .permissions)
                } label: {
                    HStack(spacing: 8) {
                        Text(localized("Start setup"))
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(OnboardingButtonStyle(treatment: .primary))
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("onboarding.start")
                Button(localized("Set up later"), action: actions.later)
                    .buttonStyle(OnboardingButtonStyle(treatment: .quiet)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottomLeading) {
                languagePicker.frame(width: 156)
            }
            .padding(.horizontal, 32)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
    }

    private func welcomeIntroduction(compact: Bool) -> some View {
        VStack(spacing: compact ? 14 : 20) {
            HStack(spacing: 9) {
                AppSymbolView(pointSize: compact ? 24 : 28).accessibilityHidden(true)
                Text(AppIdentity.displayName)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(OnboardingStyle.green)

            VStack(spacing: 10) {
                Text(OnboardingPage.welcomeTitle)
                    .font(.system(size: compact ? 30 : 36, weight: .semibold, design: .rounded))
                    .tracking(-0.65)
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

            OnboardingIllustration(scene: .welcome, menuSymbol: appearance.defaultStatusSymbol)
                .frame(height: compact ? 204 : 280)
                .scaleEffect(hasRevealedCover || reduceMotion ? 1 : 0.975)
                .opacity(hasRevealedCover || reduceMotion ? 1 : 0.72)
                .animation(OnboardingMotion.cover, value: hasRevealedCover)
                .onAppear { hasRevealedCover = true }
        }
        .frame(maxWidth: 730)
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnboardingPermissionDiagram(
                clipboardGranted: state.clipboardAccess == .granted,
                accessibilityGranted: state.accessibilityGranted)
            OnboardingSurface {
                VStack(alignment: .leading, spacing: 12) {
                    statusHeading(localized("Clipboard access"), granted: state.clipboardAccess == .granted)
                    detail(
                        localized(
                            "Save new copies to your history. If prompted, choose Allow Paste, then set WhiskyMac to Allow in Paste from Other Apps."
                        ))
                    if state.clipboardAccess != .granted {
                        HStack {
                            Spacer()
                            Button(localized("Allow Clipboard Access"), action: actions.allowClipboard)
                                .buttonStyle(OnboardingButtonStyle(treatment: .secondary))
                        }
                        .transition(.opacity)
                    }
                }
            }
            .animation(OnboardingMotion.detail, value: state.clipboardAccess == .granted)
            OnboardingSurface {
                VStack(alignment: .leading, spacing: 12) {
                    statusHeading(localized("Accessibility"), granted: state.accessibilityGranted)
                    detail(
                        localized(
                            "Enable WhiskyMac in Accessibility to paste directly. You can also copy a card and press ⌘V."
                        ))
                    if !state.accessibilityGranted {
                        HStack {
                            Spacer()
                            Button(localized("Open Accessibility settings"), action: actions.allowAccessibility)
                                .buttonStyle(OnboardingButtonStyle(treatment: .secondary))
                        }
                        .transition(.opacity)
                    }
                }
            }
            .animation(OnboardingMotion.detail, value: state.accessibilityGranted)
            HStack {
                Spacer()
                Button(localized("Check permissions again")) { state.refreshPermissions() }
                    .buttonStyle(OnboardingButtonStyle(treatment: .quiet))
                    .foregroundStyle(OnboardingStyle.green)
            }
        }
    }

    private var practice: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingPractice(session: state.practice, general: general, bindings: bindings)
            OnboardingPracticeSettings(session: state.practice, general: general, bindings: bindings)
        }
    }

    private var tools: some View {
        VStack(alignment: .leading, spacing: 14) {
            OnboardingIllustration(scene: .tools, menuSymbol: appearance.defaultStatusSymbol).frame(height: 165)
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
            .background(OnboardingStyle.card, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingPrivacyDiagram()
            feature(
                "eye.slash", localized("Screen sharing"),
                localized(
                    "Turn on Privacy Mode before sharing. Revealed or pasted content can still appear on screen."
                ), section: .screenPrivacy)
            feature(
                "timer", localized("Sensitive apps"),
                localized(
                    "New copies stay in memory briefly. Excluded apps aren’t recorded. Existing history is kept."
                ), section: .sensitiveAccess)
            OnboardingSurface(tint: .orange) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(localized("Know what protection covers"), systemImage: "info.circle").font(
                        .subheadline.weight(.semibold))
                    detail(
                        localized(
                            "Automatic protection only detects supported Zoom and Teams sharing sessions."
                        ))
                }
            }
            OnboardingDisclosure(localized("Fine-tune what stays visible")) {
                VStack(alignment: .leading, spacing: 10) {
                    detail(
                        localized(
                            "Manage what stays visible and which clicks are allowed."
                        ))
                    settingLink(localized("Privacy mode"), section: .privacyInteractions)
                    settingLink(localized("Visible during protection"), section: .privacyVisibility)
                }.padding(.top, 8)
            }.font(.callout)
        }
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnboardingSurface {
                VStack(alignment: .leading, spacing: 12) {
                    Picker(localized("Accent color"), selection: $appearance.accentMode) {
                        ForEach(AccentMode.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    if appearance.accentMode == .custom {
                        ColorPicker(
                            localized("Custom color"),
                            selection: Binding(
                                get: { Color(nsColor: appearance.customAccent.nsColor) },
                                set: { appearance.customAccent = AccentRGB(NSColor($0)) }),
                            supportsOpacity: false
                        )
                        .transition(OnboardingMotion.enter(y: 3))
                    }
                    Divider()
                    Toggle(
                        localized("Launch at login"),
                        isOn: Binding(
                            get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) })
                    )
                    .toggleStyle(.switch)
                    if let error = loginItem.lastError { Text(error).font(.caption).foregroundStyle(.orange) }
                }
            }
            .animation(OnboardingMotion.detail, value: appearance.accentMode)
            OnboardingSurface {
                VStack(alignment: .leading, spacing: 13) {
                    Toggle(
                        localized("Enable the history shortcut"),
                        isOn: Binding(
                            get: { bindings.isGlobalEnabled(.togglePanel) },
                            set: { bindings.setGlobalEnabled($0, for: .togglePanel) })
                    )
                    .toggleStyle(.switch)
                    HStack {
                        detail(localized("Show / hide the panel"))
                        Spacer()
                        Button {
                            if bindings.recordingAction == .togglePanel {
                                bindings.endRecording()
                            } else {
                                bindings.beginRecording(.togglePanel)
                            }
                        } label: {
                            OnboardingKeycap(
                                text: bindings.recordingAction == .togglePanel
                                    ? localized("Press a shortcut…") : bindings.label(for: .togglePanel),
                                recording: bindings.recordingAction == .togglePanel)
                        }.buttonStyle(OnboardingButtonStyle(treatment: .quiet))
                    }
                    detail(
                        localized(
                            "Click the shortcut to change it. Press Esc to cancel."
                        ))
                    if bindings.registrationFailures.contains(.togglePanel)
                        || bindings.duplicatedActions.contains(.togglePanel)
                    {
                        Label(
                            localized("This shortcut is unavailable or duplicated. Choose another combination."),
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            OnboardingSurface {
                VStack(alignment: .leading, spacing: 12) {
                    Picker(localized("History capacity"), selection: $general.capacity) {
                        ForEach(GeneralSettingsStore.capacityChoices, id: \.self) {
                            Text(GeneralSettingsStore.capacityLabel($0)).tag($0)
                        }
                    }
                    Picker(localized("Keep history for"), selection: $general.retentionPeriod) {
                        ForEach(RetentionPeriodOption.allCases) { Text($0.label).tag($0) }
                    }
                    detail(
                        localized(
                            "Lower limits can remove unpinned history immediately."
                        ))
                }
            }
            HStack(spacing: 18) {
                settingLink(localized("Appearance and card size"), section: .cards)
                settingLink(localized("Sounds and effects"), section: .sounds)
                settingLink(localized("Online content"), section: .network)
            }
            OnboardingDisclosure(localized("More ways to make it yours")) {
                VStack(alignment: .leading, spacing: 12) {
                    settingLink(localized("Menu bar and Dock"), section: .menuAndDock)
                    settingLink(localized("Menu bar icons"), section: .statusIcons)
                    settingLink(localized("Colors"), section: .colors)
                    settingLink(localized("Pinned items"), section: .pinnedItems)
                    settingLink(localized("About this App"), section: .aboutApp)
                }.padding(.top, 8)
            }.font(.callout)
        }
    }

    private var guide: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingSurface {
                VStack(spacing: 11) {
                    ForEach([KeyAction.togglePanel, .togglePinned, .pasteNextFromStack, .togglePrivacy], id: \.self) {
                        shortcutRow($0)
                    }
                    Divider().padding(.vertical, 2)
                    ForEach(
                        [
                            KeyAction.pasteSelection, .pastePlain, .copySelection, .previewSelection,
                            .pinSelection, .stackSelection, .editSelection, .undoLastChange,
                        ], id: \.self
                    ) { shortcutRow($0) }
                }
            }
            settingLink(localized("Customize all shortcuts and Vim navigation"), section: .panelShortcuts)
            OnboardingDisclosure(localized("Inside the clipboard panel")) {
                VStack(spacing: 11) {
                    ForEach(
                        [
                            KeyAction.previousCard, .nextCard, .rowUp, .rowDown, .switchChipGroup,
                            .deleteSelection, .openSelection, .revealSelection, .saveSelection,
                            .excludeSelectionSource, .deleteSelectionSource,
                        ], id: \.self
                    ) { shortcutRow($0) }
                    HStack {
                        Text(localized("Close the panel")).font(.system(size: 12))
                        Spacer()
                        OnboardingKeycap(text: "esc")
                    }
                }.padding(.top, 10)
            }
            OnboardingDisclosure(localized("Nothing is appearing in my history")) {
                detail(
                    localized(
                        "Copy something new. If it doesn’t appear, check clipboard access, capture status and app exclusions."
                    )
                )
                .padding(.top, 8)
            }
            OnboardingDisclosure(localized("A card copies, but does not paste")) {
                detail(
                    localized(
                        "Focus a field in the destination app and check Accessibility. You can also copy the card and press ⌘V."
                    )
                )
                .padding(.top, 8)
            }
            OnboardingDisclosure(localized("Where are settings and my pinned items?")) {
                detail(
                    localized(
                        "Right-click the menu bar icon for settings and pinned items."
                    )
                )
                .padding(.top, 8)
            }
        }
        .font(.callout)
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingIllustration(scene: .ready, menuSymbol: appearance.defaultStatusSymbol).frame(height: 180)
            intro(
                localized(
                    "Copy something, then open your history."
                ))
            OnboardingSurface {
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
                    readinessRow(
                        localized("Practice"),
                        value: state.isPracticeComplete ? localized("Completed") : localized("Try it anytime"),
                        ready: state.isPracticeComplete)
                }
            }
            if state.clipboardAccess != .granted || !state.accessibilityGranted {
                Button(localized("Review permissions")) { navigate(to: .permissions) }
                    .buttonStyle(OnboardingButtonStyle(treatment: .quiet))
                    .foregroundStyle(OnboardingStyle.green)
            }
        }
    }

    private func intro(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func detail(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func statusHeading(_ title: String, granted: Bool) -> some View {
        HStack {
            Text(title).font(.system(size: 14, weight: .semibold))
            Spacer()
            Label(
                granted ? localized("Ready") : localized("Not enabled"),
                systemImage: granted ? "checkmark.circle.fill" : "circle.dashed"
            )
            .font(.caption).foregroundStyle(granted ? OnboardingStyle.green : .secondary)
            .contentTransition(.opacity)
        }
    }

    private func shortcutRow(_ action: KeyAction) -> some View {
        HStack(spacing: 16) {
            Text(action.displayName).font(.system(size: 12))
            Spacer(minLength: 8)
            if action.isGlobal && !bindings.isGlobalEnabled(action) {
                Text(localized("Off")).font(.caption).foregroundStyle(.secondary)
            }
            OnboardingKeycap(text: bindings.label(for: action))
        }
    }

    private func feature(_ symbol: String, _ title: String, _ text: String, section: SettingsSectionID) -> some View {
        Button {
            bindings.endRecording()
            actions.openSettings(SettingsDestination(section: section))
        } label: {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(OnboardingStyle.green)
                    .frame(width: 36, height: 36)
                    .background(OnboardingStyle.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    detail(text)
                }
                Spacer(minLength: 12)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(OnboardingButtonStyle(treatment: .quiet))
        .help(localized("View in Settings"))
        .accessibilityHint(localized("View in Settings"))
    }

    private func settingLink(_ title: String, section: SettingsSectionID) -> some View {
        Button {
            bindings.endRecording(); actions.openSettings(SettingsDestination(section: section))
        } label: {
            HStack(spacing: 4) {
                Text(title).fixedSize(horizontal: false, vertical: true)
                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
            }
            .font(.system(size: 11, weight: .medium))
        }.buttonStyle(OnboardingButtonStyle(treatment: .quiet))
            .foregroundStyle(OnboardingStyle.green)
    }

    private func readinessRow(_ title: String, value: String, ready: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ready ? "checkmark.circle.fill" : "circle.dashed")
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(ready ? OnboardingStyle.green : .secondary)
            Text(title).font(.callout)
            Spacer()
            Text(value).font(.callout).foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
        .animation(OnboardingMotion.detail, value: value)
        .animation(OnboardingMotion.detail, value: ready)
    }
}

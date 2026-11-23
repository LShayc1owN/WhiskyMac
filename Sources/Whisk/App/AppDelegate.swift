// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private typealias Controller = ClipboardController<AppKitPasteboard, SystemClock, AnyHistoryStore, ConsoleLogger>

    private let privacy = PrivacyController(startInDefaultMode: true)
    private let diagnostics: DiagnosticLogStore
    private let logger: ConsoleLogger
    private let defaults: UserDefaults
    private let developerMode: DeveloperModeStore
    private let keyBindings: KeyBindingsStore
    private let generalSettings: GeneralSettingsStore
    private let copySoundPlayer = CopySoundPlayer()
    private let appearance = AppearanceSettingsStore()
    private let vimKeymap = VimBindingsStore()
    private let loginItem = LoginItemManager()
    private let updateChecker: UpdateChecker
    private var onboardingWindow: NSWindow?
    private var onboardingState: OnboardingState?
    private var settingsObserver: AnyCancellable?
    private var privacyObserver: AnyCancellable?
    private var statusItem: NSStatusItem?
    private let statusSymbol = StatusBarSymbol()
    private var panelController: PanelController?
    private var hotKey: HotKey?
    private var pinnedHotKey: HotKey?
    private var privacyHotKey: HotKey?
    private var stackHotKey: HotKey?
    private var layoutObserver: NSObjectProtocol?
    private var bindingsObserver: AnyCancellable?
    private var settingsWindow: NSWindow?
    private let settingsSearch = SettingsSearchModel()
    // NSToolbar holds its delegate weakly.
    private var settingsSearchToolbar: AnyObject?
    private var stateStore: HistoryViewStateStore?
    private var clipboard: Controller?
    private var thumbnailPreparation: PanelThumbnailPreparation?
    private var pollTimer: Timer?
    private var memoryPressure: DispatchSourceMemoryPressure?
    private var sharingMonitor: SharingMonitor?
    private var windowObserver: NSObjectProtocol?
    private var colorObserver: NSObjectProtocol?
    private var sessionObservers: [NSObjectProtocol] = []

    override init() {
        let defaults = AppIdentity.defaults
        let build = AppBuildInfo.current
        let diagnostics = DiagnosticLogStore(build: build) {
            try AppIdentity.dataDirectory().appendingPathComponent("Logs", isDirectory: true)
        }
        let smokeTest = CommandLine.arguments.contains("--smoke-test")
        let logger = ConsoleLogger(record: smokeTest ? nil : diagnostics.record)
        logger.log(.appStarted)
        self.defaults = defaults
        self.diagnostics = diagnostics
        self.logger = logger
        developerMode = DeveloperModeStore(defaults: defaults, channel: build.channel)
        keyBindings = KeyBindingsStore(defaults: defaults, logger: logger)
        generalSettings = GeneralSettingsStore(defaults: defaults, logger: logger)
        updateChecker = UpdateChecker(logger: logger, defaults: defaults)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLocalization.language = appearance.language.code
        AppAccent.color = appearance.nsAccent
        appearance.changed = { [weak self] in self?.applyAppearance() }
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let window = note.object as? NSWindow,
                window === self.settingsWindow || window === self.onboardingWindow
            else { return }
            if window === self.settingsWindow {
                self.panelController?.cancelSizePreview()
                NotificationCenter.default.post(name: .settingsWindowClosed, object: nil)
            } else {
                self.keyBindings.endRecording()
                self.onboardingWindow = nil
            }
            self.updateDockIcon(excluding: window)
        }
        colorObserver = NotificationCenter.default.addObserver(
            forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyAppearance(forceColor: true)
        }
        updateDockIcon()
        let opened = openStore()
        let stateStore = HistoryViewStateStore()
        stateStore.setPrivacyPermissions(
            allowSearch: privacy.allowSearchWhileProtected,
            showSourceApps: privacy.showSourceAppsWhileProtected,
            allowFiltering: privacy.allowFilteringWhileProtected,
            allowAppFiltering: privacy.allowAppFilteringWhileProtected,
            allowHandoffFiltering: privacy.allowHandoffFilteringWhileProtected)
        stateStore.setPrivacy(privacy.isProtected)
        stateStore.setSpotlightAllowed(privacy.allowsSpotlight)
        stateStore.spotlight = privacy.spotlight
        stateStore.interactions = generalSettings.interactions
        stateStore.privacyInteractions = generalSettings.privacyInteractions
        stateStore.appFilterTrigger = generalSettings.appFilterTrigger
        let clipboard = ClipboardController(
            pasteboard: AppKitPasteboard(didWrite: { [weak self] in
                guard let self else { return }
                self.copySoundPlayer.play(
                    .historyCopy, preferences: self.generalSettings.copySound,
                    protected: self.privacy.isProtected)
            }),
            store: opened.store,
            clock: SystemClock(),
            retention: generalSettings.policy,
            initialItems: opened.items,
            searchMatchMode: defaults.string(forKey: "searchMatchMode").flatMap(SearchMatchMode.init(rawValue:))
                ?? .fuzzy,
            logger: logger
        ) { [weak self] state in
            stateStore.update(state)
            self?.thumbnailPreparation?.schedule()
        }
        self.stateStore = stateStore
        self.clipboard = clipboard
        stateStore.contentCacheVisibility = { [weak self, weak clipboard] visible in
            clipboard?.setContentCacheEnabled(visible)
            self?.thumbnailPreparation?.setPanelVisible(visible)
            if !visible { LinkPreviewStore.shared.releaseCache() }
        }
        clipboard.setContentCacheEnabled(false)
        let pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        pressure.setEventHandler { [weak self] in
            guard let self, let event = self.memoryPressure?.data else { return }
            let pressured = !event.intersection([.warning, .critical]).isEmpty
            self.thumbnailPreparation?.setMemoryPressure(pressured)
            guard pressured else { return }
            self.clipboard?.releaseContentCache()
            SourceAppStyle.releaseCache()
            LinkPreviewStore.shared.releaseCache()
        }
        pressure.resume()
        memoryPressure = pressure
        clipboard.hiddenLinksChanged = { LinkPreviewStore.shared.setHiddenAddresses($0) }
        LinkPreviewStore.shared.setHiddenAddresses(clipboard.hiddenLinkAddresses)
        clipboard.didRecord = { [weak self] in
            guard let self else { return }
            self.copySoundPlayer.play(
                .captured, preferences: self.generalSettings.copySound,
                protected: self.privacy.isProtected)
        }
        stateStore.protectedSearch = { [weak clipboard] query in clipboard?.search(query) }
        stateStore.protectedFilter = { [weak clipboard] action in
            switch action {
            case .toggleApp(let key): clipboard?.toggleSourceFilter(key)
            case .selectApp(let key): clipboard?.selectSourceFilter(key)
            case .selectKind(let key): clipboard?.selectCategoryFilter(key)
            case .toggleKind(let key): clipboard?.toggleCategoryFilter(key)
            case .reset: clipboard?.toggleCategoryFilter(allFiltersChipID)
            }
        }
        clipboard.retainSensitive = { [weak self, weak stateStore] snapshot in
            guard let self, let bundleID = snapshot.source?.bundleID,
                self.generalSettings.sensitiveBundleIDs.contains(bundleID),
                !self.generalSettings.excludedBundleIDs.contains(bundleID)
            else { return }
            stateStore?.sensitiveSession.setRetention(minutes: self.generalSettings.sensitiveRetentionMinutes)
            stateStore?.sensitiveSession.receive(snapshot)
        }
        stateStore.sensitiveSession.copyToPasteboard = { payload, rtf in
            AppKitPasteboard().writeSensitive(payload, rtf: rtf)
        }
        let sessionCenter = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ] {
            sessionObservers.append(
                sessionCenter.addObserver(forName: name, object: nil, queue: .main) {
                    [weak stateStore] _ in stateStore?.sensitiveSession.clear()
                })
        }
        stateStore.detailSource = { [weak clipboard] id in clipboard?.item(for: id) }
        stateStore.detailsSource = { [weak clipboard] ids in clipboard?.items(for: ids) ?? [] }

        // Filtering re-renders a screenful of glass cards, so keystrokes
        // coalesce: only the last query of a typing burst runs.
        let searchDebounce = Debouncer(delay: 0.18)
        stateStore.searchMatchModeChanged = { [weak clipboard, defaults] mode, query in
            searchDebounce.cancel()
            defaults.set(mode.rawValue, forKey: "searchMatchMode")
            clipboard?.setSearchMatchMode(mode, query: query)
        }
        let actions = PanelWiring.actions(
            for: clipboard,
            searchDebounce: searchDebounce,
            hidePanel: { [weak self] in self?.panelController?.hide() },
            paste: { [weak self] in self?.panelController?.pasteToPreviousApplication() },
            dragBegan: { [weak self] in self?.panelController?.dragDidBegin() },
            system: PanelWiring.SystemActions(
                openLink: { NSWorkspace.shared.open($0) },
                revealFiles: { paths in
                    NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(fileURLWithPath: $0) })
                },
                saveToDisk: { [logger] in SaveToDisk.present($0, logger: logger) },
                excludeSource: { [weak self] bundleID, name in
                    guard let self, !self.generalSettings.excludedApps.contains(where: { $0.bundleID == bundleID })
                    else { return }
                    self.generalSettings.excludeApp(ExcludedApp(bundleID: bundleID, name: name))
                },
                beginEditing: { stateStore.beginEditing($0) },
                openPasteboardSettings: { [weak self] in self?.openPasteboardSettings() }
            )
        )
        stateStore.protectedExport = { [weak self, weak clipboard] id, action in
            guard self?.privacy.isProtected == true else { return }
            guard clipboard?.select(id, forPaste: action == .paste) == true else { return }
            self?.panelController?.hide()
            if action == .paste { self?.panelController?.pasteToPreviousApplication(explicitProtectedExport: true) }
        }
        stateStore.beginSplit = { [weak stateStore, weak clipboard] id in
            guard let stateStore, let clipboard, !stateStore.isProtected, stateStore.panelVisible,
                let item = clipboard.item(for: id),
                !item.pinnedMetadata.hidesContent, item.splitGroup == nil,
                item.payload.transformableText != nil
            else { return }
            stateStore.hidePreview?()
            stateStore.closeSplitSessions()
            let session = SplitSession(
                source: item, current: { [weak clipboard] in clipboard?.item(for: $0) },
                allowed: { [weak stateStore] in stateStore?.isProtected == false && stateStore?.panelVisible == true },
                assess: { [weak clipboard] request in
                    guard let clipboard else { throw SplitFailure.unavailable };
                    return try clipboard.assessSplit(request)
                },
                save: { [weak clipboard] request, confirm in
                    guard let clipboard else { throw SplitFailure.unavailable };
                    try clipboard.saveSplit(request, confirmEviction: confirm)
                })
            session.completed = { [weak stateStore] in stateStore?.closeSplitSessions() }
            stateStore.splitSession = session
            stateStore.auxiliaryDidChange()
        }
        clipboard.requestGroupSelection = { [weak self, weak stateStore, weak clipboard] id, plain, paste in
            guard let stateStore, let clipboard, !stateStore.isProtected, stateStore.panelVisible,
                let item = clipboard.item(for: id), item.splitGroup != nil
            else { return }
            stateStore.hidePreview?()
            stateStore.closeSplitSessions()
            let session = SplitGroupSession(
                source: item, action: paste ? .paste : .copy, plain: plain, query: stateStore.state.query,
                searchMatchMode: stateStore.searchMatchMode,
                current: { [weak clipboard] in clipboard?.item(for: $0) },
                allowed: { [weak stateStore] in stateStore?.isProtected == false && stateStore?.panelVisible == true },
                export: { [weak clipboard] item, selected, original, plain, paste in
                    guard let clipboard else { throw SplitFailure.unavailable }
                    try clipboard.exportGroup(
                        item, selected: selected, original: original, plain: plain,
                        forPaste: paste, combine: SplitContentCodec.combine)
                })
            session.completed = { [weak self, weak stateStore] in
                stateStore?.closeSplitSessions()
                self?.panelController?.hide()
                if paste { self?.panelController?.pasteToPreviousApplication() }
            }
            stateStore.splitGroupSession = session
            stateStore.auxiliaryDidChange()
        }
        var guardedActions = actions
        guardedActions.split = { [weak stateStore, weak clipboard] id in
            guard let stateStore, let clipboard, !stateStore.isProtected else { return }
            if let card = stateStore.state.cards.first(where: { $0.id == id }), card.variantIDs.count > 1 {
                let candidates = clipboard.items(for: card.variantIDs)
                stateStore.chooseSplitVersion(candidates)
            } else {
                stateStore.beginSplit(id)
            }
        }
        guardedActions.editRich = { [weak clipboard] id, text, rtf in clipboard?.editRich(id, text: text, rtf: rtf) }
        guardedActions.metadataEditorChanged = { [weak stateStore] editing in
            guard let stateStore, stateStore.pinMetadataEditing != editing else { return }
            stateStore.pinMetadataEditing = editing
        }
        guardedActions.cardMenuChanged = { [weak stateStore] in stateStore?.cardMenuOpen = $0 }
        guardedActions = guardedActions.guarded { [weak stateStore] in stateStore?.isProtected != false }
        let panelController = PanelController(
            stateStore: stateStore, actions: guardedActions, keyBindings: keyBindings,
            vimBindings: vimKeymap, appearanceMode: appearance.clipboardAppearance,
            vimMode: { [weak self] in self?.generalSettings.vimNavigation ?? false }
        )
        self.panelController = panelController
        panelController.sizePreviewEnded = { [weak self] in self?.applyClipboardSizing() }
        privacy.displayPermissionsChanged = { [weak self, weak stateStore] in
            guard let self else { return }
            stateStore?.setPrivacyPermissions(
                allowSearch: self.privacy.allowSearchWhileProtected,
                showSourceApps: self.privacy.showSourceAppsWhileProtected,
                allowFiltering: self.privacy.allowFilteringWhileProtected,
                allowAppFiltering: self.privacy.allowAppFilteringWhileProtected,
                allowHandoffFiltering: self.privacy.allowHandoffFilteringWhileProtected)
            if self.privacy.isProtected { self.panelController?.privacyDidChange() }
        }
        privacy.spotlightSettingsChanged = { [weak stateStore] in stateStore?.spotlight = $0 }
        privacy.willChangeSpotlight = { [weak stateStore] allowed in
            stateStore?.setSpotlightAllowed(allowed)
        }
        privacy.willChangeProtection = { [weak self, weak stateStore] protected in
            searchDebounce.cancel()
            if protected { self?.copySoundPlayer.stop() }
            self?.thumbnailPreparation?.setPrivacy(protected)
            stateStore?.setPrivacy(protected)
            self?.panelController?.privacyDidChange()
            LinkPreviewStore.shared.setPrivacy(protected)
            if protected { self?.clipboard?.releaseContentCache() }
            self?.updateStatusIcon(protected: protected)
        }
        LinkPreviewStore.shared.setPrivacy(privacy.isProtected)

        sharingMonitor = SharingMonitor { [weak self] report in
            self?.privacy.receive([report])
            if let self { self.updateStatusIcon(protected: self.privacy.isProtected) }
        }
        privacy.automaticSettingChanged = { [weak self] enabled in
            guard let self else { return }
            if enabled { self.sharingMonitor?.start() } else { self.sharingMonitor?.stop() }
            self.updateStatusIcon(protected: self.privacy.isProtected)
        }
        if privacy.automaticEnabled, !CommandLine.arguments.contains("--smoke-test") { sharingMonitor?.start() }

        privacyObserver = privacy.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self else { return }
            self.updateStatusIcon(protected: self.privacy.isProtected)
        }
        configureStatusItem()
        registerHotKey()
        observeKeyboardLayoutChanges()
        // @Published emits on willSet: hop to the next main-queue cycle so
        // registerHotKey reads the binding after it has actually landed —
        // otherwise every recording applies the previous shortcut.
        bindingsObserver = keyBindings.$overrides.combineLatest(keyBindings.$enabledGlobalActions)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.registerHotKey()
            }
        clipboard.applyRetention(generalSettings.policy)
        clipboard.applyExclusions(generalSettings.excludedBundleIDs)
        clipboard.applySensitiveSources(generalSettings.sensitiveBundleIDs)
        stateStore.sensitiveSession.setRetention(minutes: generalSettings.sensitiveRetentionMinutes)
        LinkPreviewStore.shared.setEnabled(generalSettings.linkPreviews)
        applyClipboardSizing()
        thumbnailPreparation = PanelThumbnailPreparation(
            images: .shared, files: .shared, lightweight: generalSettings.lightweightMode,
            protected: privacy.isProtected
        ) { [weak clipboard, weak stateStore] in
            guard let clipboard, let stateStore else { return [] }
            let width = NSScreen.screens.map(\.frame.width).max() ?? 0
            return clipboard.openingThumbnailItems(
                slotLimit: PanelThumbnailPreparation.slotLimit(width: width, stride: stateStore.cardStride))
        }
        clipboard.setLayoutDirection(
            NSApp.userInterfaceLayoutDirection == .rightToLeft ? .rightToLeft : .leftToRight)
        // willSet semantics again: hop to the next cycle so the policy is
        // read after the setting has landed.
        var sensitivePolicy = generalSettings.sensitiveApps
        var exclusions = generalSettings.excludedApps
        settingsObserver = generalSettings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.thumbnailPreparation?.setLightweightMode(self.generalSettings.lightweightMode)
                if self.generalSettings.copySound.safeVolume == 0
                    || (!self.generalSettings.copySound.onCapture && !self.generalSettings.copySound.onHistoryCopy)
                {
                    self.copySoundPlayer.stop()
                }
                self.clipboard?.applyRetention(self.generalSettings.policy)
                if let session = self.stateStore?.sensitiveSession,
                    session.retentionMinutes != self.generalSettings.sensitiveRetentionMinutes
                {
                    session.setRetention(minutes: self.generalSettings.sensitiveRetentionMinutes)
                }
                LinkPreviewStore.shared.setEnabled(self.generalSettings.linkPreviews)
                self.applyClipboardSizing()
                if let state = self.stateStore {
                    if state.interactions != self.generalSettings.interactions {
                        state.interactions = self.generalSettings.interactions
                    }
                    if state.privacyInteractions != self.generalSettings.privacyInteractions {
                        state.privacyInteractions = self.generalSettings.privacyInteractions
                    }
                    if state.appFilterTrigger != self.generalSettings.appFilterTrigger {
                        state.appFilterTrigger = self.generalSettings.appFilterTrigger
                    }
                }
                if sensitivePolicy != self.generalSettings.sensitiveApps
                    || exclusions != self.generalSettings.excludedApps
                {
                    self.clipboard?.applyExclusions(self.generalSettings.excludedBundleIDs)
                    self.clipboard?.applySensitiveSources(self.generalSettings.sensitiveBundleIDs)
                    self.stateStore?.sensitiveSession.clear()
                    sensitivePolicy = self.generalSettings.sensitiveApps
                    exclusions = self.generalSettings.excludedApps
                }
            }
        if !CommandLine.arguments.contains("--smoke-test") {
            startPolling(clipboard)
        }

        if Distribution.current.checksForUpdates, generalSettings.checkForUpdates {
            updateChecker.checkNow(automatic: true)
        }
        if !defaults.bool(forKey: "didShowOnboarding"),
            !CommandLine.arguments.contains("--smoke-test")
        {
            showOnboarding()
        }

        if CommandLine.arguments.contains("--show-panel") {
            panelController.show()
        }
        if CommandLine.arguments.contains("--show-settings") {
            DispatchQueue.main.async { [weak self] in
                self?.openSettings()
            }
        }

        // Exercised by the release pipeline against the packaged app: the
        // full wiring above ran (SwiftUI evaluated the panel, resources
        // resolved), so reaching this line is the pass signal.
        if CommandLine.arguments.contains("--smoke-test") {
            print(
                "smoke test passed (distribution: \(Distribution.current), bundle: \(Bundle.main.bundleIdentifier ?? "none"))"
            )
            print("resources: \(AppResources.bundle.bundleURL.path)")
            print("localized copy: \(localized("Copy"))")
            print("localized count: \(localized("\(1) items"))")
            if CommandLine.arguments.contains("--smoke-preferences") { smokePreferences() }
            // An isolated smoke launch can remain alive briefly for an
            // external footprint sample, with capture and hotkeys disabled.
            if CommandLine.arguments.contains("--smoke-memory") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { NSApp.terminate(nil) }
                return
            }
            NSApp.terminate(nil)
        }
    }

    /// Uses only the isolated smoke preferences/history. No clipboard polling,
    /// permission prompts or global shortcuts run in this path.
    private func smokePreferences() {
        appearance.language = .french
        precondition(localized("Copy") == "Copier")
        appearance.language = .german
        precondition(localized("Copy") == "Kopieren")
        appearance.language = .italian
        precondition(localized("Copy") == "Copia")
        appearance.language = .traditionalChinese
        precondition(localized("Copy") == "拷貝")
        appearance.language = .japanese
        precondition(localized("Copy") == "コピー")
        appearance.language = .simplifiedChinese
        precondition(localized("Copy") == "拷贝")
        precondition(settingsWindow == nil)
        appearance.accentMode = .custom
        appearance.customAccent = AccentRGB(red: 0.85, green: 0.2, blue: 0.12)
        precondition(NSColor.matcha == appearance.customAccent.nsColor)
        appearance.dockIcon = .never
        precondition(NSApp.activationPolicy() == .accessory)
        appearance.dockIcon = .always
        precondition(NSApp.activationPolicy() == .regular)
        appearance.dockIcon = .followWindows
        precondition(NSApp.activationPolicy() == .accessory)
        openSettings()
        precondition(settingsWindow?.isVisible == true && NSApp.activationPolicy() == .regular)
        precondition(settingsWindow?.title == localized("WhiskyMac Settings"))
        settingsWindow?.close()
        precondition(NSApp.activationPolicy() == .accessory)
        appearance.statusClick = .menu
        precondition(appearance.statusClick.opensMenu(rightClick: false))
        appearance.statusClick = .history
        precondition(!appearance.statusClick.opensMenu(rightClick: false))
        precondition(appearance.statusClick.opensMenu(rightClick: true))
        appearance.language = .system
        appearance.accentMode = .system
        precondition(NSColor.matcha == .controlAccentColor)
        print("preference smoke passed: runtime language, accent, Dock windows and menu mapping")
    }

    /// Launch never fails on storage: HistoryStorage recovers from a
    /// database that will not open, and an unreachable Application
    /// Support leaves the session running in memory.
    private func openStore() -> HistoryStorage.OpenedHistory {
        do {
            return HistoryStorage.openAndLoad(in: try HistoryStorage.defaultDirectory(), log: logger.log)
        } catch {
            logger.log(.historyDirectoryUnavailable)
            return HistoryStorage.OpenedHistory(store: AnyHistoryStore(VolatileHistoryStore()), items: [])
        }
    }

    /// The user's binding when one is recorded; otherwise ⇧⌘V wherever the
    /// current layout prints a V — Dvorak, AZERTY, … Re-registered on
    /// layout switches and on binding changes.
    private func registerHotKey() {
        keyBindings.registrationFailures = []
        pinnedHotKey = nil
        hotKey = nil
        stackHotKey = nil
        privacyHotKey = nil
        guard !CommandLine.arguments.contains("--smoke-test") else { return }
        if keyBindings.isGlobalEnabled(.togglePrivacy) {
            let binding = keyBindings.binding(for: .togglePrivacy)
            privacyHotKey = HotKey(keyCode: UInt32(binding.keyCode), modifiers: binding.carbonModifiers) {
                [weak self] in
                self?.privacy.toggle()
            }
        }
        if keyBindings.isGlobalEnabled(.togglePinned) {
            let binding = keyBindings.binding(for: .togglePinned)
            pinnedHotKey = HotKey(keyCode: UInt32(binding.keyCode), modifiers: binding.carbonModifiers) { [weak self] in
                self?.showPinnedItems()
            }
        }
        if keyBindings.isGlobalEnabled(.togglePinned), pinnedHotKey == nil {
            keyBindings.registrationFailures.insert(.togglePinned)
        }
        if keyBindings.isGlobalEnabled(.togglePanel) {
            let toggle = keyBindings.binding(for: .togglePanel)
            hotKey = HotKey(keyCode: UInt32(toggle.keyCode), modifiers: toggle.carbonModifiers) { [weak self] in
                self?.panelController?.toggle()
            }
        }
        if keyBindings.isGlobalEnabled(.pasteNextFromStack) {
            let stack = keyBindings.binding(for: .pasteNextFromStack)
            stackHotKey = HotKey(keyCode: UInt32(stack.keyCode), modifiers: stack.carbonModifiers) { [weak self] in
                guard self?.privacy.isProtected == false, self?.clipboard?.popStack() == true else { return }
                PasteSimulator.paste(allowed: { [weak self] in self?.privacy.isProtected == false })
            }
        }
        if keyBindings.isGlobalEnabled(.togglePanel), hotKey == nil {
            keyBindings.registrationFailures.insert(.togglePanel)
        }
        if keyBindings.isGlobalEnabled(.pasteNextFromStack), stackHotKey == nil {
            keyBindings.registrationFailures.insert(.pasteNextFromStack)
        }
        if keyBindings.isGlobalEnabled(.togglePrivacy), privacyHotKey == nil {
            keyBindings.registrationFailures.insert(.togglePrivacy)
        }

    }

    private func observeKeyboardLayoutChanges() {
        layoutObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.registerHotKey()
        }
    }

    private func startPolling(_ clipboard: Controller) {
        let timer = Timer(timeInterval: 0.25, repeats: true) { _ in
            clipboard.pollTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            statusSymbol.install(on: button)
            button.setAccessibilityLabel(AppIdentity.displayName)
        }
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        updateStatusIcon(protected: privacy.isProtected)
    }

    @objc private func statusItemClicked() {
        statusSymbol.wiggle()
        if appearance.statusClick.opensMenu(rightClick: NSApp.currentEvent?.type == .rightMouseUp) {
            presentMenu()
        } else {
            panelController?.toggle()
        }
    }

    private var isPaused = false

    @objc private func togglePause() {
        isPaused.toggle()
        clipboard?.setPaused(isPaused)
        updateStatusIcon(protected: privacy.isProtected)
    }

    private func updateStatusIcon(protected: Bool) {
        let image = AppSymbol.image(
            named: appearance.statusSymbolName(protected: protected, paused: isPaused),
            pointSize: StatusBarSymbol.pointSize)
        image?.isTemplate = true
        statusSymbol.imageView.image = image
        statusItem?.button?.toolTip = AppIdentity.displayName + " — " + privacy.statusText
    }

    @objc private func togglePrivacy() { privacy.toggle() }

    private func presentMenu() {
        let menu = NSMenu()
        menu.addItem(StatusMenuMessage.item(for: privacy.statusText))
        menu.addItem(
            menuItem(
                title: privacy.isManuallyProtected
                    ? localized("Turn off manual protection") : localized("Turn on manual protection"),
                action: #selector(togglePrivacy), shortcut: .togglePrivacy))
        menu.addItem(
            menuItem(
                title: localized("Show History"),
                action: #selector(showPanel), shortcut: .togglePanel))
        menu.addItem(
            menuItem(
                title: isPaused ? localized("Resume Capture") : localized("Pause Capture"),
                action: #selector(togglePause)))
        menu.addItem(
            menuItem(title: localized("Pinned items"), action: #selector(showPinnedItems), shortcut: .togglePinned))
        menu.addItem(menuItem(title: localized("Clear Unpinned Items"), action: #selector(clearHistory)))
        menu.addItem(
            menuItem(
                title: localized("Undo Last Change"), action: #selector(undoLastChange), shortcut: .undoLastChange))
        if let clipboard, clipboard.clipboardAccess != .granted {
            menu.addItem(.separator())
            menu.addItem(
                menuItem(title: localized("Allow Clipboard Access…"), action: #selector(allowClipboardAccess)))
        }
        if let release = updateChecker.availableRelease {
            menu.addItem(.separator())
            let update = menuItem(
                title: String(format: localized("Update Available (v%@)…"), release.version),
                action: #selector(openUpdateRelease(_:)))
            update.representedObject = release.page
            menu.addItem(update)
        }
        menu.addItem(.separator())
        if Distribution.current.checksForUpdates {
            menu.addItem(menuItem(title: localized("Check for updates"), action: #selector(checkForUpdatesFromMenu)))
        }
        menu.addItem(menuItem(title: localized("Settings…"), action: #selector(openSettings)))
        menu.addItem(menuItem(title: localized("Welcome Guide"), action: #selector(openWelcomeGuide)))
        menu.addItem(menuItem(title: localized("Licenses and notices…"), action: #selector(openLegalNotices)))
        menu.addItem(menuItem(title: localized("Quit WhiskyMac"), action: #selector(quit)))
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    private func menuItem(title: String, action: Selector, shortcut: KeyAction? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let shortcut,
            (!shortcut.isGlobal || keyBindings.isGlobalEnabled(shortcut)),
            let equivalent = keyBindings.binding(for: shortcut).menuKeyEquivalent
        {
            item.keyEquivalent = equivalent
            item.keyEquivalentModifierMask = keyBindings.binding(for: shortcut).modifiers
        }
        return item
    }

    @objc private func showPinnedItems() {
        panelController?.togglePinned(
            presentation: generalSettings.pinnedPresentation, style: generalSettings.pinnedWindowStyle)
    }

    @objc private func showPanel() {
        panelController?.show()
    }

    @objc private func allowClipboardAccess() {
        clipboard?.requestClipboardAccess()
        openPasteboardSettings()
    }

    /// The pane where the user allows Whisk to read the pasteboard for good.
    private func openPasteboardSettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Pasteboard")
        else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openUpdateRelease(_ item: NSMenuItem) {
        guard let url = item.representedObject as? URL, url == updateChecker.availableRelease?.page else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func checkForUpdatesFromMenu() {
        updateChecker.checkNow()
        showSettings(destination: SettingsDestination(section: .aboutApp))
    }

    @objc private func openWelcomeGuide() {
        if onboardingWindow?.isVisible != true, defaults.bool(forKey: "didShowOnboarding") {
            onboardingState?.select(.welcome)
        }
        showOnboarding()
    }

    private func closeOnboarding() {
        keyBindings.endRecording()
        onboardingWindow?.close()
        onboardingWindow = nil
    }

    private func showOnboarding(fromBeginning: Bool = false) {
        if let window = onboardingWindow, window.isVisible {
            if fromBeginning { onboardingState?.restart() }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let state =
            onboardingState
            ?? OnboardingState(
                defaults: defaults,
                readClipboardAccess: { [weak self] in self?.clipboard?.clipboardAccess ?? .requiresConsent })
        onboardingState = state
        if fromBeginning { state.restart() }
        let hosting = NSHostingController(
            rootView: OnboardingView(
                state: state, bindings: keyBindings, general: generalSettings,
                appearance: appearance, loginItem: loginItem,
                actions: OnboardingActions(
                    allowClipboard: { [weak self] in
                        self?.clipboard?.requestClipboardAccess()
                        self?.openPasteboardSettings()
                    },
                    allowAccessibility: {
                        let options =
                            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                        _ = AXIsProcessTrustedWithOptions(options)
                        if let url = URL(
                            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                        {
                            NSWorkspace.shared.open(url)
                        }
                    },
                    openSettings: { [weak self] in self?.showSettings(destination: $0) },
                    later: { [weak self] in self?.closeOnboarding() },
                    finish: { [weak self] in
                        self?.closeOnboarding()
                        self?.panelController?.show()
                    }))
        )
        let window = NSWindow(contentViewController: hosting)
        OnboardingWindowConfiguration.apply(to: window)
        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1100, height: 800)
        window.setContentSize(NSSize(width: min(980, visible.width - 60), height: min(700, visible.height - 80)))
        onboardingWindow = window
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        updateDockIcon()
        window.makeKeyAndOrderFront(nil)
        updateDockIcon()
    }

    @objc private func openSettings() {
        showSettings(destination: nil)
    }

    private func applyClipboardSizing() {
        guard let stateStore, panelController?.isSizePreview != true else { return }
        let side = CGFloat(generalSettings.cardSide)
        let scale = generalSettings.filterTagScale
        guard stateStore.cardSide != side || stateStore.filterTagScale != scale else { return }
        stateStore.configureCards(side: side)
        stateStore.configureFilterTags(scale: scale)
        panelController?.cardSizeDidChange()
    }

    @MainActor private func exportDiagnostics() async throws {
        guard developerMode.showsTools, let window = settingsWindow, window.isVisible else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = DiagnosticLogStore.suggestedFilename()
        panel.canCreateDirectories = true
        let destination: URL? = await withCheckedContinuation { continuation in
            panel.beginSheetModal(for: window) { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
        guard developerMode.showsTools else { return }
        try await diagnostics.export(to: destination)
    }

    private func makeSettingsWindow(initialPage: SettingsPage) -> NSWindow {
        let clearHistory: () -> Void = { [weak self] in self?.clipboard?.clear() }
        let showWelcomeGuide = { [weak self] in
            guard let self, self.developerMode.showsTools else { return }
            self.showOnboarding(fromBeginning: true)
        }
        let exportDiagnostics: () async throws -> Void = { [weak self] in try await self?.exportDiagnostics() }
        let previewClipboard: (Double, Double) -> Void = { [weak self] side, scale in
            self?.panelController?.previewSize(cardSide: side, tagScale: scale)
        }
        let cancelClipboardPreview: () -> Void = { [weak self] in self?.panelController?.cancelSizePreview() }
        let canFocusSearch = { [weak self] in self?.keyBindings.recordingAction == nil }

        let window: NSWindow
        if #available(macOS 26, *) {
            window = MainActor.assumeIsolated {
                MacOS26SettingsWindow.make(
                    rootView: MacOS26SettingsView(
                        store: keyBindings, general: generalSettings, loginItem: loginItem,
                        vimBindings: vimKeymap, privacy: privacy, clearHistory: clearHistory,
                        showWelcomeGuide: showWelcomeGuide, exportDiagnostics: exportDiagnostics,
                        previewClipboard: previewClipboard, cancelClipboardPreview: cancelClipboardPreview,
                        appearance: appearance, updateChecker: updateChecker, search: settingsSearch,
                        developerMode: developerMode, selectedPage: initialPage)
                )
            }
            settingsSearchToolbar = MacOS26SettingsToolbar(
                window: window, search: settingsSearch, appearance: appearance, canFocus: canFocusSearch)
        } else {
            let hosting = NSHostingController(
                rootView: SettingsView(
                    store: keyBindings, general: generalSettings, loginItem: loginItem,
                    vimBindings: vimKeymap, privacy: privacy, clearHistory: clearHistory,
                    showWelcomeGuide: showWelcomeGuide, exportDiagnostics: exportDiagnostics,
                    previewClipboard: previewClipboard, cancelClipboardPreview: cancelClipboardPreview,
                    appearance: appearance, updateChecker: updateChecker, search: settingsSearch,
                    developerMode: developerMode, selectedPage: initialPage)
            )
            window = NSWindow(contentViewController: hosting)
            // SwiftUI sizing is lazy: without this the window materializes
            // at 1×32 points and is effectively invisible.
            window.setContentSize(hosting.view.fittingSize)
            window.styleMask.remove([.resizable, .miniaturizable])
            SettingsWindowConfiguration.apply(to: window)
            settingsSearchToolbar = SettingsSearchToolbar(
                window: window, search: settingsSearch, appearance: appearance, canFocus: canFocusSearch)
        }
        window.appearance = appearance.settingsAppearance.nsAppearance
        window.title = localized("WhiskyMac Settings")
        window.isReleasedWhenClosed = false
        return window
    }

    private func showSettings(destination requested: SettingsDestination?) {
        let destination = requested.flatMap {
            $0.resolvedSection(isProtected: privacy.isProtected, showsDeveloperTools: developerMode.showsTools) != nil
                ? $0 : nil
        }
        if settingsWindow == nil {
            settingsWindow = makeSettingsWindow(initialPage: destination?.page ?? .general)
        }
        if let window = settingsWindow {
            let chrome = window.frame.height - window.contentRect(forFrameRect: window.frame).height
            let visibleHeight =
                (window.screen ?? NSScreen.main)?.visibleFrame.height
                ?? (SettingsWindowSize.height + chrome + 2 * SettingsWindowSize.margin)
            window.setContentSize(
                SettingsWindowSize.content(visibleHeight: visibleHeight, chromeHeight: chrome))
        }
        settingsWindow?.center()
        if appearance.dockIcon != .never { NSApp.setActivationPolicy(.regular) }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async {
            if let destination {
                NotificationCenter.default.post(
                    name: .settingsPageRequested,
                    object: destination)
            }
            NotificationCenter.default.post(name: .settingsWindowOpened, object: nil)
        }
        updateDockIcon()
    }

    private func updateDockIcon(excluding closedWindow: NSWindow? = nil) {
        let visible = [settingsWindow, onboardingWindow].compactMap { $0 }
            .filter { $0 !== closedWindow && $0.isVisible }.count
        let policy: NSApplication.ActivationPolicy =
            appearance.dockIcon.isVisible(ordinaryWindowCount: visible)
            ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }

    private func applyAppearance(forceColor: Bool = false) {
        let languageChanged = AppLocalization.language != appearance.language.code
        let accentChanged = !AppAccent.color.isEqual(appearance.nsAccent)
        AppLocalization.language = appearance.language.code
        AppAccent.color = appearance.nsAccent
        settingsWindow?.appearance = appearance.settingsAppearance.nsAppearance
        panelController?.appearanceMode = appearance.clipboardAppearance
        if languageChanged { clipboard?.refreshLocalization() }
        if languageChanged || accentChanged || forceColor {
            stateStore?.appearanceDidChange()
            panelController?.appearanceDidChange()
        }
        settingsWindow?.title = localized("WhiskyMac Settings")
        if languageChanged, let window = onboardingWindow, window.isVisible {
            window.close()
            onboardingWindow = nil
            showOnboarding()
        }
        updateStatusIcon(protected: privacy.isProtected)
        updateDockIcon()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    @objc private func clearHistory() {
        clipboard?.clear()
    }

    @objc private func openLegalNotices() {
        showSettings(destination: SettingsDestination(section: .licenses))
    }

    @objc private func undoLastChange() {
        clipboard?.undo()
    }

    func applicationWillTerminate(_ notification: Notification) {
        copySoundPlayer.stop()
        if CommandLine.arguments.contains("--smoke-test") {
            defaults.removePersistentDomain(forName: AppIdentity.smokeDefaultsDomain)
        }
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        if let colorObserver { NotificationCenter.default.removeObserver(colorObserver) }
        appearance.changed = nil
        sharingMonitor?.stop()
        stateStore?.sensitiveSession.clear()
        sessionObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        sessionObservers = []
        pollTimer?.invalidate()
        memoryPressure?.cancel()
        memoryPressure = nil
        thumbnailPreparation?.release()
        thumbnailPreparation = nil
        if let layoutObserver { DistributedNotificationCenter.default().removeObserver(layoutObserver) }
        bindingsObserver?.cancel()
        settingsObserver?.cancel()
        privacyObserver?.cancel()
        pinnedHotKey = nil
        hotKey = nil
        stackHotKey = nil
        privacyHotKey = nil
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

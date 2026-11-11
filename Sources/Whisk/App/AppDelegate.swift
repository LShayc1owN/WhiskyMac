// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private typealias Controller = ClipboardController<AppKitPasteboard, SystemClock, AnyHistoryStore, ConsoleLogger>

    private let privacy = PrivacyController(startInDefaultMode: true)
    private let logger = ConsoleLogger()
    private let defaults = AppIdentity.defaults
    private let keyBindings = KeyBindingsStore()
    private let generalSettings = GeneralSettingsStore()
    private let copySoundPlayer = CopySoundPlayer()
    private let appearance = AppearanceSettingsStore()
    private let vimKeymap = VimBindingsStore()
    private let loginItem = LoginItemManager()
    private let updateChecker = UpdateChecker()
    private var onboardingWindow: NSWindow?
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
    private var settingsSearchToolbar: SettingsSearchToolbar?
    private var stateStore: HistoryViewStateStore?
    private var clipboard: Controller?
    private var pollTimer: Timer?
    private var sharingMonitor: SharingMonitor?
    private var windowObserver: NSObjectProtocol?
    private var colorObserver: NSObjectProtocol?
    private var sessionObservers: [NSObjectProtocol] = []

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
                self.generalSettings.cancelCardSizePreview()
                NotificationCenter.default.post(name: .settingsWindowClosed, object: nil)
            }
            self.updateDockIcon(excluding: window)
        }
        colorObserver = NotificationCenter.default.addObserver(
            forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyAppearance(forceColor: true)
        }
        updateDockIcon()
        let store = openStore()
        let stateStore = HistoryViewStateStore()
        stateStore.setPrivacyPermissions(
            allowSearch: privacy.allowSearchWhileProtected,
            showSourceApps: privacy.showSourceAppsWhileProtected,
            allowFiltering: privacy.allowFilteringWhileProtected)
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
            store: store,
            clock: SystemClock(),
            retention: generalSettings.policy,
            logger: logger
        ) { state in
            stateStore.update(state)
        }
        self.stateStore = stateStore
        self.clipboard = clipboard
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
                saveToDisk: { SaveToDisk.present($0) },
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
        guardedActions.metadataEditorChanged = { [weak stateStore] in stateStore?.pinMetadataEditing = $0 }
        guardedActions.cardMenuChanged = { [weak stateStore] in stateStore?.cardMenuOpen = $0 }
        guardedActions = guardedActions.guarded { [weak stateStore] in stateStore?.isProtected != false }
        let panelController = PanelController(
            stateStore: stateStore, actions: guardedActions, keyBindings: keyBindings,
            vimBindings: vimKeymap,
            vimMode: { [weak self] in self?.generalSettings.vimNavigation ?? false }
        )
        self.panelController = panelController
        privacy.displayPermissionsChanged = { [weak self, weak stateStore] in
            guard let self else { return }
            stateStore?.setPrivacyPermissions(
                allowSearch: self.privacy.allowSearchWhileProtected,
                showSourceApps: self.privacy.showSourceAppsWhileProtected,
                allowFiltering: self.privacy.allowFilteringWhileProtected)
            if self.privacy.isProtected { self.panelController?.privacyDidChange() }
        }
        privacy.spotlightSettingsChanged = { [weak stateStore] in stateStore?.spotlight = $0 }
        privacy.willChangeSpotlight = { [weak stateStore] allowed in
            stateStore?.setSpotlightAllowed(allowed)
        }
        privacy.willChangeProtection = { [weak self, weak stateStore] protected in
            searchDebounce.cancel()
            if protected { self?.copySoundPlayer.stop() }
            stateStore?.setPrivacy(protected)
            self?.panelController?.privacyDidChange()
            LinkPreviewStore.shared.setPrivacy(protected)
            FileThumbnailStore.shared.setPrivacy(protected)
            self?.updateStatusIcon(protected: protected)
        }
        LinkPreviewStore.shared.setPrivacy(privacy.isProtected)
        FileThumbnailStore.shared.setPrivacy(privacy.isProtected)

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
        stateStore.configureCards(side: CGFloat(generalSettings.effectiveCardSide))
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
                if self.generalSettings.copySound.safeVolume == 0
                    || (!self.generalSettings.copySound.onCapture && !self.generalSettings.copySound.onHistoryCopy)
                {
                    self.copySoundPlayer.stop()
                }
                self.clipboard?.applyRetention(self.generalSettings.policy)
                self.clipboard?.applyExclusions(self.generalSettings.excludedBundleIDs)
                self.clipboard?.applySensitiveSources(self.generalSettings.sensitiveBundleIDs)
                self.stateStore?.sensitiveSession.setRetention(minutes: self.generalSettings.sensitiveRetentionMinutes)
                LinkPreviewStore.shared.setEnabled(self.generalSettings.linkPreviews)
                if let stateStore = self.stateStore {
                    let side = CGFloat(self.generalSettings.effectiveCardSide)
                    if stateStore.cardSide != side {
                        stateStore.configureCards(side: side)
                        self.panelController?.cardSizeDidChange()
                    }
                }
                self.stateStore?.interactions = self.generalSettings.interactions
                self.stateStore?.privacyInteractions = self.generalSettings.privacyInteractions
                self.stateStore?.appFilterTrigger = self.generalSettings.appFilterTrigger
                if sensitivePolicy != self.generalSettings.sensitiveApps
                    || exclusions != self.generalSettings.excludedApps
                {
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
    private func openStore() -> AnyHistoryStore {
        do {
            return HistoryStorage.open(in: try HistoryStorage.defaultDirectory(), log: logger.log)
        } catch {
            logger.log("Application Support unavailable — \(error); history will not be saved this session")
            return AnyHistoryStore(VolatileHistoryStore())
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
        if let version = updateChecker.availableVersion {
            menu.addItem(.separator())
            menu.addItem(
                menuItem(
                    title: String(format: localized("Update Available (v%@)…"), version),
                    action: #selector(openReleasesPage)))
        }
        menu.addItem(.separator())
        if Distribution.current.checksForUpdates {
            menu.addItem(menuItem(title: localized("Check for updates"), action: #selector(checkForUpdatesFromMenu)))
        }
        menu.addItem(menuItem(title: localized("Settings…"), action: #selector(openSettings)))
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

    @objc private func openReleasesPage() {
        if let url = UpdateChecker.releasesPage {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func checkForUpdatesFromMenu() {
        updateChecker.checkNow()
        showSettings(destination: SettingsDestination(section: .aboutApp))
    }

    private func showOnboarding() {
        let hosting = NSHostingController(
            rootView: OnboardingView(
                toggleShortcut: keyBindings.label(for: .togglePanel),
                shortcutEnabled: keyBindings.isGlobalEnabled(.togglePanel),
                clipboardAccess: clipboard?.clipboardAccess ?? .granted,
                onAllowClipboard: { [weak self] in
                    self?.clipboard?.requestClipboardAccess()
                    self?.openPasteboardSettings()
                }
            ) { [weak self] in
                self?.defaults.set(true, forKey: "didShowOnboarding")
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
            }
        )
        let window = NSWindow(contentViewController: hosting)
        window.setContentSize(hosting.view.fittingSize)
        window.styleMask.remove([.resizable, .miniaturizable])
        window.title = localized("Welcome")
        window.isReleasedWhenClosed = false
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

    private func showSettings(destination: SettingsDestination?) {
        if settingsWindow == nil {
            let hosting = NSHostingController(
                rootView: SettingsView(
                    store: keyBindings, general: generalSettings, loginItem: loginItem,
                    vimBindings: vimKeymap, privacy: privacy,
                    clearHistory: { [weak self] in self?.clipboard?.clear() },
                    appearance: appearance, updateChecker: updateChecker, search: settingsSearch,
                    selectedPage: destination?.page ?? .general)
            )
            let window = NSWindow(contentViewController: hosting)
            // SwiftUI sizing is lazy: without this the window materializes
            // at 1×32 points and is effectively invisible.
            window.setContentSize(hosting.view.fittingSize)
            window.styleMask.remove([.resizable, .miniaturizable])
            SettingsWindowConfiguration.apply(to: window)
            settingsSearchToolbar = SettingsSearchToolbar(
                window: window, search: settingsSearch, appearance: appearance
            ) { [weak self] in
                self?.keyBindings.recordingAction == nil
            }
            window.title = localized("WhiskyMac Settings")
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        if let window = settingsWindow, let screen = window.screen ?? NSScreen.main {
            let chrome = window.frame.height - window.contentRect(forFrameRect: window.frame).height
            window.setContentSize(
                SettingsWindowSize.content(visibleHeight: screen.visibleFrame.height, chromeHeight: chrome))
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

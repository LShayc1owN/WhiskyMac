// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Combine
import SwiftUI

@available(macOS 26, *)
final class MacOS26SettingsToolbar: NSObject, NSToolbarDelegate, NSSearchFieldDelegate {
    static let itemID = NSToolbarItem.Identifier("WhiskyMac.macOS26.settingsSearch")
    static let navigationID = NSToolbarItem.Identifier("WhiskyMac.macOS26.settingsNavigation")
    static let brandID = NSToolbarItem.Identifier("WhiskyMac.macOS26.settingsBrand")

    private weak var window: NSWindow?
    private let search: SettingsSearchModel
    private let appearance: AppearanceSettingsStore
    private let buildInfo: AppBuildInfo
    private let canFocus: () -> Bool
    private let searchItem = NSSearchToolbarItem(itemIdentifier: itemID)
    private let navigationItem = NSToolbarItem(itemIdentifier: navigationID)
    private var searchWidth: NSLayoutConstraint?
    private var observations: Set<AnyCancellable> = []
    private var events: Any?
    private var endingSearchInteraction = false
    private(set) var resultsPanel: NSPanel?

    var searchField: NSSearchField { searchItem.searchField }

    init(
        window: NSWindow, search: SettingsSearchModel, appearance: AppearanceSettingsStore,
        buildInfo: AppBuildInfo = .current,
        canFocus: @escaping () -> Bool
    ) {
        self.window = window
        self.search = search
        self.appearance = appearance
        self.buildInfo = buildInfo
        self.canFocus = canFocus
        super.init()

        let field = NSSearchField()
        field.delegate = self
        field.target = self
        field.action = #selector(searchFieldAction)
        field.sendsWholeSearchString = true
        field.setAccessibilityIdentifier("settingsSearchField")
        let standardFont = field.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        appearance.$interfaceTypography.removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self, weak field] typography in
                field?.font = NSFont(
                    descriptor: standardFont.fontDescriptor, size: typography.points(standardFont.pointSize))
                self?.updateSearchWidth()
                self?.updateResultsPanel()
            }.store(in: &observations)
        searchItem.searchField = field
        searchWidth = field.widthAnchor.constraint(equalToConstant: 260)
        searchWidth?.isActive = true
        searchItem.resignsFirstResponderWithCancel = false
        searchItem.visibilityPriority = .high
        navigationItem.target = self
        navigationItem.action = #selector(toggleNavigation)
        navigationItem.isBordered = true
        updateLabels()
        updateSearchField()

        // Layout switches belong to this window. AppKit synchronizes item changes
        // across toolbars that share an identifier, even when autosaving is off.
        let toolbar = NSToolbar(identifier: NSToolbar.Identifier("WhiskyMac.macOS26.settings.\(UUID())"))
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.autosavesConfiguration = false
        window.toolbarStyle = .unified
        window.toolbar = toolbar

        observeChanges(to: window)
        events = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) {
            [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    deinit {
        if let events { NSEvent.removeMonitor(events) }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.navigationID, Self.itemID, .flexibleSpace] + (appearance.navigation == .top ? [Self.brandID] : [])
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.navigationID, Self.itemID, .flexibleSpace, Self.brandID]
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch identifier {
        case Self.itemID: searchItem
        case Self.navigationID: navigationItem
        case Self.brandID: brandItem()
        default: nil
        }
    }

    private func brandItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: Self.brandID)
        item.label = AppIdentity.displayName
        item.isBordered = false
        item.view = NSHostingView(
            rootView: MacOS26SettingsBrand(appearance: appearance, buildInfo: buildInfo, placement: .toolbar))
        return item
    }

    private func observeChanges(to window: NSWindow) {
        search.$query.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.updateSearchField()
        }.store(in: &observations)
        search.$isPresented.combineLatest(search.$results.map(\.count)).receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateResultsPanel() }.store(in: &observations)
        search.$focusRevision.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self, self.window?.isKeyWindow == true, self.window?.attachedSheet == nil,
                self.canFocus(), self.searchField.currentEditor() == nil
            else { return }
            self.searchItem.beginSearchInteraction()
        }.store(in: &observations)
        search.$navigationRevision.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.endSearchInteraction()
        }.store(in: &observations)
        search.$localizationRevision.combineLatest(appearance.$navigation).receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateLabels() }.store(in: &observations)
        appearance.$navigation.removeDuplicates().dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] navigation in self?.updateBrandPlacement(navigation) }.store(in: &observations)

        let notifications = NotificationCenter.default
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            notifications.publisher(for: name, object: window).sink { [weak self] _ in
                self?.updateResultsPanel()
            }.store(in: &observations)
        }
        for name in [NSWindow.didResignKeyNotification, NSWindow.willBeginSheetNotification] {
            notifications.publisher(for: name, object: window).sink { [weak self] _ in
                self?.dismissResults()
            }.store(in: &observations)
        }
        notifications.publisher(for: NSWindow.willCloseNotification, object: window).sink { [weak self] _ in
            self?.search.reset()
            self?.dismissResults()
        }.store(in: &observations)
    }

    private func updateBrandPlacement(_ navigation: SettingsNavigation) {
        guard let toolbar = window?.toolbar else { return }
        let currentIndex = toolbar.items.firstIndex { $0.itemIdentifier == Self.brandID }
        if navigation == .top, currentIndex == nil {
            toolbar.insertItem(withItemIdentifier: Self.brandID, at: toolbar.items.count)
        } else if navigation == .sidebar, let currentIndex {
            toolbar.removeItem(at: currentIndex)
        }
        updateResultsPanel()
    }

    private func updateLabels() {
        let searchLabel = localized("Search settings")
        searchField.placeholderString = searchLabel
        updateSearchWidth()
        searchField.setAccessibilityLabel(searchLabel)
        searchItem.label = searchLabel
        searchItem.paletteLabel = searchLabel

        let label =
            appearance.navigation == .top ? localized("Use sidebar navigation") : localized("Use top navigation")
        let symbol = appearance.navigation == .top ? "sidebar.left" : "rectangle.topthird.inset.filled"
        navigationItem.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        navigationItem.label = label
        navigationItem.toolTip = label
    }

    private func updateSearchWidth() {
        guard let cell = searchField.cell as? NSSearchFieldCell, let font = searchField.font else { return }
        let bounds = NSRect(x: 0, y: 0, width: 260, height: max(cell.cellSize.height, 28))
        let chrome = bounds.width - cell.searchTextRect(forBounds: bounds).width
        let prompt = (searchField.placeholderString ?? "") as NSString
        let width = max(bounds.width, ceil(prompt.size(withAttributes: [.font: font]).width + chrome + 4))
        searchItem.preferredWidthForSearchField = width
        searchWidth?.constant = width
    }

    private func updateSearchField() {
        let editor = searchField.currentEditor() as? NSTextView
        guard (editor?.string ?? searchField.stringValue) != search.query, editor?.hasMarkedText() != true else {
            return
        }
        searchField.stringValue = search.query
    }

    func control(_ control: NSControl, textShouldBeginEditing fieldEditor: NSText) -> Bool {
        canFocus()
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        if !search.isPresented { search.focus() }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        dismissResults()
    }

    func controlTextDidChange(_ notification: Notification) {
        searchFieldAction()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard canFocus(), !textView.hasMarkedText() else { return false }
        switch selector {
        case #selector(NSResponder.moveDown(_:)) where !search.results.isEmpty:
            search.move(1)
        case #selector(NSResponder.moveUp(_:)) where !search.results.isEmpty:
            search.move(-1)
        case #selector(NSResponder.insertNewline(_:)) where search.isPresented && !search.results.isEmpty:
            search.activateSelection()
        case #selector(NSResponder.cancelOperation(_:)):
            dismissResults()
            endSearchInteraction()
        default:
            return false
        }
        return true
    }

    @objc private func searchFieldAction() {
        let editor = searchField.currentEditor() as? NSTextView
        guard !endingSearchInteraction, editor?.hasMarkedText() != true else { return }
        search.query = editor?.string ?? searchField.stringValue
    }

    private func endSearchInteraction() {
        endingSearchInteraction = true
        searchItem.endSearchInteraction()
        endingSearchInteraction = false
        updateSearchField()
    }

    @objc private func toggleNavigation() {
        guard window?.attachedSheet == nil, canFocus() else { return }
        appearance.navigation = appearance.navigation == .top ? .sidebar : .top
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let window else { return event }
        if event.type == .keyDown {
            guard event.window === window, window.attachedSheet == nil, canFocus() else { return event }
            if SettingsTextSizeShortcut.handle(event, in: window, appearance: appearance) { return nil }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            switch (modifiers, event.charactersIgnoringModifiers?.lowercased()) {
            case (.command, "f"):
                search.focus()
                return nil
            case ([.control, .command], "s"):
                toggleNavigation()
                return nil
            default:
                break
            }
        } else if search.isPresented, event.window !== resultsPanel {
            let inSearchField =
                event.window === window
                && searchField.bounds.contains(searchField.convert(event.locationInWindow, from: nil))
            if !inSearchField { dismissResults() }
        }
        return event
    }

    private func dismissResults() {
        search.dismiss()
        hideResultsPanel()
    }

    private func hideResultsPanel() {
        guard let panel = resultsPanel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    private func updateResultsPanel() {
        guard search.isPresented, let window, window.isVisible, window.attachedSheet == nil,
            searchField.window === window
        else {
            hideResultsPanel()
            return
        }
        let panel = resultsPanel ?? makeResultsPanel()
        let field = window.convertToScreen(searchField.convert(searchField.bounds, to: nil))
        let screen = (window.screen?.visibleFrame ?? window.frame).insetBy(dx: 8, dy: 8)
        let width = min(appearance.interfaceTypography.room(360), screen.width, window.frame.width)
        let height = min(
            appearance.interfaceTypography.room(MacOS26SettingsSearchResults.height(for: search.results.count)),
            screen.height)
        let leadingX = searchField.userInterfaceLayoutDirection == .rightToLeft ? field.maxX - width : field.minX
        let x = min(max(leadingX, screen.minX), screen.maxX - width)
        let y = min(max(field.minY - height - 6, screen.minY), screen.maxY - height)
        panel.appearance = window.effectiveAppearance
        panel.level = NSWindow.Level(rawValue: window.level.rawValue + 1)
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        if panel.parent == nil { window.addChildWindow(panel, ordered: .above) }
        if !panel.isVisible { panel.orderFront(nil) }
    }

    private func makeResultsPanel() -> NSPanel {
        let panel = MacOS26SettingsSearchPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        let glass = NSGlassEffectView()
        glass.cornerRadius = MacOS26SettingsSurface.searchPanelRadius
        let host = MacOS26SettingsResultsHost(
            rootView: MacOS26SettingsSearchResults(search: search, appearance: appearance))
        host.sizingOptions = []
        glass.contentView = host
        panel.contentView = glass
        resultsPanel = panel
        return panel
    }
}

@available(macOS 26, *)
private final class MacOS26SettingsSearchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@available(macOS 26, *)
private final class MacOS26SettingsResultsHost: NSHostingView<MacOS26SettingsSearchResults> {
    override var allowsVibrancy: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@available(macOS 26, *)
private struct MacOS26SettingsSearchResults: View {
    private var typography: InterfaceTypography { appearance.interfaceTypography }

    static let rowHeight: CGFloat = 80
    static let padding: CGFloat = 6
    @ObservedObject var search: SettingsSearchModel
    @ObservedObject var appearance: AppearanceSettingsStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var labelColor: Color {
        Color(nsColor: scheme == .dark ? .white : .black)
    }

    private var secondaryLabelColor: Color {
        let lightness = scheme == .dark ? 0.76 : 0.32
        return contrast == .increased ? labelColor : Color(white: lightness)
    }

    static func height(for count: Int) -> CGFloat {
        count == 0 ? 64 : CGFloat(min(6, count)) * rowHeight
    }

    var body: some View {
        if search.results.isEmpty {
            Text(localized("No matching settings"))
                .font(typography.font(.callout))
                .foregroundStyle(secondaryLabelColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        IndexedForEach(search.results) { index, entry in
                            result(entry, selected: search.selectedIndex == index)
                                .onHover { if $0 { search.hover(at: index) } }
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, Self.padding)
                }
                .onChange(of: search.keyboardSelectionRevision) {
                    if search.results.indices.contains(search.selectedIndex) {
                        proxy.scrollTo(search.results[search.selectedIndex].id)
                    }
                }
            }
        }
    }

    private func result(_ entry: SettingsSearchEntry, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.symbol)
                .font(typography.font(.callout).weight(.medium))
                .foregroundStyle(secondaryLabelColor)
                .frame(width: typography.room(22))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                highlighted(entry.title.localized)
                    .font(typography.font(.callout))
                    .foregroundStyle(labelColor)
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.path)
                    .font(typography.font(.caption))
                    .foregroundStyle(secondaryLabelColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: typography.room(Self.rowHeight) - 2 * Self.padding)
        .background(
            selected ? appearance.accent.opacity(0.18) : .clear,
            in: MacOS26SettingsSurface.rounded(minimum: 18)
        )
        .contentShape(.rect)
        .padding(.vertical, Self.padding)
        .beButton { search.activate(entry.id) }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func highlighted(_ value: String) -> Text {
        var text = AttributedString(value)
        var highlight = AttributeContainer()
        highlight.inlinePresentationIntent = .stronglyEmphasized
        text.mergeAttributes(highlight, in: SettingsSearchIndex.matchingRanges(in: value, query: search.query))
        return Text(text)
    }
}

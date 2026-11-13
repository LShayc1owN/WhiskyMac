// WhiskyMac: modified or added 2026-11-07 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Combine
import SwiftUI

/// AppKit owns title-bar geometry; both the field and results are SwiftUI.
final class SettingsSearchToolbar: NSObject, NSToolbarDelegate {
    static let itemID = NSToolbarItem.Identifier("WhiskyMac.settingsSearch")
    static let navigationID = NSToolbarItem.Identifier("WhiskyMac.settingsNavigation")
    static let brandID = NSToolbarItem.Identifier("WhiskyMac.settingsBrand")
    private weak var window: NSWindow?
    private let search: SettingsSearchModel
    private let appearance: AppearanceSettingsStore
    let fieldHost: NSHostingView<SettingsSearchField>
    private let canFocus: () -> Bool
    private var observation: AnyCancellable?
    private var events: Any?
    private var notifications: [NSObjectProtocol] = []
    private(set) var resultsPanel: NSPanel?

    init(
        window: NSWindow, search: SettingsSearchModel,
        appearance: AppearanceSettingsStore = AppearanceSettingsStore(),
        canFocus: @escaping () -> Bool = { true }
    ) {
        self.window = window
        self.search = search
        self.appearance = appearance
        self.canFocus = canFocus
        fieldHost = NSHostingView(rootView: SettingsSearchField(search: search))
        super.init()
        fieldHost.frame.size = NSSize(width: 260, height: 28)
        let toolbar = NSToolbar(identifier: "WhiskyMac.settingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        window.toolbar = toolbar
        observation = search.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.updateResultsPanel()
        }
        events = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) {
            [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            notifications.append(
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.updateResultsPanel()
                })
        }
        notifications.append(
            NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: .main
            ) { [weak self] _ in self?.search.dismiss() })
        notifications.append(
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                self?.search.reset(); self?.hideResults()
            })
    }

    deinit {
        if let events { NSEvent.removeMonitor(events) }
        notifications.forEach(NotificationCenter.default.removeObserver)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.navigationID, Self.itemID, .flexibleSpace, Self.brandID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        switch itemIdentifier {
        case Self.itemID:
            item.label = localized("Search settings")
            item.view = fieldHost
        case Self.navigationID:
            item.label = localized("Settings layout")
            let host = NSHostingView(rootView: SettingsNavigationControl(appearance: appearance))
            host.frame.size = NSSize(width: 40, height: 28)
            item.view = host
        case Self.brandID:
            item.label = AppIdentity.displayName
            let host = NSHostingView(rootView: SettingsToolbarBrand(appearance: appearance))
            host.frame.size = host.fittingSize
            item.view = host
        default: return nil
        }
        return item
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let window else { return event }
        if event.type == .keyDown {
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if event.window === window, window.attachedSheet == nil, canFocus(),
                modifiers == [.control, .command], event.charactersIgnoringModifiers?.lowercased() == "s"
            {
                appearance.navigation = appearance.navigation == .top ? .sidebar : .top
                return nil
            }
            if event.window === window, window.attachedSheet == nil, canFocus(),
                modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "f"
            {
                search.focus()
                return nil
            }
        } else if search.isPresented, event.window !== resultsPanel {
            let point = fieldHost.convert(event.locationInWindow, from: nil)
            if event.window !== window || !fieldHost.bounds.contains(point) { search.dismiss() }
        }
        return event
    }

    private func hideResults() {
        guard let panel = resultsPanel else { return }
        window?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    private func updateResultsPanel() {
        window?.toolbar?.items.first { $0.itemIdentifier == Self.itemID }?.label = localized("Search settings")
        guard search.isPresented, let window, window.isVisible, window.attachedSheet == nil else {
            hideResults()
            return
        }
        let panel: NSPanel
        if let existing = resultsPanel {
            panel = existing
        } else {
            panel = SettingsSearchResultsPanel(
                contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = true
            panel.contentView = NSHostingView(rootView: SettingsSearchResults(search: search, appearance: appearance))
            resultsPanel = panel
        }
        let field = window.convertToScreen(fieldHost.convert(fieldHost.bounds, to: nil))
        let screen = window.screen?.visibleFrame ?? window.frame
        let height =
            search.results.isEmpty ? 64 : CGFloat(min(6, search.results.count)) * SettingsSearchResults.rowHeight
        let width: CGFloat = 360
        let x = min(max(field.minX, screen.minX + 8), screen.maxX - width - 8)
        let y = max(screen.minY + 8, field.minY - height - 6)
        panel.appearance = window.effectiveAppearance
        panel.level = NSWindow.Level(rawValue: window.level.rawValue + 1)
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        if panel.parent == nil { window.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
    }
}

private final class SettingsSearchResultsPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct SettingsSearchField: View {
    @ObservedObject var search: SettingsSearchModel
    @FocusState private var focused: Bool

    private var hasMarkedText: Bool {
        (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() == true
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(localized("Search settings"), text: $search.query)
                .textFieldStyle(.plain)
                .focused($focused)
                .accessibilityIdentifier("settingsSearchField")
                .onSubmit { search.activateSelection() }
                .onKeyPress(.downArrow) {
                    guard !hasMarkedText else { return .ignored }
                    search.move(1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    guard !hasMarkedText else { return .ignored }
                    search.move(-1)
                    return .handled
                }
                .onExitCommand {
                    search.dismiss(); focused = false
                }
            if !search.query.isEmpty {
                Button {
                    search.query = ""; focused = true
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localized("Clear the search"))
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .frame(width: 260, height: 28)
        .background(.quaternary.opacity(0.5), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
        .onChange(of: search.focusRevision) { _, _ in focused = true }
        .onChange(of: search.navigationRevision) { _, _ in focused = false }
        .onChange(of: focused) { _, value in
            if value { search.focus() } else { search.dismiss() }
        }
    }
}

struct SettingsSearchResults: View {
    static let rowHeight: CGFloat = 80
    @ObservedObject var search: SettingsSearchModel
    @ObservedObject var appearance: AppearanceSettingsStore

    var body: some View {
        Group {
            if search.results.isEmpty {
                Text(localized("No matching settings"))
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(search.results.enumerated()), id: \.element.id) { index, entry in
                                Button {
                                    search.activate(entry.id)
                                } label: {
                                    HStack(alignment: .center, spacing: 10) {
                                        Image(systemName: entry.symbol)
                                            .font(.system(size: 17))
                                            .foregroundStyle(appearance.accent)
                                            .frame(width: 22)
                                            .accessibilityHidden(true)
                                        VStack(alignment: .leading, spacing: 3) {
                                            highlightedText(entry.title.localized, secondary: false)
                                                .font(.system(size: 13, weight: .medium))
                                                .lineLimit(2)
                                                .fixedSize(horizontal: false, vertical: true)
                                            highlightedText(entry.path, secondary: true)
                                                .font(.system(size: 11)).lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .frame(height: Self.rowHeight - 32)
                                    .padding(10)
                                    .contentShape(Rectangle())
                                    .background(
                                        appearance.accent.opacity(search.selectedIndex == index ? 0.15 : 0),
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                                    .padding(6)
                                }
                                .buttonStyle(.plain)
                                .onContinuousHover { phase in
                                    if case .active = phase { search.hover(at: index) }
                                }
                                .accessibilityAddTraits(search.selectedIndex == index ? .isSelected : [])
                                .id(entry.id)
                            }
                        }
                    }
                    .onChange(of: search.keyboardSelectionRevision) { _, _ in
                        let index = search.selectedIndex
                        if search.results.indices.contains(index) { proxy.scrollTo(search.results[index].id) }
                    }
                }
            }
        }
        .settingsSurface(in: RoundedRectangle(cornerRadius: 10))
    }

    private func highlightedText(_ value: String, secondary: Bool) -> Text {
        var text = AttributedString(value)
        text.foregroundColor = secondary ? .secondary : .primary
        for range in SettingsSearchIndex.matchingRanges(in: value, query: search.query) {
            if let start = AttributedString.Index(range.lowerBound, within: text),
                let end = AttributedString.Index(range.upperBound, within: text)
            {
                text[start..<end].foregroundColor = appearance.accent
            }
        }
        return Text(text)
    }

}

// WhiskyMac: modified or added 2026-11-17 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI
import Testing

@testable import Whisk

@Suite struct CardRailLayoutTests {
    private func cards(_ count: Int) -> [CardViewState] {
        HistoryPresenter().present(
            items: (0..<count).map { anItem(.text("Rail item \($0)")) }, query: "", now: Date()
        ).cards
    }

    @Test func large_histories_have_bounded_slots_and_exact_document_extent() {
        for count in [1, 5, 200, 1000, 10_000] {
            let cards = cards(count)
            for leading in [0, 50, count - 1, count + 100] {
                for selected in [nil, 0, count - 1, count + 1] {
                    let entries = CardRailLayout.entries(
                        cards: cards, window: CardRailWindow(leading: leading, capacity: 7), selectedIndex: selected)
                    let actual = entries.compactMap { entry -> Int? in
                        if case .card(let index, _) = entry { return index }
                        return nil
                    }
                    #expect(actual.count <= 13)
                    #expect(entries.count <= 16)
                    #expect(Set(entries.map(\.id)).count == entries.count)
                    if let selected, cards.indices.contains(selected) { #expect(actual.contains(selected)) }
                    for side: CGFloat in [178.5, 210, 283.5] {
                        let width =
                            entries.reduce(CGFloat.zero) { $0 + $1.width(side: side, gap: 14) }
                            + CGFloat(entries.count - 1) * 14
                        #expect(abs(width - (CGFloat(count) * (side + 14) - 14)) < 0.001)
                    }
                }
            }
        }
        #expect(CardRailLayout.entries(cards: [], window: CardRailWindow(), selectedIndex: nil).isEmpty)
    }

    @Test func adjacent_windows_keep_common_card_identity_and_cover_every_position_once() {
        let cards = cards(200)
        let first = CardRailLayout.entries(
            cards: cards, window: CardRailWindow(leading: 50, capacity: 7), selectedIndex: 3)
        let next = CardRailLayout.entries(
            cards: cards, window: CardRailWindow(leading: 51, capacity: 7), selectedIndex: 3)
        let common = Set(first.map(\.id)).intersection(next.map(\.id))
        for index in 49...59 { #expect(common.contains(.card(cards[index].id))) }
        for entries in [first, next] {
            let indices = entries.flatMap { entry -> [Int] in
                switch entry {
                case .card(let index, _): [index]
                case .gap(let range): Array(range)
                }
            }
            #expect(indices == Array(cards.indices))
        }
    }
    @Test(arguments: [false, true])
    func keyboard_reveal_keeps_visible_cards_still_and_preserves_both_margins(rtl: Bool) {
        let geometry = ScrollGeometry(
            contentOffset: CGPoint(x: rtl ? 2256 : 2224, y: 0), contentSize: CGSize(width: 44786, height: 226),
            contentInsets: EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16),
            containerSize: CGSize(width: 1480, height: 226))
        let viewport = CardRailViewport(geometry, count: 200, side: 210, stride: 224, rtl: rtl)
        #expect(viewport.revealOffset(index: 10, side: 210, stride: 224) == nil)
        #expect(viewport.revealOffset(index: 15, side: 210, stride: 224) == nil)
        #expect(viewport.revealOffset(index: 3, side: 210, stride: 224) == 672)
        #expect(viewport.revealOffset(index: 150, side: 210, stride: 224) == 32330)
    }
}

@MainActor
@Suite(.serialized) struct NativeCardRailTests {
    @Test(arguments: [false, true])
    func native_scroll_reveals_distant_selection_and_returns_to_the_first_card(rtl: Bool) throws {
        _ = NSApplication.shared
        let store = HistoryViewStateStore()
        store.configureCards(side: 200)
        let items = (0..<200).map { anItem(.text("Rail item \($0)"), from: "App \($0)", bundle: "synthetic.app-\($0)") }
        let appScope = FilterAppScope(visibleSourceKeys: [])
        let presenter = HistoryPresenter()
        store.update(presenter.present(items: items, query: "", now: Date(), selectedID: items[0].id))
        store.setPanelVisible(true)
        var actions = PanelActionSpy().actions
        var editorEvents: [Bool] = []
        actions.metadataEditorChanged = { editorEvents.append($0) }
        func root(_ revision: Int) -> AnyView {
            AnyView(
                MacOS15HistoryCardRail(
                    store: store, actions: actions, keyBindings: nil, returnToLatestRevision: revision,
                    appScope: appScope
                )
                .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight))
        }
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: 0, width: 1512, height: 270),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: root(0))
        host.sizingOptions = []
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        func settle() {
            for _ in 0..<12 {
                autoreleasepool {
                    host.layoutSubtreeIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.025))
                }
            }
        }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        settle()
        let scroll = try #require(descendants(host).compactMap { $0 as? NSScrollView }.first)
        let document = try #require(scroll.documentView)
        let initialOffset = scroll.contentView.bounds.minX
        let initialExtent = document.frame.width
        func checkVisibleSources() {
            let visible = scroll.documentVisibleRect
            let expected = Set(
                store.state.cards.indices.filter { index in
                    let x =
                        rtl
                        ? document.frame.width - CGFloat(index) * store.cardStride - store.zoomedCardSide
                        : CGFloat(index) * store.cardStride
                    return x < visible.maxX && x + store.zoomedCardSide > visible.minX
                }.compactMap { store.state.cards[$0].sourceKey })
            #expect(appScope.visibleSourceKeys == expected, "rtl=\(rtl), visible=\(visible)")
        }
        checkVisibleSources()
        #expect(abs(initialExtent - (CGFloat(items.count) * store.cardStride - HistoryViewStateStore.cardGap)) < 0.5)
        func visibleGlass() -> Int {
            descendants(scroll).compactMap { $0 as? MacOS15BackdropView }.filter {
                $0.convert($0.bounds, to: document).intersects(scroll.documentVisibleRect)
            }.count
        }
        #expect(visibleGlass() >= 6)
        for index in [50, 100, 20] {
            scroll.contentView.scroll(to: NSPoint(x: CGFloat(index) * store.cardStride, y: 0))
            scroll.reflectScrolledClipView(scroll.contentView)
            settle()
            #expect(visibleGlass() >= 6)
            checkVisibleSources()
            #expect(abs(document.frame.width - initialExtent) < 0.5)
        }
        let previousGlass = Set(descendants(scroll).filter { $0 is MacOS15BackdropView }.map(ObjectIdentifier.init))
        scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.minX + store.cardStride, y: 0))
        scroll.reflectScrolledClipView(scroll.contentView)
        settle()
        let currentGlass = Set(descendants(scroll).filter { $0 is MacOS15BackdropView }.map(ObjectIdentifier.init))
        #expect(editorEvents.isEmpty, "Unmounting ordinary cards must not dismiss another card's editor")
        #expect(previousGlass.intersection(currentGlass).count >= 10)
        for index in [150, 3, 180] {
            store.update(presenter.present(items: items, query: "", now: Date(), selectedID: items[index].id))
            settle()
            let glass = descendants(scroll).compactMap { $0 as? MacOS15BackdropView }
            let selected = glass.filter { abs($0.bounds.width - store.zoomedCardSide) < 0.5 }
            #expect(selected.count == 1)
            #expect(
                selected.contains {
                    scroll.documentVisibleRect.insetBy(dx: -0.5, dy: -0.5).contains($0.convert($0.bounds, to: document))
                })
            #expect(visibleGlass() >= 6)
            #expect(glass.count <= 13)
            #expect(abs(document.frame.width - initialExtent) < 0.5)
            print(
                "Rail rtl=\(rtl), selected=\(index), offset=\(scroll.contentView.bounds.minX), visible glass=\(visibleGlass())"
            )
        }
        host.rootView = root(1)
        settle()
        #expect(abs(scroll.contentView.bounds.minX - initialOffset) < 0.5)
        #expect(visibleGlass() >= 6)

        for index in [199, 10, 95, 180] {
            store.update(presenter.present(items: items, query: "", now: Date(), selectedID: items[index].id))
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.025))
        }
        settle()
        let selected = try #require(
            descendants(scroll).first { abs($0.bounds.width - store.zoomedCardSide) < 0.5 && $0 is MacOS15BackdropView }
        )
        #expect(
            scroll.documentVisibleRect.insetBy(dx: -0.5, dy: -0.5).contains(
                selected.convert(selected.bounds, to: document)))
        store.panelDidClose()
        settle()
        #expect(abs(scroll.contentView.bounds.minX - initialOffset) < 0.5)
        store.setPanelVisible(true)

        // A smaller result set must clamp an old scroll window, and a
        // wider viewport must fill immediately after its geometry updates.
        store.update(
            presenter.present(items: Array(items.prefix(3)), query: "Rail", now: Date(), selectedID: items[0].id))
        window.setContentSize(NSSize(width: 1800, height: 270))
        settle()
        #expect(descendants(scroll).filter { $0 is MacOS15BackdropView }.count == 3)
        #expect(visibleGlass() == 3)
    }

    @Test(arguments: [200.0, 1000.0])
    func panel_prepares_the_viewport_before_hosting_without_intrinsic_measurement(side: Double) throws {
        _ = NSApplication.shared
        let sandbox = try IsolatedDefaults()
        let store = HistoryViewStateStore()
        store.configureCards(side: side)
        let spy = PanelActionSpy()
        let controller = PanelController(
            uiFactory: MacOS15UIFactory(), stateStore: store, actions: spy.actions,
            keyBindings: KeyBindingsStore(defaults: sandbox.defaults),
            vimBindings: VimBindingsStore(defaults: sandbox.defaults), vimMode: { false })
        let screen = try #require(NSScreen.main)
        controller.preparePresentation(pins: false, style: nil, on: screen)
        let content = try #require(controller.activeWindow.contentView)
        let host = try #require(content as? TestHostingSurface)
        let expected = MacOS15PanelLayout(screen: MacOS15PanelLayout.Screen(screen), cardSide: store.cardSide).panel
        #expect(controller.activeWindow.frame == expected)
        #expect(content.frame.size == expected.size)
        #expect(host.sizingOptions.isEmpty)
        #expect(!controller.activeWindow.isVisible)
    }

    @Test(arguments: [false, true])
    func oversized_cards_scroll_vertically_inside_a_short_panel(protected: Bool) async throws {
        _ = NSApplication.shared
        let store = HistoryViewStateStore()
        store.configureCards(side: 1000)
        store.update(HistoryPresenter().present(items: [anItem(.text("Large card"))], query: "", now: Date()))
        store.setPrivacy(protected)
        let host = HistoryPanelHosting.make(
            uiFactory: MacOS15UIFactory(), store: store, actions: PanelActionSpy().actions)
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: 0, width: 1200, height: 700),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(350))
        host.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let scroll = try #require(
            descendants(host).compactMap { $0 as? NSScrollView }.first { ($0.documentView?.frame.height ?? 0) >= 1000 })
        let document = try #require(scroll.documentView)
        #expect(scroll.contentView.bounds.height < document.frame.height)
        #expect(host.bounds.contains(scroll.convert(scroll.bounds, to: host)))
        let frame = scroll.convert(scroll.bounds, to: host)
        scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.minX, y: 200))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await Task.sleep(for: .milliseconds(100))
        #expect(scroll.contentView.bounds.minY >= 200)
        #expect(scroll.convert(scroll.bounds, to: host) == frame)
    }
}

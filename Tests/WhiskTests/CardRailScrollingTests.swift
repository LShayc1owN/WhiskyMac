// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI
import Testing

@testable import Whisk

@MainActor
@Suite(.serialized) struct CardRailScrollingTests {
    private func makeWindow(host: NSView, height: CGFloat) -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(x: -10000, y: 0, width: 1200, height: height),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        return window
    }

    private func cardScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView,
            scroll.contentView.documentRect.width > scroll.contentView.bounds.width + 1
        {
            return scroll
        }
        return view.subviews.lazy.compactMap(cardScrollView).first
    }

    private func settle(_ host: NSView, for seconds: Double) {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        host.layoutSubtreeIfNeeded()
    }

    @Test func protected_return_button_reaches_latest_without_reading_clipboard_contents() throws {
        _ = NSApplication.shared
        let store = HistoryViewStateStore()
        var reads = 0
        store.detailSource = { _ in
            reads += 1
            return nil
        }
        store.setPrivacy(true)
        store.setPanelVisible(true)
        let items = (0..<1000).map { anItem(.text("Protected card \($0)")) }
        store.update(HistoryPresenter().present(items: items, query: "", now: Date()))
        let host = NSHostingView(rootView: MacOS15PrivacySpotlightView(store: store))
        host.sizingOptions = []
        let window = makeWindow(host: host, height: 430)
        defer { window.contentView = nil; window.close() }
        window.orderFront(nil)
        settle(host, for: 0.15)
        let scroll = try #require(cardScrollView(in: host))
        let start = scroll.contentView.bounds.minX
        scroll.contentView.scroll(to: CGPoint(x: start + 800 * (store.cardSide + HistoryViewStateStore.cardGap), y: 0))
        scroll.reflectScrolledClipView(scroll.contentView)
        settle(host, for: 0.15)
        #expect(scroll.contentView.bounds.minX > start + 100_000)

        // With optional search and filters hidden, the icon-only return button is the
        // square native surface in the toolbar. Deliver the click only to this test window.
        func returnSurface(in view: NSView) -> NSView? {
            if let surface = view as? MacOS15BackdropView, surface.material == .underWindowBackground,
                surface.bounds.width == surface.bounds.height
            {
                return surface
            }
            return view.subviews.lazy.compactMap(returnSurface).first
        }
        let button = try #require(returnSurface(in: host))
        let point = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(
                NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
        settle(host, for: 0.55)
        #expect(abs(scroll.contentView.bounds.minX - start) < 1)
        #expect(reads == 0 && store.state.cards.isEmpty)
    }

    private func viewport(x: Int) -> CardRailViewport {
        let geometry = ScrollGeometry(
            contentOffset: CGPoint(x: x, y: 0), contentSize: CGSize(width: 224000, height: 220),
            contentInsets: EdgeInsets(), containerSize: CGSize(width: 1200, height: 220))
        return CardRailViewport(geometry, count: 1000, side: 210, stride: 224, rtl: false)
    }

    @Test func pixel_scrolling_publishes_only_layout_and_navigation_boundaries() {
        var previous = viewport(x: 0)
        var changes = 0
        var mounts = 0
        for x in 1...2240 {
            let current = viewport(x: x)
            if previous != current { changes += 1 }
            if previous.window != current.window { mounts += 1 }
            #expect(current.visible.allSatisfy { current.window.contains($0, selectedIndex: nil) })
            previous = current
        }
        #expect(changes < 60 && mounts == 5)
        print("Rail geometry over 2240 points: \(changes) changes, \(mounts) mount-window updates")
    }

    @Test func a_new_gesture_supersedes_a_return_and_reduce_motion_goes_straight_to_latest() {
        let scrolling = CardRailScrollState()
        var position = ScrollPosition()
        var writes = 0
        let binding = Binding(
            get: { position },
            set: {
                position = $0; writes += 1
            })
        scrolling.update(viewport(x: 100000), position: binding, reduceMotion: false)
        scrolling.returnToLatest(position: binding, reduceMotion: false)
        #expect(position.edge == nil && writes == 1)
        scrolling.cancelReturn()
        scrolling.update(viewport(x: 780), position: binding, reduceMotion: false)
        #expect(position.edge == nil && writes == 1)
        scrolling.returnToLatest(position: binding, reduceMotion: false)
        #expect(position.edge == .leading)
        scrolling.update(viewport(x: 100000), position: binding, reduceMotion: true)
        scrolling.returnToLatest(position: binding, reduceMotion: true)
        #expect(position.edge == .leading && writes == 3)
    }

    @Test(arguments: [false, true])
    func manual_scroll_and_long_return_share_the_native_viewport(rtl: Bool) throws {
        _ = NSApplication.shared
        let store = HistoryViewStateStore()
        store.configureCards(side: 200)
        let items = (0..<1000).map { anItem(.text("Card \($0)"), from: "Source \($0)", bundle: "source.\($0)") }
        store.update(HistoryPresenter().present(items: items, query: "", now: Date()))
        store.setPanelVisible(true)
        let scope = FilterAppScope(visibleSourceKeys: [])
        let spy = PanelActionSpy()
        func rail(_ revision: Int) -> some View {
            MacOS15HistoryCardRail(
                store: store, actions: spy.actions, keyBindings: nil,
                returnToLatestRevision: revision, appScope: scope
            )
            .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
        }
        let host = NSHostingView(rootView: rail(0))
        host.sizingOptions = []
        let window = makeWindow(host: host, height: 280)
        defer { window.contentView = nil; window.close() }
        settle(host, for: 0.2)
        let scroll = try #require(cardScrollView(in: host))
        let latest = scope.visibleSourceKeys
        let start = scroll.contentView.bounds.minX
        let direction: CGFloat = rtl ? -1 : 1
        func move(_ distance: CGFloat) {
            scroll.contentView.scroll(to: NSPoint(x: start + direction * distance, y: 0))
            scroll.reflectScrolledClipView(scroll.contentView)
            host.layoutSubtreeIfNeeded()
            CATransaction.flush()
        }
        var steps: [Double] = []
        for i in 1...120 {
            let begin = DispatchTime.now().uptimeNanoseconds
            autoreleasepool { move(CGFloat(i) * 9) }
            steps.append(Double(DispatchTime.now().uptimeNanoseconds - begin) / 1e6)
        }
        #expect(abs(scroll.contentView.bounds.minX - start) >= 1079)
        move(800 * store.cardStride)
        settle(host, for: 0.2)
        let distant = scope.visibleSourceKeys ?? []
        var duringReturn = Set<String>()
        let observation = scope.objectWillChange.sink { duringReturn.formUnion(scope.visibleSourceKeys ?? []) }
        host.rootView = rail(1)
        settle(host, for: 0.55)
        withExtendedLifetime(observation) {
            #expect(abs(scroll.contentView.bounds.minX - start) < 1)
            duringReturn.formUnion(scope.visibleSourceKeys ?? [])
            #expect(!distant.isEmpty && latest != distant && scope.visibleSourceKeys == latest)
            #expect(duringReturn.count <= 20)
        }
        steps.sort()
        print(
            "Rail scrolling rtl=\(rtl) stepMedianMs=\(steps[60]) stepP90Ms=\(steps[107]) sourcesDuringReturn=\(duringReturn.count)"
        )
    }
}

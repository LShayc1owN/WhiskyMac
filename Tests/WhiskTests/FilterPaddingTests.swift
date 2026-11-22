// WhiskyMac: modified or added 2026-11-20 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI
import Testing

@testable import Whisk

@MainActor
@Suite(.serialized) struct FilterPaddingTests {
    @Test(arguments: [false, true])
    func scaled_tags_keep_the_resting_card_alignment_during_selection(animationsEnabled: Bool) async throws {
        _ = NSApplication.shared
        let store = HistoryViewStateStore()
        store.configureCards(side: 300)
        store.setPanelVisible(true)
        let item = anItem(.text("Synthetic card"))
        let items = [item] + (0..<4).map { anItem(.text("Synthetic card \($0)")) }
        let all = FilterChip(
            id: allFiltersChipID, label: "All", sourceBundleID: nil, icon: .symbol("square.grid.2x2"),
            accessibilityLabel: "All", isActive: true, isFocused: false)
        let host = NSHostingView(
            rootView: HistoryPanelView(store: store, actions: PanelActionSpy().actions)
                .transaction { if !animationsEnabled { $0.disablesAnimations = true } })
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: 0, width: 900, height: 550),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.contentView = nil; window.close() }
        var tagPositions: [Double: CGFloat] = [:]
        for selected in [false, true, false] {
            store.update(
                HistoryPresenter().present(
                    items: items, query: "", now: Date(), selectedID: selected ? item.id : nil,
                    filters: FilterContext(chips: [.all])))
            #expect(store.state.filters.all.first?.id == all.id)
            for scale in [0.75, 1, 2, 1] {
                store.configureFilterTags(scale: scale)
                window.setContentSize(
                    NSSize(width: 900, height: PanelLayout.panelHeight(forCardSide: 300, tagScale: scale)))
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(350))
                host.layoutSubtreeIfNeeded()
                let surfaces = descendants(host).compactMap { $0 as? BackdropView }
                let card = try #require(
                    surfaces.first { $0.bounds.height >= 300 && $0.bounds.width == $0.bounds.height })
                let firstTag = try #require(
                    surfaces.filter { $0.bounds.height < 120 }.min {
                        $0.convert($0.bounds, to: host).minX < $1.convert($1.bounds, to: host).minX
                    })
                let cardFrame = card.convert(card.bounds, to: host)
                let tagFrame = firstTag.convert(firstTag.bounds, to: host)
                let restingCardEdge = PanelLayout.contentMargin + (store.zoomedCardSide - store.cardSide) / 2
                #expect(
                    abs(restingCardEdge - tagFrame.minX) < 1,
                    "selected=\(selected), scale=\(scale): \(cardFrame), \(tagFrame)")
                if let previous = tagPositions[scale] {
                    #expect(abs(previous - tagFrame.minX) < 0.5, "Card selection must not move the filter row")
                }
                tagPositions[scale] = tagFrame.minX
                let tagScroll = try #require(
                    descendants(host).compactMap { $0 as? NSScrollView }.first {
                        $0.bounds.height < 120
                    })
                #expect(tagScroll.bounds.height <= FilterTagMetrics(scale: scale).totalRowHeight + 1)
                let rowFrame = tagScroll.convert(tagScroll.bounds, to: host)
                #expect(abs(rowFrame.midY - tagFrame.midY) < 1)
                let bottomMargin = host.isFlipped ? host.bounds.maxY - cardFrame.maxY : cardFrame.minY
                let tagGap = host.isFlipped ? cardFrame.minY - tagFrame.maxY : tagFrame.minY - cardFrame.maxY
                #expect(abs(bottomMargin - cardFrame.minX) < 1, "Equal screen margins: \(bottomMargin), \(cardFrame)")
                #expect(tagGap > 0 && tagGap < 30, "Tag-to-card gap must stay compact: \(tagGap)")
                if let output = ProcessInfo.processInfo.environment["WHISK_UI_ARTIFACTS"] {
                    let directory = URL(fileURLWithPath: output)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])?.write(
                        to: directory.appendingPathComponent("padding-\(selected)-\(Int(scale * 100)).png"))
                }
            }
        }
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
}

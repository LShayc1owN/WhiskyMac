// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI
import Testing

@testable import Whisk

@MainActor
@Suite struct RichTextCards {
    private func formatted() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        paragraph.paragraphSpacing = 8
        return NSAttributedString(
            string: "Rich card",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 18), .foregroundColor: NSColor.red,
                .obliqueness: 0.2, .link: URL(string: "https://example.invalid")!, .paragraphStyle: paragraph,
            ])
    }

    @Test func cards_carry_opaque_rtf_while_plain_cards_and_protected_state_do_not() throws {
        let data = try #require(RichTextCodec.encode(formatted()))
        let item = ClipboardItem(
            id: UUID(), payload: .text("Rich card"), source: nil, copiedAt: Date(), isPinned: false, rtf: data)
        let state = HistoryPresenter().present(items: [item, anItem(.text("plain"))], query: "", now: Date())
        #expect(state.cards[0].rtf == data)
        #expect(state.cards[1].rtf == nil)
        let store = HistoryViewStateStore()
        store.update(state)
        store.setPrivacy(true)
        #expect(store.state == .empty)
        #expect(store.state.cards.isEmpty)
        let view = ItemCardView(card: state.cards[0], actions: PanelActionSpy().actions)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 240, height: 240)
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.width > 0)
    }

    @Test func bounded_excerpt_preserves_rich_attributes_and_falls_back_for_invalid_or_large_data() throws {
        let data = try #require(RichTextCodec.encode(formatted()))
        let text = RichTextCardContent.decode(data, fallback: "Rich card")
        #expect(text.string == "Rich card")
        let attributes = text.attributes(at: 0, effectiveRange: nil)
        #expect((attributes[.font] as? NSFont)?.pointSize == 18)
        #expect(NSFontManager.shared.traits(of: try #require(attributes[.font] as? NSFont)).contains(.boldFontMask))
        #expect((attributes[.foregroundColor] as? NSColor)?.usingColorSpace(.deviceRGB)?.redComponent == 1)
        #expect(attributes[.link] != nil)
        #expect((attributes[.paragraphStyle] as? NSParagraphStyle)?.alignment == .right)
        for data in [Data("bad rtf".utf8), Data(count: RichTextCardContent.maximumBytes + 1)] {
            let fallback = RichTextCardContent.decode(data, fallback: String(repeating: "a", count: 8000))
            #expect(fallback.length == RichTextCardContent.maximumUTF16)
            #expect(fallback.attribute(.font, at: 0, effectiveRange: nil) != nil)
        }
        let long = NSAttributedString(string: String(repeating: "a", count: 3999) + "😀tail")
        let excerpt = RichTextCardContent.decode(try #require(RichTextCodec.encode(long)), fallback: "")
        #expect(excerpt.length == 3999)
        #expect(excerpt.string == String(repeating: "a", count: 3999))
    }

    @Test func mounted_surface_reuses_decoding_clips_layout_and_releases_content() throws {
        _ = NSApplication.shared
        let data = try #require(RichTextCodec.encode(formatted()))
        let surface = RichTextCardView.Surface(frame: NSRect(x: 0, y: 0, width: 160, height: 80))
        surface.update(data: data, fallback: "Rich card", matches: [])
        let first = try #require(surface.base)
        surface.update(data: data, fallback: "Rich card", matches: [MatchSpan(start: 0, length: 4)])
        #expect(surface.base === first)
        #expect(surface.text.attribute(.underlineStyle, at: 0, effectiveRange: nil) != nil)
        surface.update(
            data: data, fallback: "Rich card",
            matches: [MatchSpan(start: -1, length: 4), MatchSpan(start: 9000, length: 4)])
        #expect(surface.base === first)
        #expect(surface.hitTest(.zero) == nil)
        #expect(surface.intrinsicContentSize.width == NSView.noIntrinsicMetric)
        let window = NSWindow(contentRect: surface.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = surface
        defer { window.close() }
        surface.layoutSubtreeIfNeeded()
        let bitmap = try #require(surface.bitmapImageRepForCachingDisplay(in: surface.bounds))
        surface.cacheDisplay(in: surface.bounds, to: bitmap)
        var redPixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                    color.alphaComponent > 0.5, color.redComponent > 0.7, color.greenComponent < 0.3
                {
                    redPixels += 1
                }
            }
        }
        #expect(redPixels > 5)
        surface.update(data: data, fallback: "Rich card", matches: [MatchSpan(start: 0, length: 99)])
        #expect(surface.text.length == 9)
        surface.update(data: data, fallback: "different source text", matches: [MatchSpan(start: 0, length: 4)])
        #expect(surface.text.attribute(.underlineStyle, at: 0, effectiveRange: nil) == nil)
        surface.clear()
        #expect(surface.base == nil && surface.text.length == 0)
    }
}

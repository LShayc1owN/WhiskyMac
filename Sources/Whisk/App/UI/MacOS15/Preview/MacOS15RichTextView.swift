// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

struct MacOS15RichTextView: NSViewRepresentable {
    let text: NSAttributedString
    var editable = false
    var onChange: (NSAttributedString) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let view = scroll.documentView as! NSTextView
        view.isRichText = true
        view.importsGraphics = false
        view.isAutomaticLinkDetectionEnabled = false
        view.allowsUndo = false
        view.drawsBackground = true
        view.backgroundColor = .white
        view.textColor = .black
        view.usesFontPanel = true
        scroll.drawsBackground = false
        view.textContainerInset = NSSize(width: 12, height: 12)
        view.delegate = context.coordinator
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        context.coordinator.onChange = onChange
        view.isEditable = editable
        view.isSelectable = true
        if !view.attributedString().isEqual(to: text) {
            view.textStorage?.setAttributedString(text)
        }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        (scroll.documentView as? NSTextView)?.textStorage?.setAttributedString(NSAttributedString(string: ""))
        (scroll.documentView as? NSTextView)?.delegate = nil
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onChange: (NSAttributedString) -> Void
        init(onChange: @escaping (NSAttributedString) -> Void) { self.onChange = onChange }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            onChange(NSAttributedString(attributedString: view.attributedString()))
        }
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool { true }
    }
}

/// Every stored preview uses the same reader. Cancelled views waiting behind a
/// slow read can drop the request before opening the next original.
struct MacOS15RichTextPreviewPane: View {
    let content: BinaryContent?
    let fallback: String

    init(item: ClipboardItem) {
        self.init(content: item.richText, fallback: item.payload.searchableText ?? "")
    }

    init(content: BinaryContent?, fallback: String) {
        self.content = content
        self.fallback = fallback
    }

    private struct Request: Equatable {
        let content: BinaryContent?
        let fallback: String
    }

    @State private var result: (request: Request, text: NSAttributedString)?

    var body: some View {
        let request = Request(content: content, fallback: fallback)
        Group {
            if let result, result.request == request { MacOS15RichTextView(text: result.text) } else { ProgressView() }
        }
        .task(id: request) {
            result = nil
            let data = await RichTextPreviewReader.shared.read(
                request.content, maximumBytes: RichTextCodec.maximumBytes)
            guard !Task.isCancelled else { return }
            result = (request, RichTextCodec.decode(data, fallback: request.fallback))
        }
        .onDisappear { result = nil }
    }
}

/// A card excerpt has a stricter parsing budget than the full preview.
struct MacOS15RichTextCardView: NSViewRepresentable {
    let data: Data
    let fallback: String
    var matches: [MatchSpan] = []

    func makeNSView(context: Context) -> Surface { Surface() }
    func updateNSView(_ view: Surface, context: Context) {
        view.update(data: data, fallback: fallback, matches: matches)
    }
    static func dismantleNSView(_ view: Surface, coordinator: ()) { view.clear() }

    final class Surface: NSView {
        private var source: Data?
        private var fallback = ""
        private var matches: [MatchSpan] = []
        private(set) var base: NSAttributedString?
        private(set) var text = NSAttributedString(string: "")
        override var isFlipped: Bool { true }
        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func update(data: Data, fallback: String, matches: [MatchSpan]) {
            let changed = source != data || self.fallback != fallback
            guard changed || self.matches != matches else { return }
            if changed {
                source = data
                self.fallback = fallback
                base = RichTextCardContent.decode(
                    data, fallback: fallback, defaultFont: .systemFont(ofSize: 12), defaultColor: .labelColor)
            }
            self.matches = matches
            let result = NSMutableAttributedString(attributedString: base ?? NSAttributedString(string: ""))
            // Search spans belong to plain capture text; only apply when offsets agree.
            if fallback.hasPrefix(result.string) {
                for match in matches where match.start >= 0 && match.length > 0 && match.start < result.length {
                    result.addAttribute(
                        .underlineStyle, value: NSUnderlineStyle.single.rawValue,
                        range: NSRange(location: match.start, length: min(match.length, result.length - match.start)))
                }
            }
            // AppKit otherwise substitutes its link color while drawing, even
            // when RTF supplies an explicit foreground color. Cards are inert;
            // retain the original link in base/history and draw its styled text.
            result.removeAttribute(.link, range: NSRange(location: 0, length: result.length))
            text = result
            needsDisplay = true
            setAccessibilityElement(false)
        }

        override func draw(_ dirtyRect: NSRect) {
            NSGraphicsContext.saveGraphicsState()
            bounds.clip()
            text.draw(with: bounds, options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine])
            NSGraphicsContext.restoreGraphicsState()
        }

        func clear() {
            source = nil
            fallback = ""
            matches = []
            base = nil
            text = NSAttributedString(string: "")
        }
    }
}

/// Only mounted, visible rich-text cards request their original formatting.
struct MacOS15DeferredRichTextCardView: View {
    let content: BinaryContent
    let fallback: String
    let matches: [MatchSpan]
    let isActive: Bool
    @State private var data: Data?

    private struct Request: Equatable {
        let content: BinaryContent
        let active: Bool
    }

    var body: some View {
        Group {
            if let data, isActive {
                MacOS15RichTextCardView(data: data, fallback: fallback, matches: matches)
            } else {
                MacOS15RichTextCardView(data: Data(), fallback: fallback, matches: matches)
            }
        }
        .task(id: Request(content: content, active: isActive)) {
            data = nil
            guard isActive else { return }
            let value = await RichTextPreviewReader.shared.read(content, maximumBytes: RichTextCardContent.maximumBytes)
            guard !Task.isCancelled else { return }
            data = value
        }
        .onDisappear { data = nil }
    }
}

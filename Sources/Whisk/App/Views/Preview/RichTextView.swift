// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

enum RichTextCodec {
    // Bound parsing work for malformed or unusually large clipboard data.
    static let maximumBytes = 8 * 1024 * 1024

    static func decode(_ data: Data?, fallback: String) -> NSAttributedString {
        guard let data, data.count <= maximumBytes,
            let text = try? NSAttributedString(
                data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil)
        else { return NSAttributedString(string: fallback) }
        return text
    }

    static func encode(_ text: NSAttributedString) -> Data? {
        try? text.data(
            from: NSRange(location: 0, length: text.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }
}

struct RichTextView: NSViewRepresentable {
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

struct RichTextPreviewPane: View {
    let item: ClipboardItem
    @State private var decoded: NSAttributedString?

    var body: some View {
        Group {
            if let decoded { RichTextView(text: decoded) } else { ProgressView() }
        }
        .onAppear { decode() }
        .onChange(of: item) { _, _ in decode() }
        .onDisappear { decoded = nil }
    }

    private func decode() {
        decoded = RichTextCodec.decode(item.rtf, fallback: item.payload.searchableText ?? "")
    }
}

/// A card excerpt has a stricter parsing budget than the full preview.
enum RichTextCardContent {
    static let maximumBytes = 256 * 1024
    static let maximumUTF16 = 4000

    static func decode(_ data: Data, fallback: String) -> NSAttributedString {
        let decoded =
            data.count <= maximumBytes
            ? RichTextCodec.decode(data, fallback: fallback) : NSAttributedString(string: fallback)
        let end =
            decoded.length > maximumUTF16
            ? (decoded.string as NSString).rangeOfComposedCharacterSequence(at: maximumUTF16).location : decoded.length
        let text = NSMutableAttributedString(
            attributedString: decoded.attributedSubstring(from: NSRange(location: 0, length: end)))
        let all = NSRange(location: 0, length: text.length)
        text.enumerateAttributes(in: all) { attributes, range, _ in
            if attributes[.font] == nil { text.addAttribute(.font, value: NSFont.systemFont(ofSize: 12), range: range) }
            if attributes[.foregroundColor] == nil {
                text.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
            }
        }
        return text
    }
}

/// Draw-only AppKit text keeps card gestures, scrolling and layout with the rail.
struct RichTextCardView: NSViewRepresentable {
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
                base = RichTextCardContent.decode(data, fallback: fallback)
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

// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

@available(macOS 26, *)
struct MacOS26RichTextView: NSViewRepresentable {
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
@available(macOS 26, *)
struct MacOS26RichTextPreviewPane: View {
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
            if let result, result.request == request { MacOS26RichTextView(text: result.text) } else { ProgressView() }
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

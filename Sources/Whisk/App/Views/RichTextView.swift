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

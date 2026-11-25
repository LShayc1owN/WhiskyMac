// WhiskyMac: modified or added 2026-11-15 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

/// Native text layout keeps full previews scrollable without measuring a SwiftUI label of the entire document.
@available(macOS 26, *)
struct MacOS26TextPreviewView: NSViewRepresentable {
    @Environment(\.interfaceTypography) private var typography
    let text: String
    var tokens: [CodeToken] = []
    var monospaced = false

    func makeNSView(context: Context) -> Surface { Surface(frame: .zero) }

    func updateNSView(_ surface: Surface, context: Context) {
        surface.update(text: text, tokens: tokens, monospaced: monospaced, typography: typography)
    }

    static func dismantleNSView(_ surface: Surface, coordinator: ()) { surface.clear() }

    final class Surface: NSScrollView {
        let textView: NSTextView
        private let storage: NSTextStorage
        private var source: String?
        private var tokens: [CodeToken] = []
        private var monospaced = false
        private var typography = InterfaceTypography.standard

        override init(frame frameRect: NSRect) {
            let storage = NSTextStorage()
            let layout = NSLayoutManager()
            layout.allowsNonContiguousLayout = true
            storage.addLayoutManager(layout)
            let container = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            self.storage = storage
            textView = NSTextView(frame: .zero, textContainer: container)
            super.init(frame: frameRect)
            drawsBackground = false
            borderType = .noBorder
            hasVerticalScroller = true
            autohidesScrollers = true
            textView.isEditable = false
            textView.isSelectable = true
            textView.isVerticallyResizable = true
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.autoresizingMask = [.width]
            textView.drawsBackground = false
            textView.textContainerInset = .zero
            textView.isAutomaticLinkDetectionEnabled = false
            textView.allowsUndo = false
            textView.usesFindBar = true
            documentView = textView
        }

        required init?(coder: NSCoder) { return nil }

        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }

        override func layout() {
            super.layout()
            textView.minSize = contentSize
            let width = monospaced ? max(contentSize.width, textView.frame.width) : contentSize.width
            let size = NSSize(width: width, height: max(contentSize.height, textView.frame.height))
            if textView.frame.size != size { textView.setFrameSize(size) }
        }

        func update(
            text: String, tokens: [CodeToken], monospaced: Bool, typography: InterfaceTypography = .standard
        ) {
            let typography = typography.plainText
            guard
                source != text || self.tokens != tokens || self.monospaced != monospaced
                    || self.typography != typography
            else { return }
            self.typography = typography
            source = text
            self.tokens = tokens
            self.monospaced = monospaced
            hasHorizontalScroller = monospaced
            textView.isHorizontallyResizable = monospaced
            textView.textContainer?.widthTracksTextView = !monospaced
            textView.textContainer?.containerSize = NSSize(
                width: monospaced ? .greatestFiniteMagnitude : contentSize.width,
                height: .greatestFiniteMagnitude)
            let font =
                monospaced
                ? NSFont.monospacedSystemFont(ofSize: typography.points(12), weight: .regular)
                : NSFont.systemFont(ofSize: typography.points(13))
            storage.beginEditing()
            storage.setAttributedString(
                NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor]))
            for token in tokens
            where token.start >= 0 && token.length > 0 && token.start <= storage.length
                && token.length <= storage.length - token.start
            {
                storage.addAttribute(
                    .foregroundColor, value: MacOS26CardTextFormatting.color(for: token.kind),
                    range: NSRange(location: token.start, length: token.length))
            }
            storage.endEditing()
            needsLayout = true
        }

        func clear() {
            source = nil
            tokens = []
            storage.setAttributedString(NSAttributedString(string: ""))
        }
    }
}

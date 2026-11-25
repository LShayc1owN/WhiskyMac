// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit

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

actor RichTextPreviewReader {
    static let shared = RichTextPreviewReader()

    func read(_ content: BinaryContent?, maximumBytes: Int) -> Data? {
        guard !Task.isCancelled, let content, content.byteCount <= maximumBytes else { return nil }
        return try? content.read()
    }
}

enum RichTextCardContent {
    static let maximumBytes = 256 * 1024
    static let maximumUTF16 = 4000

    static func decode(
        _ data: Data, fallback: String, defaultFont: NSFont, defaultColor: NSColor
    ) -> NSAttributedString {
        let excerpt = String(fallback.prefix(maximumUTF16))
        let decoded =
            data.count <= maximumBytes
            ? RichTextCodec.decode(data, fallback: excerpt) : NSAttributedString(string: excerpt)
        let end =
            decoded.length > maximumUTF16
            ? (decoded.string as NSString).rangeOfComposedCharacterSequence(at: maximumUTF16).location : decoded.length
        let text = NSMutableAttributedString(
            attributedString: decoded.attributedSubstring(from: NSRange(location: 0, length: end)))
        let all = NSRange(location: 0, length: text.length)
        text.enumerateAttributes(in: all) { attributes, range, _ in
            if attributes[.font] == nil { text.addAttribute(.font, value: defaultFont, range: range) }
            if attributes[.foregroundColor] == nil {
                text.addAttribute(.foregroundColor, value: defaultColor, range: range)
            }
        }
        return text
    }
}

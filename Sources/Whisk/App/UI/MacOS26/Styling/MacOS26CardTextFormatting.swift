// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit

@available(macOS 26, *)
enum MacOS26CardTextFormatting {
    /// The text in the label color, each token recolored by kind, each
    /// query match washed in the accent; a span pointing past the end is
    /// ignored rather than trusted.
    static func attributed(_ text: String, tokens: [CodeToken], matches: [MatchSpan] = []) -> AttributedString {
        let rendered = NSMutableAttributedString(string: text)
        let full = NSRange(location: 0, length: rendered.length)
        rendered.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
        for token in tokens {
            let range = NSRange(location: token.start, length: token.length)
            guard range.location + range.length <= rendered.length else { continue }
            rendered.addAttribute(.foregroundColor, value: color(for: token.kind), range: range)
        }
        Self.wash(rendered, with: matches)
        return AttributedString(rendered)
    }

    /// Plain text with the query matches washed in the accent.
    static func highlighted(_ text: String, matches: [MatchSpan]) -> AttributedString {
        let rendered = NSMutableAttributedString(string: text)
        Self.wash(rendered, with: matches)
        return AttributedString(rendered)
    }

    static var matchWash: NSColor { NSColor.macOS26Matcha.withAlphaComponent(0.32) }

    private static func wash(_ rendered: NSMutableAttributedString, with matches: [MatchSpan]) {
        for span in matches {
            let range = NSRange(location: span.start, length: span.length)
            guard range.location + range.length <= rendered.length else { continue }
            rendered.addAttribute(.backgroundColor, value: matchWash, range: range)
        }
    }

    static func color(for kind: CodeToken.Kind) -> NSColor {
        switch kind {
        case .keyword: return .systemPurple
        case .string: return .systemRed
        case .comment: return .secondaryLabelColor
        case .number: return .systemBlue
        }
    }
}

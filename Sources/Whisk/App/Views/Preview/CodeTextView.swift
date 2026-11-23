// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

/// Renders a code preview by applying the presenter's tokens as colors on
/// a monospaced base.
struct CodeTextView: View {
    let text: String
    let tokens: [CodeToken]
    var lineLimit: Int? = 8
    var matches: [MatchSpan] = []

    var body: some View {
        Text(CardTextFormatting.attributed(text, tokens: tokens, matches: matches))
            .font(.system(size: 12, design: .monospaced))
            .lineSpacing(1.5)
            .lineLimit(lineLimit)
    }

    static func attributed(_ text: String, tokens: [CodeToken], matches: [MatchSpan] = []) -> AttributedString {
        CardTextFormatting.attributed(text, tokens: tokens, matches: matches)
    }

    static func highlighted(_ text: String, matches: [MatchSpan]) -> AttributedString {
        CardTextFormatting.highlighted(text, matches: matches)
    }

    static var matchWash: NSColor { CardTextFormatting.matchWash }

    static func color(for kind: CodeToken.Kind) -> NSColor { CardTextFormatting.color(for: kind) }
}

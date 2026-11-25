// WhiskyMac: added 2026-11-24 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

struct SecretRecognition: Equatable {
    var enabled = true
    var mask = true
    var classify = true

    func recognizes(_ item: ClipboardItem) -> Bool { enabled && item.secretMatch != nil }

    func masks(_ item: ClipboardItem) -> Bool { mask && recognizes(item) }

    func hidesContent(of item: ClipboardItem) -> Bool { item.pinnedMetadata.hidesContent || masks(item) }

    func category(of item: ClipboardItem) -> ContentCategory {
        classify && recognizes(item) ? .secret : item.category
    }
}

/// Lexical, offline detection. No validation against a service. A bounded scan
/// runs when a record is made or loaded, never while moving the card cursor.
struct SecretMatch: Equatable, Hashable {
    let visiblePrefix: String
    var maskedText: String { visiblePrefix + "••••••••" }

    private static let scanLimit = 65_536
    private static let pattern = try? NSRegularExpression(
        pattern: [
            #"(?<![A-Za-z0-9_-])(?:sk[-_]|rk_|gh[pousr]_|github_pat_|xox[baprs]-|glpat-|npm_|pypi-|ya29\.)[A-Za-z0-9_-]{16,}"#,
            #"(?<![A-Za-z0-9_-])eyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{8,}(?![A-Za-z0-9_-])"#,
            #"(?im:^\s*(?:set-cookie|cookie)\s*:[ \t]*[\w.-]+=[^\s;]+)"#,
            #"(?i:\bBearer[ \t]+[A-Za-z0-9._~+/-]{16,}={0,2})"#,
            #"(?i:(?:^|[\s?&{"',;])(?:api[_-]?key|(?:access|refresh|auth|id)[_-]?token|token|session(?:[_-]?id)?|sid|phpsessid|jsessionid|connect\.sid)["']?[ \t]*[=:][ \t]*["']?[A-Za-z0-9._~%+/-]{12,})"#,
            #"-----BEGIN (?:[A-Z0-9]+ )?PRIVATE KEY-----"#,
        ].joined(separator: "|"))
    private static let hashLengths: Set<Int> = [32, 40, 64, 96, 128]

    static func detect(_ payload: Payload, group: SplitGroup?) -> SecretMatch? {
        if group?.parts.contains(where: { $0.payload.transformableText.flatMap(detect) != nil }) == true {
            // A child can be sensitive even when the parent has no recognized format.
            return SecretMatch(visiblePrefix: "")
        }
        return payload.transformableText.flatMap(detect)
    }

    static func detect(_ text: String) -> SecretMatch? {
        let bounded = text.utf8.count > scanLimit
        let sample = bounded ? String(decoding: text.utf8.prefix(scanLimit), as: UTF8.self) : text
        let range = NSRange(sample.startIndex..., in: sample)
        if let match = pattern?.firstMatch(in: sample, range: range),
            let matched = Range(match.range, in: sample)
        {
            // Limit how much of an early credential can appear in a long card,
            // even when its own length is much less than 20% of the whole card.
            let cap = sample[..<matched.lowerBound].count + sample[matched].count / 5
            return maskedPrefix(of: sample, cap: cap)
        }
        guard !bounded else { return nil }
        let trimmed = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        if hashLengths.contains(trimmed.utf8.count),
            trimmed.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) })
        {
            return maskedPrefix(of: sample, cap: sample.prefix(while: \.isWhitespace).count + trimmed.count / 5)
        }
        return nil
    }

    private static func maskedPrefix(of value: String, cap: Int) -> SecretMatch {
        let prefix = value.prefix(min(value.count / 5, cap))
        return SecretMatch(visiblePrefix: String(prefix))
    }
}

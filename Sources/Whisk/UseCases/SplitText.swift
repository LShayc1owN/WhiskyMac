// WhiskyMac: modified or added 2026-11-10 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

/// Computes ranges only. RTF and URL detection are supplied by the adapter.
enum SplitText {
    static func candidates(text: String, options: SplitOptions, links: [SplitLink] = []) throws -> [SplitCandidate] {
        try Task.checkCancellation()
        guard options.customDelimiter.utf16.count <= SplitLimits.maximumUTF16 else { throw SplitFailure.tooLarge }
        let ns = text as NSString
        guard ns.length <= SplitLimits.maximumUTF16 else { throw SplitFailure.tooLarge }
        var ranges: [(NSRange, URL?, Int)] = []
        let newline = "(?:\\r\\n|[\\n\\r\\u0085\\u2028\\u2029])"
        if options.rule == .links {
            var end = 0
            for link in links.sorted(by: { $0.range.location < $1.range.location }) {
                guard link.range.location >= end, link.range.length > 0, NSMaxRange(link.range) <= ns.length else {
                    continue
                }
                if !options.linksOnly {
                    ranges.append((NSRange(location: end, length: link.range.location - end), nil, 0))
                }
                ranges.append((link.range, link.url, 0))
                end = NSMaxRange(link.range)
            }
            if !options.linksOnly { ranges.append((NSRange(location: end, length: ns.length - end), nil, 0)) }
        } else {
            let pattern: String
            switch options.rule {
            case .lines: pattern = newline
            case .paragraphs: pattern = newline + "[\\t ]*" + newline + "(?:[\\t ]*" + newline + ")*"
            case .delimiters:
                var separators = options.delimiters.flatMap(\.values)
                if !options.customDelimiter.isEmpty { separators.append(options.customDelimiter) }
                guard !separators.isEmpty else { throw SplitFailure.noDelimiter }
                pattern = separators.sorted { $0.utf16.count > $1.utf16.count }
                    .map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
            case .links: pattern = ""
            }
            let regex = try NSRegularExpression(pattern: pattern)
            var start = 0
            var exceeded = false
            regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, stop in
                guard let match else { return }
                let end = options.keepDelimiter ? NSMaxRange(match.range) : match.range.location
                let range = NSRange(location: start, length: end - start)
                if !ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ranges.append((range, nil, options.keepDelimiter ? match.range.length : 0))
                }
                start = NSMaxRange(match.range)
                if Task.isCancelled || ranges.count > SplitLimits.maximumParts { exceeded = true; stop.pointee = true }
            }
            try Task.checkCancellation()
            if exceeded { throw SplitFailure.tooManyParts }
            ranges.append((NSRange(location: start, length: ns.length - start), nil, 0))
        }
        var result: [SplitCandidate] = []
        for (original, link, trailer) in ranges {
            try Task.checkCancellation()
            var range = original
            let raw = ns.substring(with: NSRange(location: range.location, length: range.length - trailer))
            if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            if options.trimWhitespace, link == nil {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                let local = (raw as NSString).range(of: trimmed)
                range = NSRange(
                    location: range.location + local.location,
                    length: trailer > 0 ? range.length - local.location : local.length)
            }
            guard ns.rangeOfComposedCharacterSequences(for: range) == range else { throw SplitFailure.invalidBoundary }
            let value = link?.absoluteString ?? ns.substring(with: range)
            result.append(
                SplitCandidate(
                    id: result.count, range: range,
                    part: SplitPart(id: UUID(), text: value, link: link, rtf: nil)))
            if result.count > SplitLimits.maximumParts { throw SplitFailure.tooManyParts }
        }
        return result
    }
}

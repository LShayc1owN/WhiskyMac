import Foundation

/// fzf-style fuzzy matching: the pattern's characters must appear in
/// order — a subsequence — and the score rewards what fzf rewards,
/// consecutive runs and word-boundary hits, with penalties for opening
/// and stretching gaps, so the tightest, best-anchored match ranks
/// first. Smart case: an all-lowercase pattern matches insensitively.
enum FuzzyMatch {
    private static let match = 16
    private static let bonusConsecutive = 4
    private static let bonusBoundary = 8
    private static let penaltyGapStart = 3
    private static let penaltyGapExtension = 1

    /// A match with the offsets, in characters of the candidate, of the
    /// characters the pattern landed on — what a card highlights.
    struct Match: Equatable {
        let score: Int
        let positions: [Int]
    }

    static func score<S: StringProtocol>(pattern: String, in candidate: S) -> Int? {
        match(pattern: pattern, in: candidate)?.score
    }

    static func match<S: StringProtocol>(pattern: String, in candidate: S) -> Match? {
        guard !pattern.isEmpty else { return Match(score: 0, positions: []) }
        let insensitive = !pattern.contains(where: \.isUppercase)
        // ASCII fast lane: raw bytes compare without a full lowercased
        // copy of the candidate. ASCII byte offsets are character offsets,
        // so highlight positions stay identical.
        if candidate.utf8.count == candidate.count, pattern.utf8.count == pattern.count,
            let ascii = matchASCII(pattern: pattern, in: candidate, insensitive: insensitive)
        {
            return ascii
        }
        let text = Array(insensitive ? candidate.lowercased() : String(candidate))
        let needle = Array(insensitive ? pattern.lowercased() : pattern)
        guard needle.count <= text.count else { return nil }

        // Forward pass finds the earliest end of a full match; the
        // backward pass then shrinks toward the tightest window ending
        // there — fzf's two-pass v1 heart.
        var needleIndex = 0
        var end = -1
        for (position, character) in text.enumerated() where character == needle[needleIndex] {
            needleIndex += 1
            if needleIndex == needle.count {
                end = position
                break
            }
        }
        guard end >= 0 else { return nil }
        needleIndex = needle.count - 1
        var start = end
        var position = end
        while position >= 0 {
            if text[position] == needle[needleIndex] {
                if needleIndex == 0 {
                    start = position
                    break
                }
                needleIndex -= 1
            }
            position -= 1
        }
        return score(
            window: text, needle: needle, start: start, end: end,
            isWordStart: { Self.isWordStart($0, at: $1) })
    }

    private static func matchASCII<S: StringProtocol>(pattern: String, in candidate: S, insensitive: Bool) -> Match? {
        let needle = pattern.utf8.map { byte in insensitive && byte >= 65 && byte <= 90 ? byte + 32 : byte }
        let text = Array(candidate.utf8)
        guard needle.count <= text.count else { return nil }
        var needleIndex = 0
        var end = -1
        for (position, byte) in text.enumerated() where byte == needle[needleIndex] {
            needleIndex += 1
            if needleIndex == needle.count {
                end = position
                break
            }
        }
        guard end >= 0 else { return nil }
        needleIndex = needle.count - 1
        var start = end
        var position = end
        while position >= 0 {
            if text[position] == needle[needleIndex] {
                if needleIndex == 0 {
                    start = position
                    break
                }
                needleIndex -= 1
            }
            position -= 1
        }
        return score(
            window: text, needle: needle, start: start, end: end,
            isWordStart: { Self.asciiWordStart($0, at: $1) })
    }

    private static func asciiWordStart(_ text: [UInt8], at position: Int) -> Bool {
        guard position > 0 else { return true }
        let previous = text[position - 1]
        if previous == 32 || previous == 95 || (33...47).contains(Int(previous))
            || (58...64).contains(Int(previous)) || (91...96).contains(Int(previous))
            || (123...126).contains(Int(previous))
        {
            return true
        }
        let current = text[position]
        return current >= 65 && current <= 90 && previous >= 97 && previous <= 122
    }

    private static func score<C: RandomAccessCollection>(
        window: C, needle: [C.Element], start: Int, end: Int, isWordStart: (C, Int) -> Bool
    ) -> Match where C.Element: Equatable {
        var total = 0
        var positions: [Int] = []
        var needleIndex = 0
        var previousMatched = false
        for position in start...end where needleIndex < needle.count {
            if window[window.index(window.startIndex, offsetBy: position)] == needle[needleIndex] {
                total += match
                if previousMatched {
                    total += bonusConsecutive
                }
                if isWordStart(window, position) {
                    total += bonusBoundary
                }
                positions.append(position)
                previousMatched = true
                needleIndex += 1
            } else {
                total -= previousMatched ? penaltyGapStart : penaltyGapExtension
                previousMatched = false
            }
        }
        return Match(score: total, positions: positions)
    }

    private static func isWordStart(_ text: [Character], at position: Int) -> Bool {
        guard position > 0 else { return true }
        let previous = text[position - 1]
        if previous.isWhitespace || previous.isPunctuation || previous.isSymbol || previous == "_" {
            return true
        }
        return text[position].isUppercase && previous.isLowercase
    }
}

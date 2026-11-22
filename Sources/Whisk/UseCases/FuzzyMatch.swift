import Foundation

/// Subsequence matching with smart case. An exact ASCII spelling takes precedence
/// over a folded spelling, as it does for highlights in existing histories.
enum FuzzyMatch {
    private static let baseScore = 16
    private static let consecutiveBonus = 4
    private static let boundaryBonus = 8
    private static let gapStartPenalty = 3
    private static let gapExtensionPenalty = 1

    struct Match: Equatable {
        let score: Int
        let positions: [Int]
    }

    struct Pattern: Equatable {
        private let needle: [Character]
        private let ascii: [UInt8]?
        private let insensitive: Bool
        private let canMatchASCII: Bool

        init(_ pattern: String) {
            insensitive = !pattern.contains(where: \.isUppercase)
            let folded = insensitive ? pattern.lowercased() : pattern
            needle = Array(folded)
            let bytes = Array(pattern.utf8)
            ascii = Self.hasSingleByteCharacters(bytes) ? bytes : nil
            // Canonically equivalent characters (e.g. the Kelvin sign and K)
            // can compare equal even when their original UTF-8 bytes differ.
            canMatchASCII = ascii != nil || folded.precomposedStringWithCanonicalMapping.utf8.allSatisfy { $0 < 128 }
        }

        func score<S: StringProtocol>(in candidate: S) -> Int? {
            evaluate(candidate, offsets: false)?.score
        }

        func match<S: StringProtocol>(in candidate: S) -> Match? {
            evaluate(candidate, offsets: true)
        }

        // CRLF is one Swift Character. Lone CR and LF are each one byte.
        private static func hasSingleByteCharacters<C: Collection>(_ bytes: C) -> Bool where C.Element == UInt8 {
            guard bytes.allSatisfy({ $0 < 128 }) else { return false }
            guard bytes.contains(13) else { return true }
            return !zip(bytes, bytes.dropFirst()).contains { $0 == 13 && $1 == 10 }
        }

        private func evaluate<S: StringProtocol>(_ candidate: S, offsets: Bool) -> Match? {
            guard !needle.isEmpty else { return Match(score: 0, positions: []) }
            guard !candidate.isEmpty else { return nil }
            func evaluateBytes(_ bytes: UnsafeBufferPointer<UInt8>) -> Match? {
                if Self.hasSingleByteCharacters(bytes) {
                    guard canMatchASCII else { return nil }
                    if let ascii {
                        guard ascii.count <= bytes.count else { return nil }
                        if let exact = FuzzyMatch.search(
                            bytes, for: ascii, offsets: offsets, equal: ==,
                            boundary: { i in
                                i == 0 || FuzzyMatch.asciiSeparator(bytes[i - 1])
                                    || ((65...90).contains(bytes[i]) && (97...122).contains(bytes[i - 1]))
                            })
                        {
                            return exact
                        }
                        guard insensitive else { return nil }
                        return FuzzyMatch.search(
                            bytes, for: ascii, offsets: offsets,
                            equal: { byte, wanted in
                                (byte >= 65 && byte <= 90 ? byte + 32 : byte) == wanted
                            },
                            boundary: { i in
                                i == 0 || (9...13).contains(bytes[i - 1])
                                    || FuzzyMatch.asciiSeparator(bytes[i - 1])
                            })
                    }
                }
                let text = insensitive ? candidate.lowercased() : String(candidate)
                return FuzzyMatch.search(text, for: needle, offsets: offsets, equal: ==) { i in
                    guard i != text.startIndex else { return true }
                    let previous = text[text.index(before: i)]
                    return previous.isWhitespace || previous.isPunctuation || previous.isSymbol
                        || (text[i].isUppercase && previous.isLowercase)
                }
            }
            if let result = candidate.utf8.withContiguousStorageIfAvailable(evaluateBytes) { return result }
            return Array(candidate.utf8).withUnsafeBufferPointer(evaluateBytes)
        }
    }

    static func score<S: StringProtocol>(pattern: String, in candidate: S) -> Int? {
        Pattern(pattern).score(in: candidate)
    }

    static func match<S: StringProtocol>(pattern: String, in candidate: S) -> Match? {
        Pattern(pattern).match(in: candidate)
    }

    private static func asciiSeparator(_ previous: UInt8) -> Bool {
        (32...47).contains(previous) || (58...64).contains(previous)
            || (91...96).contains(previous) || (123...126).contains(previous)
    }

    /// Find the earliest end, shrink back to the tightest start, then score
    /// that window. Only highlighters request character offsets.
    private static func search<C: BidirectionalCollection>(
        _ text: C, for needle: [C.Element], offsets: Bool,
        equal: (C.Element, C.Element) -> Bool, boundary: (C.Index) -> Bool
    ) -> Match? {
        var end = text.startIndex
        var needleIndex = 0
        while end != text.endIndex {
            if equal(text[end], needle[needleIndex]) {
                needleIndex += 1
                if needleIndex == needle.count { break }
            }
            text.formIndex(after: &end)
        }
        guard end != text.endIndex else { return nil }
        var start = end
        while true {
            if equal(text[start], needle[needleIndex - 1]) {
                needleIndex -= 1
                if needleIndex == 0 { break }
            }
            text.formIndex(before: &start)
        }
        var points = 0
        var positions: [Int] = []
        var offset = offsets ? text.distance(from: text.startIndex, to: start) : 0
        var previousHit = false
        var cursor = start
        while true {
            if equal(text[cursor], needle[needleIndex]) {
                points += baseScore + (previousHit ? consecutiveBonus : 0) + (boundary(cursor) ? boundaryBonus : 0)
                if offsets { positions.append(offset) }
                needleIndex += 1
                if needleIndex == needle.count { break }
                previousHit = true
            } else {
                points -= previousHit ? gapStartPenalty : gapExtensionPenalty
                previousHit = false
            }
            text.formIndex(after: &cursor)
            offset += 1
        }
        return Match(score: points, positions: positions)
    }
}

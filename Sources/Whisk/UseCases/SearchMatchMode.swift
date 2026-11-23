import Foundation

enum SearchMatchMode: String, CaseIterable {
    case fuzzy
    case containing
    case matchingWord
    case startingWith
    case endingWith
}

/// Compiled once per query so all cards in a pass share the same matching rule.
struct LiteralSearch {
    private let expression: NSRegularExpression?

    init(_ phrase: String, mode: SearchMatchMode) {
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        let pattern: String
        switch mode {
        case .fuzzy, .containing: pattern = escaped
        case .matchingWord: pattern = "\\b" + escaped + "\\b"
        case .startingWith: pattern = "\\A" + escaped
        case .endingWith: pattern = escaped + "\\z"
        }
        expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .useUnicodeWordBoundaries])
    }

    func firstMatch(in value: String, within range: NSRange? = nil) -> NSRange? {
        // A preview may truncate a word or the entire field. Evaluate its anchors
        // and boundaries against the full text even when scanning only the excerpt.
        expression?.firstMatch(
            in: value, options: [.withTransparentBounds, .withoutAnchoringBounds],
            range: range ?? NSRange(value.startIndex..., in: value)
        )?.range
    }
}

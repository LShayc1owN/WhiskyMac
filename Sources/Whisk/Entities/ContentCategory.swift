import Foundation

/// What a payload is, as users think of it — the classification behind
/// category filters and card previews.
enum ContentCategory: String, CaseIterable, Equatable {
    case text
    case code
    case color
    case link
    case path
    case secret
    case image
    case files

    /// Code has its own preview and can also be found under Text.
    var parentCategory: ContentCategory? { self == .code ? .text : nil }

    func isIncluded(in categories: Set<ContentCategory>) -> Bool {
        categories.contains(self) || parentCategory.map(categories.contains) == true
    }

    func matches(typePrefix: String) -> Bool {
        rawValue.hasPrefix(typePrefix) || parentCategory?.rawValue.hasPrefix(typePrefix) == true
    }

    var symbolName: String {
        switch self {
        case .text: "text.alignleft"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .color: "paintpalette"
        case .link: "link"
        case .secret: "key.horizontal.fill"
        case .path: "point.bottomleft.forward.to.arrow.triangle.uturn.scurvepath"
        case .image: "photo"
        case .files: "folder"
        }
    }
}

extension Payload {
    var category: ContentCategory {
        switch self {
        case .link: return .link
        case .image, .storedImage: return .image
        case .fileReferences: return .files
        case .text(let value):
            if Self.readsAsFilePath(value) { return .path }
            if ParsedColor.parse(value) != nil { return .color }
            if CodeRecognition.matches(value) { return .code }
            return .text
        }
    }

    /// The color the payload spells out, in any recognized notation.
    var parsedColor: ParsedColor? {
        guard case .text(let value) = self else { return nil }
        return ParsedColor.parse(value)
    }

    /// Lexical classification only: never resolves a home directory, reads a file,
    /// or changes the copied text. Bare relative names are too ambiguous.
    static func readsAsFilePath(_ text: String) -> Bool {
        var path = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let quote = path.first, quote == "\"" || quote == "'", path.count >= 2, path.last == quote {
            path.removeFirst()
            path.removeLast()
        }
        guard path.hasPrefix("/") || path.hasPrefix("~/") || path.hasPrefix("./") || path.hasPrefix("../"),
            !path.hasPrefix("//"), !path.hasPrefix("/*")
        else { return false }
        return !path.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0)
        }
    }
}

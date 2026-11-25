// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Only the content a protected card can draw, prepared after reveal is allowed.
enum SpotlightExcerpt: Equatable {
    case text(String)
    case image

    static let characterLimit = 4_000

    init(_ payload: Payload, includesFilePaths: Bool = false) {
        switch payload {
        case .text(let text): self = .text(String(text.prefix(Self.characterLimit)))
        case .link(let url): self = .text(String(url.absoluteString.prefix(Self.characterLimit)))
        case .fileReferences(let paths):
            self = .text(
                Self.fileList(paths.lazy.map { includesFilePaths ? $0 : URL(fileURLWithPath: $0).lastPathComponent }))
        case .image, .storedImage: self = .image
        }
    }

    /// Equivalent to joining every name with a newline and taking the prefix.
    /// Include the separator before counting so CR followed by LF stays one character.
    static func fileList<Names: Collection>(_ names: Names) -> String where Names.Element == String {
        var text = ""
        var remaining = characterLimit
        var index = names.startIndex
        while remaining > 0, index != names.endIndex {
            var line = names[index]
            names.formIndex(after: &index)
            if index != names.endIndex { line.append("\n") }
            let part = line.prefix(remaining)
            text += part
            remaining -= part.count
        }
        return text
    }
}

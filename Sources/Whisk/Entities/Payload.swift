import Foundation

/// Content captured from the pasteboard. Image bytes are opaque to the
/// kernel; the adapter that produced them owns their encoding.
enum Payload: Equatable, Hashable {
    case text(String)
    case link(URL)
    case image(Data)
    case storedImage(StoredBytes)
    case fileReferences([String])

    func materialized() throws -> Payload {
        if case .storedImage(let reference) = self { return .image(try reference.read()) }
        return self
    }

    static func == (lhs: Payload, rhs: Payload) -> Bool {
        switch (lhs, rhs) {
        case (.text(let a), .text(let b)): return a == b
        case (.link(let a), .link(let b)): return a == b
        case (.fileReferences(let a), .fileReferences(let b)): return a == b
        case (.image(let a), .image(let b)): return a == b
        case (.storedImage(let a), .storedImage(let b)): return a == b
        case (.storedImage(let ref), .image(let data)), (.image(let data), .storedImage(let ref)):
            return ref.matches(data)
        default: return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .text(let text): hasher.combine(0); hasher.combine(text)
        case .link(let url): hasher.combine(1); hasher.combine(url)
        case .fileReferences(let files): hasher.combine(2); hasher.combine(files)
        case .image(let data): hasher.combine(3); hasher.combine(data.count)
        case .storedImage(let ref): hasher.combine(3); hasher.combine(ref.byteCount)
        }
    }

    /// The text a paste-time transform can rewrite: what the card holds
    /// as text, or a link's address. Files and images have none.
    var transformableText: String? {
        switch self {
        case .text(let value): return value
        case .link(let url): return url.absoluteString
        case .image, .storedImage, .fileReferences: return nil
        }
    }

    /// The text a search can look at; image bytes are opaque.
    var searchableText: String? {
        switch self {
        case .text(let value):
            return value
        case .link(let url):
            return url.absoluteString
        case .fileReferences(let paths):
            return paths.joined(separator: " ")
        case .image, .storedImage:
            return nil
        }
    }
}

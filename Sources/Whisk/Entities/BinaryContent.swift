import Foundation

/// An immutable on-disk revision. Owning this handle retains its revision,
/// never its bytes; reads pass through the gateway's bounded cache.
final class StoredBytes: Hashable, @unchecked Sendable {
    let key: String
    let byteCount: Int
    private let reader: @Sendable () throws -> Data
    private let matcher: @Sendable (Data) -> Bool

    init(
        key: String, byteCount: Int, read: @escaping @Sendable () throws -> Data,
        matches: @escaping @Sendable (Data) -> Bool
    ) {
        self.key = key; self.byteCount = byteCount; reader = read; matcher = matches
    }

    func read() throws -> Data { try reader() }
    func matches(_ data: Data) -> Bool { data.count == byteCount && matcher(data) }
    static func == (lhs: StoredBytes, rhs: StoredBytes) -> Bool { lhs.key == rhs.key }
    func hash(into hasher: inout Hasher) { hasher.combine(key) }
}

enum BinaryContent: Hashable, Sendable {
    case inline(Data)
    case stored(StoredBytes)

    var byteCount: Int {
        switch self {
        case .inline(let data): data.count
        case .stored(let reference): reference.byteCount
        }
    }

    var reference: StoredBytes? {
        if case .stored(let reference) = self { return reference }
        return nil
    }

    func read() throws -> Data {
        switch self {
        case .inline(let data): return data
        case .stored(let reference): return try reference.read()
        }
    }

    static func == (lhs: BinaryContent, rhs: BinaryContent) -> Bool {
        switch (lhs, rhs) {
        case (.inline(let a), .inline(let b)): return a == b
        case (.stored(let a), .stored(let b)): return a == b
        case (.stored(let reference), .inline(let data)), (.inline(let data), .stored(let reference)):
            return reference.matches(data)
        }
    }

    func hash(into hasher: inout Hasher) { hasher.combine(byteCount) }
}

import CryptoKit
import Foundation
import SQLite3

/// One cache/reader per database in this process. Handles keep immutable
/// revisions alive for undo; the registry and handle table are weak.
final class SQLiteContentStorage: @unchecked Sendable {
    private final class WeakStorage {
        weak var value: SQLiteContentStorage?; init(_ value: SQLiteContentStorage) { self.value = value }
    }
    private final class WeakReference {
        weak var value: StoredBytes?; init(_ value: StoredBytes) { self.value = value }
    }
    private struct Cached { let data: Data; var access: UInt64 }
    private static let registryLock = NSLock()
    private static var registry: [String: WeakStorage] = [:]
    private let lock = NSLock()
    private let readerLock = NSLock()
    private let onDiskRead: @Sendable () -> Void
    private var db: OpaquePointer?
    private var references: [String: WeakReference] = [:]
    private var cache: [String: Cached] = [:]
    private var cacheEnabled = true
    private var cacheGeneration: UInt64 = 0
    private var releaseScheduled = false
    private var access: UInt64 = 0
    private let byteLimit: Int
    private let countLimit: Int
    private var cost = 0
    private var reads = 0
    var cachedBytes: Int { lock.lock(); defer { lock.unlock() }; return cost }
    var readCount: Int { lock.lock(); defer { lock.unlock() }; return reads }

    static func shared(at url: URL, byteLimit: Int = 24 * 1024 * 1024, countLimit: Int = 64) throws
        -> SQLiteContentStorage
    {
        registryLock.lock(); defer { registryLock.unlock() }
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        if let existing = registry[path]?.value { return existing }
        let storage = try SQLiteContentStorage(path: path, byteLimit: byteLimit, countLimit: countLimit)
        registry = registry.filter { $0.value.value != nil }
        registry[path] = WeakStorage(storage)
        return storage
    }

    init(path: String, byteLimit: Int, countLimit: Int, onDiskRead: @escaping @Sendable () -> Void = {}) throws {
        self.byteLimit = max(0, byteLimit); self.countLimit = max(1, countLimit)
        self.onDiskRead = onDiskRead
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            sqlite3_close_v2(db)
            db = nil
            throw HistoryStoreError.unreadable("cannot open content reader")
        }
        sqlite3_busy_timeout(db, 2000)
        sqlite3_exec(db, "PRAGMA cache_size=-2048", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA mmap_size=0", nil, nil, nil)
    }

    deinit { sqlite3_close_v2(db) }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func reference(key: String, byteCount: Int) -> StoredBytes {
        lock.lock(); defer { lock.unlock() }
        if let old = references[key]?.value { return old }
        let reference = StoredBytes(
            key: key, byteCount: byteCount,
            read: { [self] in try read(key: key, expectedBytes: byteCount) },
            matches: { Self.digest($0) == key })
        references[key] = WeakReference(reference)
        return reference
    }

    /// The caller keeps these handles alive through its transaction.
    func retainedReferences() -> [StoredBytes] {
        lock.lock(); defer { lock.unlock() }
        references = references.filter { $0.value.value != nil }
        return references.values.compactMap(\.value)
    }

    func setEnabled(_ enabled: Bool) {
        lock.lock()
        cacheEnabled = enabled
        if !enabled { cacheGeneration &+= 1; cache.removeAll(); cost = 0 }
        lock.unlock()
        if !enabled { releaseReaderMemory() }
    }

    func clear() {
        lock.lock()
        cacheGeneration &+= 1
        cache.removeAll(); cost = 0
        lock.unlock()
        releaseReaderMemory()
    }

    private func releaseReaderMemory() {
        lock.lock()
        guard !releaseScheduled else { lock.unlock(); return }
        releaseScheduled = true
        lock.unlock()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            self.readerLock.lock()
            sqlite3_db_release_memory(self.db)
            self.readerLock.unlock()
            self.lock.lock(); self.releaseScheduled = false; self.lock.unlock()
        }
    }

    private func cached(_ key: String) -> (data: Data?, generation: UInt64) {
        lock.lock(); defer { lock.unlock() }
        guard let entry = cache[key] else { return (nil, cacheGeneration) }
        access &+= 1
        cache[key]?.access = access
        return (entry.data, cacheGeneration)
    }

    private func read(key: String, expectedBytes: Int) throws -> Data {
        let lookup = cached(key)
        if let data = lookup.data { return data }
        // This lock can wait for SQLite or a large checksum. Panel visibility,
        // invalidation and handle ownership only take the separate short lock.
        readerLock.lock(); defer { readerLock.unlock() }
        if let data = cached(key).data { return data }
        onDiskRead()
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT data FROM binary_content WHERE key = ?", -1, &statement, nil) == SQLITE_OK
        else {
            throw HistoryStoreError.unreadable("cannot prepare original content")
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, key, -1, transient)
        guard sqlite3_step(statement) == SQLITE_ROW, Int(sqlite3_column_bytes(statement, 0)) == expectedBytes else {
            throw HistoryStoreError.unreadable("original content is missing or truncated")
        }
        let data: Data
        if expectedBytes == 0 {
            data = Data()
        } else if let pointer = sqlite3_column_blob(statement, 0) {
            data = Data(bytes: pointer, count: expectedBytes)
        } else {
            throw HistoryStoreError.unreadable("original content is unavailable")
        }
        guard Self.digest(data) == key else { throw HistoryStoreError.unreadable("original content checksum mismatch") }
        lock.lock(); defer { lock.unlock() }
        reads += 1
        if cacheEnabled, lookup.generation == cacheGeneration, data.count <= byteLimit {
            while !cache.isEmpty, cost + data.count > byteLimit || cache.count >= countLimit {
                guard let oldest = cache.min(by: { $0.value.access < $1.value.access })?.key,
                    let removed = cache.removeValue(forKey: oldest)
                else { break }
                cost -= removed.data.count
            }
            access &+= 1
            cache[key] = Cached(data: data, access: access); cost += data.count
        }
        return data
    }
}

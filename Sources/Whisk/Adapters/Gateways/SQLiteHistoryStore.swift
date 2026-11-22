// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// SQLite-backed history store using the system library — no package
/// dependency. Content (including image and RTF blobs) is updated only
/// when it changes; the small ordering table is rewritten on each save,
/// all inside one transaction.
final class SQLiteHistoryStore: HistoryStore {
    var db: OpaquePointer?
    /// The ids whose content rows the last save actually wrote, in order.
    /// Tests watch this to prove the changed-set gate works.
    private(set) var lastContentWriteIDs: [UUID] = []

    private(set) var contentStorage: SQLiteContentStorage!

    init(databaseURL: URL, contentCacheBytes: Int = 24 * 1024 * 1024) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK else {
            sqlite3_close_v2(db)
            db = nil
            throw HistoryStoreError.unwritable("cannot open \(databaseURL.lastPathComponent)")
        }
        var opened = false
        defer { if !opened { sqlite3_close_v2(db); db = nil } }
        // Another connection mid-write — a second Whisk, a backup tool —
        // makes a save wait its turn instead of failing on the spot.
        sqlite3_busy_timeout(db, 2_000)
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA cache_size=-2048")
        try execute("PRAGMA mmap_size=0")
        try execute(
            """
            CREATE TABLE IF NOT EXISTS content (
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                text TEXT,
                link TEXT,
                image BLOB,
                rtf BLOB,
                files TEXT,
                source_app TEXT,
                source_bundle TEXT,
                source_origin TEXT
            )
            """)
        try execute(
            """
            CREATE TABLE IF NOT EXISTS ordering (
                id TEXT PRIMARY KEY,
                position INTEGER NOT NULL,
                copied_at_ms INTEGER NOT NULL,
                is_pinned INTEGER NOT NULL
            )
            """)
        try execute("CREATE TABLE IF NOT EXISTS pin_details (id TEXT PRIMARY KEY, metadata TEXT NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS split_groups (id TEXT PRIMARY KEY, data BLOB NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS split_origins (id TEXT PRIMARY KEY, source_id TEXT NOT NULL)")
        var schema: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(content)", -1, &schema, nil) == SQLITE_OK else {
            throw HistoryStoreError.unreadable(lastMessage())
        }
        var hasOrigin = false
        while sqlite3_step(schema) == SQLITE_ROW {
            if columnText(schema, 1) == "source_origin" { hasOrigin = true }
        }
        sqlite3_finalize(schema)
        if !hasOrigin { try execute("ALTER TABLE content ADD COLUMN source_origin TEXT") }
        try prepareContentStorage()
        contentStorage = try SQLiteContentStorage.shared(at: databaseURL, byteLimit: contentCacheBytes)
        opened = true
    }

    deinit {
        // close_v2 never leaves a handle behind: should a statement still
        // be open, the connection is retired when the last one finalizes
        // instead of failing with SQLITE_BUSY and leaking.
        sqlite3_close_v2(db)
    }

    func load() throws -> [ClipboardItem] { try loadList().map { try $0.materialized() } }

    func loadList() throws -> [ClipboardItem] {
        let sql = """
            SELECT c.id, c.kind, c.text, c.link, c.image_ref, c.rtf_ref, c.files, c.source_app, c.source_bundle,
                   o.copied_at_ms, o.is_pinned, c.source_origin, p.metadata, g.data, d.source_id, bi.size, br.size
            FROM ordering o JOIN content c ON c.id = o.id LEFT JOIN pin_details p ON p.id = c.id LEFT JOIN split_groups g ON g.id = c.id LEFT JOIN split_origins d ON d.id = c.id
            LEFT JOIN binary_content bi ON bi.key = c.image_ref LEFT JOIN binary_content br ON br.key = c.rtf_ref
            ORDER BY o.position ASC
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw HistoryStoreError.unreadable(lastMessage())
        }
        defer { sqlite3_finalize(statement) }
        var items: [ClipboardItem] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            if let item = try item(from: statement) {
                items.append(item)
            }
            status = sqlite3_step(statement)
        }
        // A scan cut short by an error — a schema that changed underneath,
        // a damaged page — must not pass for a shorter history: the next
        // save would persist the loss.
        guard status == SQLITE_DONE else {
            throw HistoryStoreError.unreadable(lastMessage())
        }
        return items
    }

    func save(_ items: [ClipboardItem], changedContentIDs: Set<UUID>? = nil) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try saveContent(items, changedContentIDs: changedContentIDs)
            try savePinnedMetadata(items)
            try saveSplitGroups(items)
            try saveSplitOrigins(items)
            try execute("DELETE FROM ordering")
            try insertOrdering(items)
            try execute("DELETE FROM content WHERE id NOT IN (SELECT id FROM ordering)")
            try collectUnusedContent()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    // MARK: - Rows

    // One statement per batch. The NULL-safe comparison allows edits and
    // RTF removal without rewriting unchanged blobs on reorder/pin saves.
    private func saveContent(_ items: [ClipboardItem], changedContentIDs: Set<UUID>?) throws {
        lastContentWriteIDs = []
        guard changedContentIDs?.isEmpty != true else { return }
        let sql = """
            INSERT INTO content
            (id, kind, text, link, image_ref, rtf_ref, files, source_app, source_bundle, source_origin)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                kind = excluded.kind, text = excluded.text, link = excluded.link,
                image_ref = excluded.image_ref, rtf_ref = excluded.rtf_ref, files = excluded.files,
                source_app = excluded.source_app, source_bundle = excluded.source_bundle,
                source_origin = excluded.source_origin
            WHERE content.kind IS NOT excluded.kind
                OR content.text IS NOT excluded.text OR content.link IS NOT excluded.link
                OR content.image_ref IS NOT excluded.image_ref OR content.rtf_ref IS NOT excluded.rtf_ref
                OR content.files IS NOT excluded.files OR content.source_app IS NOT excluded.source_app
                OR content.source_bundle IS NOT excluded.source_bundle
                OR content.source_origin IS NOT excluded.source_origin
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw HistoryStoreError.unwritable(lastMessage())
        }
        defer { sqlite3_finalize(statement) }
        for item in items {
            guard changedContentIDs?.contains(item.id) ?? true else { continue }
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bindContent(of: item, to: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw HistoryStoreError.unwritable(lastMessage())
            }
            lastContentWriteIDs.append(item.id)
        }
    }

    private func bindContent(of item: ClipboardItem, to statement: OpaquePointer?) throws {
        bindText(statement, 1, item.id.uuidString)
        switch item.payload {
        case .text(let value):
            bindText(statement, 2, "text")
            bindText(statement, 3, value)
        case .link(let url):
            bindText(statement, 2, "link")
            bindText(statement, 4, url.absoluteString)
        case .image(let data):
            bindText(statement, 2, "image")
            bindText(statement, 5, try insertBinary(.inline(data)))
        case .storedImage(let reference):
            bindText(statement, 2, "image")
            bindText(statement, 5, try insertBinary(.stored(reference)))
        case .fileReferences(let paths):
            bindText(statement, 2, "files")
            if let encoded = try? JSONEncoder().encode(paths) {
                bindText(statement, 7, String(decoding: encoded, as: UTF8.self))
            }
        }
        if let richText = item.richText {
            bindText(statement, 6, try insertBinary(richText))
        }
        if let name = item.source?.name {
            bindText(statement, 8, name)
        }
        if let bundleID = item.source?.bundleID {
            bindText(statement, 9, bundleID)
        }
        if item.source?.origin == .handoffMarker { bindText(statement, 10, SourceApp.Origin.handoffMarker.rawValue) }
    }

    private func saveSplitOrigins(_ items: [ClipboardItem]) throws {
        guard items.contains(where: { $0.splitSourceID != nil }) else {
            return try execute("DELETE FROM split_origins")
        }
        var upsert: OpaquePointer?
        guard
            sqlite3_prepare_v2(
                db,
                "INSERT INTO split_origins (id, source_id) VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET source_id = excluded.source_id WHERE split_origins.source_id IS NOT excluded.source_id",
                -1, &upsert, nil) == SQLITE_OK
        else {
            throw HistoryStoreError.unwritable(lastMessage())
        }
        defer { sqlite3_finalize(upsert) }
        var ids: [String] = []
        for item in items {
            guard let origin = item.splitSourceID else { continue }
            let id = item.id.uuidString
            ids.append(id)
            sqlite3_reset(upsert)
            bindText(upsert, 1, id)
            bindText(upsert, 2, origin.uuidString)
            guard sqlite3_step(upsert) == SQLITE_DONE else { throw HistoryStoreError.unwritable(lastMessage()) }
        }
        try pruneDetails(in: "split_origins", keeping: ids)
    }

    private func saveSplitGroups(_ items: [ClipboardItem]) throws {
        guard items.contains(where: { $0.splitGroup != nil }) else {
            return try execute("DELETE FROM split_groups")
        }
        var upsert: OpaquePointer?
        guard
            sqlite3_prepare_v2(
                db,
                "INSERT INTO split_groups (id, data) VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET data = excluded.data WHERE split_groups.data IS NOT excluded.data",
                -1, &upsert, nil) == SQLITE_OK
        else {
            throw HistoryStoreError.unwritable(lastMessage())
        }
        defer { sqlite3_finalize(upsert) }
        var ids: [String] = []
        for item in items {
            guard let group = item.splitGroup else { continue }
            guard group.isValid else { throw HistoryStoreError.unwritable("invalid split group") }
            let id = item.id.uuidString
            ids.append(id)
            sqlite3_reset(upsert)
            bindText(upsert, 1, id)
            let encoded = try encodeGroup(group)
            bindBlob(upsert, 2, encoded.data)
            guard sqlite3_step(upsert) == SQLITE_DONE else { throw HistoryStoreError.unwritable(lastMessage()) }
            if sqlite3_changes(db) > 0 { try saveGroupLinks(id: id, keys: encoded.keys) }
        }
        try pruneDetails(in: "split_groups", keeping: ids)
    }

    private func savePinnedMetadata(_ items: [ClipboardItem]) throws {
        guard items.contains(where: { $0.pinnedMetadata != PinnedMetadata() }) else {
            return try execute("DELETE FROM pin_details")
        }
        let sql = """
            INSERT INTO pin_details (id, metadata) VALUES (?, ?)
            ON CONFLICT(id) DO UPDATE SET metadata = excluded.metadata
            WHERE pin_details.metadata IS NOT excluded.metadata
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw HistoryStoreError.unwritable(lastMessage())
        }
        defer { sqlite3_finalize(statement) }
        var ids: [String] = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        for item in items where item.pinnedMetadata != PinnedMetadata() {
            let id = item.id.uuidString
            ids.append(id)
            sqlite3_reset(statement)
            bindText(statement, 1, id)
            // Set ordering is not stable; use an explicit representation for conditional updates.
            let record = StoredPinDetails(
                note: item.pinnedMetadata.note, hidden: item.pinnedMetadata.hidesContent,
                tags: item.pinnedMetadata.tags.map(\.rawValue).sorted())
            bindText(statement, 2, String(decoding: try encoder.encode(record), as: UTF8.self))
            guard sqlite3_step(statement) == SQLITE_DONE else { throw HistoryStoreError.unwritable(lastMessage()) }
        }
        try pruneDetails(in: "pin_details", keeping: ids)
    }

    // The snapshot is authoritative inside BEGIN IMMEDIATE, including details
    // cleared by this save or written by another connection. Bind one JSON
    // array of the sparse metadata IDs rather than a variable per history row.
    private func pruneDetails(in table: String, keeping ids: [String]) throws {
        var deletion: OpaquePointer?
        let sql = "DELETE FROM \(table) WHERE id NOT IN (SELECT value FROM json_each(?))"
        guard sqlite3_prepare_v2(db, sql, -1, &deletion, nil) == SQLITE_OK else {
            throw HistoryStoreError.unwritable(lastMessage())
        }
        defer { sqlite3_finalize(deletion) }
        bindText(deletion, 1, String(decoding: try JSONEncoder().encode(ids), as: UTF8.self))
        guard sqlite3_step(deletion) == SQLITE_DONE else { throw HistoryStoreError.unwritable(lastMessage()) }
    }

    private struct StoredPinDetails: Codable {
        let note: String
        let hidden: Bool
        let tags: [String]
        var metadata: PinnedMetadata {
            PinnedMetadata(note: note, hidesContent: hidden, tags: Set(tags.compactMap(PinTagColor.init(rawValue:))))
        }
    }

    private func insertOrdering(_ items: [ClipboardItem]) throws {
        let sql = "INSERT INTO ordering (id, position, copied_at_ms, is_pinned) VALUES (?, ?, ?, ?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw HistoryStoreError.unwritable(lastMessage())
        }
        defer { sqlite3_finalize(statement) }
        for (position, item) in items.enumerated() {
            sqlite3_reset(statement)
            bindText(statement, 1, item.id.uuidString)
            sqlite3_bind_int64(statement, 2, Int64(position))
            sqlite3_bind_int64(statement, 3, Int64((item.copiedAt.timeIntervalSince1970 * 1000).rounded()))
            sqlite3_bind_int64(statement, 4, item.isPinned ? 1 : 0)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw HistoryStoreError.unwritable(lastMessage())
            }
        }
    }

    private func item(from statement: OpaquePointer?) throws -> ClipboardItem? {
        guard let idText = columnText(statement, 0), let id = UUID(uuidString: idText),
            let kind = columnText(statement, 1)
        else { return nil }
        let payload: Payload
        switch kind {
        case "text":
            guard let text = columnText(statement, 2) else { return nil }
            payload = .text(text)
        case "link":
            guard let link = columnText(statement, 3), let url = URL(string: link) else { return nil }
            payload = .link(url)
        case "image":
            guard let key = columnText(statement, 4), sqlite3_column_type(statement, 15) != SQLITE_NULL else {
                throw HistoryStoreError.unreadable("image original is missing")
            }
            payload = .storedImage(
                contentStorage.reference(key: key, byteCount: Int(sqlite3_column_int64(statement, 15))))
        case "files":
            guard let encoded = columnText(statement, 6),
                let paths = try? JSONDecoder().decode([String].self, from: Data(encoded.utf8))
            else { return nil }
            payload = .fileReferences(paths)
        default:
            return nil
        }
        let group: SplitGroup?
        if let data = columnBlob(statement, 13) {
            group = try decodeGroup(data)
        } else {
            group = nil
        }
        let metadata: PinnedMetadata
        if let encoded = columnText(statement, 12) {
            guard let decoded = try? JSONDecoder().decode(StoredPinDetails.self, from: Data(encoded.utf8)) else {
                throw HistoryStoreError.unreadable("invalid pinned metadata")
            }
            metadata = decoded.metadata
        } else {
            metadata = PinnedMetadata()
        }
        let richText: BinaryContent?
        if let key = columnText(statement, 5) {
            guard sqlite3_column_type(statement, 16) != SQLITE_NULL else {
                throw HistoryStoreError.unreadable("rich text original is missing")
            }
            richText = .stored(contentStorage.reference(key: key, byteCount: Int(sqlite3_column_int64(statement, 16))))
        } else {
            richText = nil
        }
        return ClipboardItem(
            id: id,
            payload: payload,
            source: SourceApp(
                name: columnText(statement, 7), bundleID: columnText(statement, 8),
                origin: SourceApp.Origin(rawValue: columnText(statement, 11) ?? "") ?? .observedApplication),
            copiedAt: Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 9)) / 1000),
            isPinned: sqlite3_column_int64(statement, 10) == 1,
            pinnedMetadata: metadata, splitGroup: group,
            splitSourceID: columnText(statement, 14).flatMap(UUID.init(uuidString:)), richText: richText
        )
    }

    // MARK: - SQLite helpers

    func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw HistoryStoreError.unwritable(lastMessage())
        }
    }

    func bindText(_ statement: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
    }

    func bindBlob(_ statement: OpaquePointer?, _ index: Int32, _ data: Data) {
        guard !data.isEmpty else {
            sqlite3_bind_zeroblob(statement, index, 0)
            return
        }
        data.withUnsafeBytes { buffer in
            _ = sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(buffer.count), sqliteTransient)
        }
    }

    func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    func columnBlob(_ statement: OpaquePointer?, _ index: Int32) -> Data? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        guard sqlite3_column_bytes(statement, index) > 0 else { return Data() }
        guard let pointer = sqlite3_column_blob(statement, index) else { return nil }
        return Data(bytes: pointer, count: Int(sqlite3_column_bytes(statement, index)))
    }

    private func lastMessage() -> String {
        db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown sqlite error"
    }
}

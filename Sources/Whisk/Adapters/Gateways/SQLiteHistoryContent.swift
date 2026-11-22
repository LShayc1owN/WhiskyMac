import Foundation
import SQLite3

extension SQLiteHistoryStore {
    struct StoredGroup: Codable {
        var version = 1
        let parts: [Part]
        let plainText: Bool
        struct Part: Codable {
            let id: UUID
            let text: String
            let link: URL?
            let rtfKey: String?
            let rtfSize: Int?
        }
    }

    /// Transactional, bounded migration: at most one legacy item/group is
    /// materialized at a time, never an entire library of binary payloads.
    func prepareContentStorage() throws {
        var schema: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(content)", -1, &schema, nil) == SQLITE_OK else {
            throw HistoryStoreError.unreadable("cannot inspect content schema")
        }
        var columns: Set<String> = []
        while sqlite3_step(schema) == SQLITE_ROW { if let name = columnText(schema, 1) { columns.insert(name) } }
        sqlite3_finalize(schema)
        // A schema missing old required fields must still fail validation,
        // rather than being silently "repaired" into an empty history.
        guard
            columns.isSuperset(of: [
                "id", "kind", "text", "link", "image", "rtf", "files", "source_app", "source_bundle",
            ])
        else {
            throw HistoryStoreError.unreadable("incomplete content schema")
        }
        try execute("BEGIN IMMEDIATE")
        do {
            if !columns.contains("image_ref") { try execute("ALTER TABLE content ADD COLUMN image_ref TEXT") }
            if !columns.contains("rtf_ref") { try execute("ALTER TABLE content ADD COLUMN rtf_ref TEXT") }
            try execute(
                "CREATE TABLE IF NOT EXISTS binary_content (key TEXT PRIMARY KEY, data BLOB NOT NULL, size INTEGER NOT NULL)"
            )
            try execute(
                "CREATE TABLE IF NOT EXISTS split_blob_links (id TEXT NOT NULL, key TEXT NOT NULL, PRIMARY KEY(id, key))"
            )
            var legacy: OpaquePointer?
            guard
                sqlite3_prepare_v2(
                    db, "SELECT id, image, rtf FROM content WHERE image IS NOT NULL OR rtf IS NOT NULL", -1, &legacy,
                    nil) == SQLITE_OK
            else {
                throw HistoryStoreError.unreadable("cannot migrate originals")
            }
            defer { sqlite3_finalize(legacy) }
            var status = sqlite3_step(legacy)
            while status == SQLITE_ROW {
                try autoreleasepool {
                    guard let id = columnText(legacy, 0) else {
                        throw HistoryStoreError.unreadable("invalid content identity")
                    }
                    let image = try columnBlob(legacy, 1).map { try insertBinary(.inline($0)) }
                    let rtf = try columnBlob(legacy, 2).map { try insertBinary(.inline($0)) }
                    var update: OpaquePointer?
                    guard
                        sqlite3_prepare_v2(
                            db, "UPDATE content SET image_ref = ?, rtf_ref = ?, image = NULL, rtf = NULL WHERE id = ?",
                            -1, &update, nil) == SQLITE_OK
                    else {
                        throw HistoryStoreError.unwritable("cannot migrate content references")
                    }
                    defer { sqlite3_finalize(update) }
                    if let image { bindText(update, 1, image) }
                    if let rtf { bindText(update, 2, rtf) }
                    bindText(update, 3, id)
                    guard sqlite3_step(update) == SQLITE_DONE else {
                        throw HistoryStoreError.unwritable("original migration failed")
                    }
                }
                status = sqlite3_step(legacy)
            }
            guard status == SQLITE_DONE else { throw HistoryStoreError.unreadable("incomplete original migration") }
            try migrateSplitGroups()
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }

    func insertBinary(_ content: BinaryContent) throws -> String {
        if let reference = content.reference, try hasBinary(reference.key, size: reference.byteCount) {
            return reference.key
        }
        let data = try content.read()
        let key = SQLiteContentStorage.digest(data)
        var statement: OpaquePointer?
        guard
            sqlite3_prepare_v2(
                db, "INSERT OR IGNORE INTO binary_content(key, data, size) VALUES (?, ?, ?)", -1, &statement, nil)
                == SQLITE_OK
        else {
            throw HistoryStoreError.unwritable("cannot prepare original content save")
        }
        defer { sqlite3_finalize(statement) }
        bindText(statement, 1, key); bindBlob(statement, 2, data)
        sqlite3_bind_int64(statement, 3, Int64(data.count))
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw HistoryStoreError.unwritable("cannot save original content")
        }
        return key
    }

    private func hasBinary(_ key: String, size: Int) throws -> Bool {
        var statement: OpaquePointer?
        guard
            sqlite3_prepare_v2(db, "SELECT size, LENGTH(data) FROM binary_content WHERE key = ?", -1, &statement, nil)
                == SQLITE_OK
        else {
            throw HistoryStoreError.unreadable("cannot inspect original content")
        }
        defer { sqlite3_finalize(statement) }
        bindText(statement, 1, key)
        let status = sqlite3_step(statement)
        if status == SQLITE_DONE { return false }
        guard status == SQLITE_ROW, size >= 0, key.count == 64,
            sqlite3_column_int64(statement, 0) == size, sqlite3_column_int64(statement, 1) == size
        else {
            throw HistoryStoreError.unreadable("original size mismatch")
        }
        return true
    }

    func encodeGroup(_ group: SplitGroup) throws -> (data: Data, keys: Set<String>) {
        let parts = try group.parts.map { part in
            StoredGroup.Part(
                id: part.id, text: part.text, link: part.link,
                rtfKey: try part.richText.map(insertBinary), rtfSize: part.richText?.byteCount)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return (
            try encoder.encode(StoredGroup(parts: parts, plainText: group.plainText)), Set(parts.compactMap(\.rtfKey))
        )
    }

    private func migrateSplitGroups() throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT id, data FROM split_groups", -1, &statement, nil) == SQLITE_OK else {
            throw HistoryStoreError.unreadable("cannot migrate split formatting")
        }
        defer { sqlite3_finalize(statement) }
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            try autoreleasepool {
                guard let id = columnText(statement, 0), let data = columnBlob(statement, 1) else {
                    throw HistoryStoreError.unreadable("invalid split group")
                }
                if (try? JSONDecoder().decode(StoredGroup.self, from: data)) != nil { return }
                let group = try JSONDecoder().decode(SplitGroup.self, from: data)
                guard group.isValid else { throw HistoryStoreError.unreadable("invalid split group") }
                let encoded = try encodeGroup(group)
                var update: OpaquePointer?
                guard
                    sqlite3_prepare_v2(db, "UPDATE split_groups SET data = ? WHERE id = ?", -1, &update, nil)
                        == SQLITE_OK
                else {
                    throw HistoryStoreError.unwritable("cannot migrate split group")
                }
                defer { sqlite3_finalize(update) }
                bindBlob(update, 1, encoded.data); bindText(update, 2, id)
                guard sqlite3_step(update) == SQLITE_DONE else {
                    throw HistoryStoreError.unwritable("cannot migrate split formatting")
                }
                try saveGroupLinks(id: id, keys: encoded.keys)
            }
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw HistoryStoreError.unreadable("incomplete split migration") }
    }

    func decodeGroup(_ data: Data) throws -> SplitGroup {
        let record = try JSONDecoder().decode(StoredGroup.self, from: data)
        guard record.version == 1 else { throw HistoryStoreError.unreadable("unsupported split content") }
        let parts = try record.parts.map { part -> SplitPart in
            let richText: BinaryContent?
            guard (part.rtfKey == nil) == (part.rtfSize == nil) else {
                throw HistoryStoreError.unreadable("incomplete split formatting reference")
            }
            if let key = part.rtfKey {
                guard let size = part.rtfSize, try hasBinary(key, size: size) else {
                    throw HistoryStoreError.unreadable("missing split formatting")
                }
                richText = .stored(contentStorage.reference(key: key, byteCount: size))
            } else {
                richText = nil
            }
            return SplitPart(id: part.id, text: part.text, link: part.link, rtf: nil, richText: richText)
        }
        let group = SplitGroup(parts: parts, plainText: record.plainText)
        guard group.isValid else { throw HistoryStoreError.unreadable("invalid split group") }
        return group
    }

    func saveGroupLinks(id: String, keys: Set<String>) throws {
        var deletion: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM split_blob_links WHERE id = ?", -1, &deletion, nil) == SQLITE_OK
        else {
            throw HistoryStoreError.unwritable("cannot update split references")
        }
        defer { sqlite3_finalize(deletion) }
        bindText(deletion, 1, id)
        guard sqlite3_step(deletion) == SQLITE_DONE else {
            throw HistoryStoreError.unwritable("cannot remove split references")
        }
        var insert: OpaquePointer?
        guard
            sqlite3_prepare_v2(db, "INSERT OR IGNORE INTO split_blob_links(id, key) VALUES (?, ?)", -1, &insert, nil)
                == SQLITE_OK
        else {
            throw HistoryStoreError.unwritable("cannot save split references")
        }
        defer { sqlite3_finalize(insert) }
        for key in keys {
            sqlite3_reset(insert); sqlite3_clear_bindings(insert)
            bindText(insert, 1, id); bindText(insert, 2, key)
            guard sqlite3_step(insert) == SQLITE_DONE else {
                throw HistoryStoreError.unwritable("cannot save split reference")
            }
        }
    }

    /// Undo and active views retain revision handles. Delete only revisions
    /// absent from both live handles and the committed library.
    func collectUnusedContent() throws {
        let retained = contentStorage.retainedReferences()
        try execute("CREATE TEMP TABLE IF NOT EXISTS retained_binary (key TEXT PRIMARY KEY)")
        try execute("DELETE FROM retained_binary")
        var insert: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR IGNORE INTO retained_binary VALUES (?)", -1, &insert, nil) == SQLITE_OK
        else {
            throw HistoryStoreError.unwritable("cannot protect undo revisions")
        }
        defer { sqlite3_finalize(insert) }
        for reference in retained {
            sqlite3_reset(insert); bindText(insert, 1, reference.key)
            guard sqlite3_step(insert) == SQLITE_DONE else {
                throw HistoryStoreError.unwritable("cannot retain revision")
            }
        }
        try execute("DELETE FROM split_blob_links WHERE id NOT IN (SELECT id FROM split_groups)")
        try withExtendedLifetime(retained) {
            try execute(
                """
                DELETE FROM binary_content WHERE key NOT IN (
                    SELECT image_ref FROM content WHERE image_ref IS NOT NULL
                    UNION SELECT rtf_ref FROM content WHERE rtf_ref IS NOT NULL
                    UNION SELECT key FROM split_blob_links
                    UNION SELECT key FROM retained_binary)
                """)
        }
    }

    func compact(_ items: [ClipboardItem]) throws -> [ClipboardItem] {
        var compacted = items
        for (index, item) in items.enumerated() {
            let inlineImage: Bool
            if case .image = item.payload { inlineImage = true } else { inlineImage = false }
            let inlineRTF = item.richText != nil && item.richText?.reference == nil
            let inlineParts =
                item.splitGroup?.parts.contains { $0.richText != nil && $0.richText?.reference == nil } ?? false
            guard inlineImage || inlineRTF || inlineParts else { continue }
            var statement: OpaquePointer?
            guard
                sqlite3_prepare_v2(
                    db,
                    """
                    SELECT c.image_ref, bi.size, c.rtf_ref, br.size, g.data
                    FROM content c LEFT JOIN binary_content bi ON bi.key=c.image_ref
                    LEFT JOIN binary_content br ON br.key=c.rtf_ref
                    LEFT JOIN split_groups g ON g.id=c.id WHERE c.id=?
                    """, -1, &statement, nil) == SQLITE_OK
            else {
                throw HistoryStoreError.unreadable("cannot prepare saved references")
            }
            defer { sqlite3_finalize(statement) }
            bindText(statement, 1, item.id.uuidString)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw HistoryStoreError.unreadable("saved entry is missing")
            }
            var payload = item.payload
            var richText = item.richText
            if let key = columnText(statement, 0) {
                payload = .storedImage(
                    contentStorage.reference(key: key, byteCount: Int(sqlite3_column_int64(statement, 1))))
            }
            if let key = columnText(statement, 2) {
                richText = .stored(
                    contentStorage.reference(key: key, byteCount: Int(sqlite3_column_int64(statement, 3))))
            }
            let group = try columnBlob(statement, 4).map(decodeGroup)
            compacted[index] = item.withStoredContent(payload: payload, richText: richText, splitGroup: group)
        }
        return compacted
    }

    func setContentCacheEnabled(_ enabled: Bool) { contentStorage.setEnabled(enabled) }

    func releaseContentCache() { contentStorage.clear(); sqlite3_db_release_memory(db) }
}

extension SQLiteHistoryStore {
    /// Hash a newly captured image/RTF once, rather than once per candidate.
    func duplicateMatcher(payload: Payload, rtf: Data?) -> (ClipboardItem) -> Bool {
        let imageKey: String?
        if case .image(let data) = payload {
            imageKey = SQLiteContentStorage.digest(data)
        } else if case .storedImage(let reference) = payload {
            imageKey = reference.key
        } else {
            imageKey = nil
        }
        let rtfKey = rtf.map(SQLiteContentStorage.digest)
        return { item in
            let payloadMatches: Bool
            if let imageKey, case .storedImage(let reference) = item.payload {
                payloadMatches = reference.key == imageKey
            } else {
                payloadMatches = item.payload == payload
            }
            guard payloadMatches else { return false }
            if let reference = item.richText?.reference { return reference.key == rtfKey }
            return item.richText == rtf.map(BinaryContent.inline)
        }
    }
}

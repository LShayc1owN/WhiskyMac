// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

/// Type-erased history store: the composition root picks a gateway at
/// launch without changing the controller's type.
struct AnyHistoryStore: HistoryStore {
    private let matchItem: (Payload, Data?) -> (ClipboardItem) -> Bool
    private let listItems: () throws -> [ClipboardItem]
    private let compactItems: ([ClipboardItem]) throws -> [ClipboardItem]
    private let clearContent: () -> Void
    private let enableContent: (Bool) -> Void
    private let loadItems: () throws -> [ClipboardItem]
    private let saveItems: ([ClipboardItem], Set<UUID>?) throws -> Void

    init<Store: HistoryStore>(_ store: Store) {
        matchItem = store.duplicateMatcher
        listItems = store.loadList
        compactItems = store.compact
        clearContent = store.releaseContentCache
        enableContent = store.setContentCacheEnabled
        loadItems = store.load
        saveItems = store.save
    }

    func load() throws -> [ClipboardItem] { try loadItems() }
    func duplicateMatcher(payload: Payload, rtf: Data?) -> (ClipboardItem) -> Bool { matchItem(payload, rtf) }
    func loadList() throws -> [ClipboardItem] { try listItems() }
    func compact(_ items: [ClipboardItem]) throws -> [ClipboardItem] { try compactItems(items) }
    func releaseContentCache() { clearContent() }
    func setContentCacheEnabled(_ enabled: Bool) { enableContent(enabled) }

    func save(_ items: [ClipboardItem], changedContentIDs: Set<UUID>?) throws {
        try saveItems(items, changedContentIDs)
    }
}

/// Opens the production history store without ever refusing to launch. A
/// database that will not open is set aside for inspection and a fresh
/// one takes its place; should that fail too, the session runs in memory.
enum HistoryStorage {
    /// The validated startup snapshot travels to the controller with its
    /// store. The store's closures never retain this snapshot.
    struct OpenedHistory {
        let store: AnyHistoryStore
        let items: [ClipboardItem]
    }

    static let databaseName = "history.sqlite"
    static let unreadableSuffix = ".unreadable"
    static let legacyIndexName = "history.json"
    static let retiredSuffix = ".migrated"

    /// The May development directory, unless a dedicated test path is set.
    static func defaultDirectory(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        try AppIdentity.dataDirectory(fileManager: fileManager, environment: environment)
    }

    static func open(
        in directory: URL,
        fileManager: FileManager = .default,
        log: (DiagnosticEvent) -> Void = { ConsoleLogger().log($0) }
    ) -> AnyHistoryStore {
        openAndLoad(in: directory, fileManager: fileManager, log: log).store
    }

    static func openAndLoad(
        in directory: URL,
        fileManager: FileManager = .default,
        makeStore: (URL) throws -> AnyHistoryStore = { AnyHistoryStore(try SQLiteHistoryStore(databaseURL: $0)) },
        log: (DiagnosticEvent) -> Void = { ConsoleLogger().log($0) }
    ) -> OpenedHistory {
        let databaseURL = directory.appendingPathComponent(databaseName)
        let opened: OpenedHistory
        do {
            opened = try openReadable(databaseURL, makeStore: makeStore)
        } catch {
            log(.historyDatabaseSetAside)
            setAside(databaseURL, fileManager: fileManager)
            do {
                opened = try openReadable(databaseURL, makeStore: makeStore)
            } catch {
                log(.historyDatabaseCreateFailed)
                return OpenedHistory(store: AnyHistoryStore(VolatileHistoryStore()), items: [])
            }
        }
        return importLegacyHistory(in: directory, into: opened, fileManager: fileManager, log: log)
    }

    /// A database is trusted only once it has been read: one that opens
    /// but will not load — a drifted schema, a damaged page — would start
    /// the session empty and let the first save overwrite it.
    private static func openReadable(
        _ databaseURL: URL, makeStore: (URL) throws -> AnyHistoryStore
    ) throws -> OpenedHistory {
        let store = try makeStore(databaseURL)
        return OpenedHistory(store: store, items: try store.loadList())
    }

    /// Imports the JSON history of earlier versions, merging it behind
    /// whatever the database already holds. The legacy files are retired
    /// only once the import is stored: a failed import leaves them in
    /// place, so the next launch tries again instead of starting empty.
    private static func importLegacyHistory(
        in directory: URL, into opened: OpenedHistory, fileManager: FileManager, log: (DiagnosticEvent) -> Void
    ) -> OpenedHistory {
        let legacyIndex = directory.appendingPathComponent(legacyIndexName)
        guard fileManager.fileExists(atPath: legacyIndex.path) else { return opened }
        let merged: [ClipboardItem]
        let compacted: [ClipboardItem]
        do {
            let legacy = try LegacyJSONHistory(directory: directory, fileManager: fileManager).load()
            let current = opened.items
            let known = Set(current.map(\.id))
            merged = current + legacy.filter { !known.contains($0.id) }
            try opened.store.save(merged)
            compacted = try opened.store.compact(merged)
        } catch {
            log(.legacyHistoryImportFailed)
            return opened
        }
        do {
            try fileManager.moveItem(
                at: legacyIndex, to: directory.appendingPathComponent(legacyIndexName + retiredSuffix))
            let blobs = directory.appendingPathComponent("blobs", isDirectory: true)
            if fileManager.fileExists(atPath: blobs.path) {
                try fileManager.removeItem(at: blobs)
            }
        } catch {
            log(.legacyHistoryRetireFailed)
        }
        return OpenedHistory(store: opened.store, items: compacted)
    }

    // Best effort by design: a move that fails leaves the file where the
    // retry will trip over it again, and that failure is the one logged.
    private static func setAside(_ databaseURL: URL, fileManager: FileManager) {
        for sidecar in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: databaseURL.path + sidecar)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = URL(fileURLWithPath: databaseURL.path + unreadableSuffix + sidecar)
            try? fileManager.removeItem(at: destination)
            try? fileManager.moveItem(at: source, to: destination)
        }
    }
}

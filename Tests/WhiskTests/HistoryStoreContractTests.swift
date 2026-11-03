// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation
import SQLite3
import Testing

@testable import Whisk

/// Every gateway of the `HistoryStore` port. The contract below runs
/// against each of them in a fresh temporary directory; what is specific
/// to one format has its own suite further down.
enum StoreGateway: CaseIterable {
    case sqlite
    case volatile

    /// Gateways whose history outlives the instance that saved it.
    static let persistent: [StoreGateway] = [.sqlite]
}

private struct StoreHarness {
    let gateway: StoreGateway
    let directory: URL

    init(_ gateway: StoreGateway) {
        self.gateway = gateway
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisk-tests-\(UUID().uuidString)", isDirectory: true)
    }

    var databaseURL: URL { directory.appendingPathComponent("history.sqlite") }

    /// A store over this harness's files; a second call models a relaunch.
    func makeStore() throws -> any HistoryStore {
        switch gateway {
        case .sqlite: return try SQLiteHistoryStore(databaseURL: databaseURL)
        case .volatile: return VolatileHistoryStore()
        }
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private func date(ms: Int64) -> Date {
    Date(timeIntervalSince1970: Double(ms) / 1000)
}

private func sampleItems() throws -> [ClipboardItem] {
    let url = try #require(URL(string: "https://example.com/a?b=c"))
    return [
        ClipboardItem(
            id: UUID(), payload: .text("héllo\nworld"),
            source: SourceApp(name: "Safari", bundleID: "com.apple.Safari"),
            copiedAt: date(ms: 1_700_000_000_123), isPinned: true, rtf: Data("rich".utf8)),
        ClipboardItem(
            id: UUID(), payload: .link(url), source: nil,
            copiedAt: date(ms: 1_700_000_001_456), isPinned: false),
        ClipboardItem(
            id: UUID(), payload: .image(Data([0x89, 0x50, 0x4E, 0x47])),
            source: SourceApp(name: "Preview", bundleID: "com.apple.Preview"),
            copiedAt: date(ms: 1_700_000_002_789), isPinned: false),
        ClipboardItem(
            id: UUID(), payload: .fileReferences(["/tmp/a.txt", "/tmp/b.txt"]),
            source: SourceApp(name: "Finder", bundleID: "com.apple.finder"),
            copiedAt: date(ms: 1_700_000_003_000), isPinned: true),
    ]
}

@Suite struct HistoryStoreContract {
    @Test(arguments: StoreGateway.allCases)
    func a_saved_history_loads_back_identically(_ gateway: StoreGateway) throws {
        let harness = StoreHarness(gateway)
        defer { harness.tearDown() }
        let store = try harness.makeStore()
        let items = try sampleItems()

        try store.save(items)
        #expect(try store.load() == items)

        let reordered = [items[2], items[0]]
        try store.save(reordered)
        #expect(try store.load() == reordered)
    }

    @Test(arguments: StoreGateway.allCases)
    func loading_before_any_save_yields_no_items(_ gateway: StoreGateway) throws {
        let harness = StoreHarness(gateway)
        defer { harness.tearDown() }

        #expect(try harness.makeStore().load().isEmpty)
    }

    @Test(arguments: StoreGateway.allCases)
    func saving_a_subset_forgets_the_rest(_ gateway: StoreGateway) throws {
        let harness = StoreHarness(gateway)
        defer { harness.tearDown() }
        let store = try harness.makeStore()
        let items = try sampleItems()

        try store.save(items)
        try store.save([items[0]])

        #expect(try store.load() == [items[0]])
    }

    @Test(arguments: StoreGateway.persistent)
    func a_saved_history_survives_a_relaunch(_ gateway: StoreGateway) throws {
        let harness = StoreHarness(gateway)
        defer { harness.tearDown() }
        let items = try sampleItems()

        try harness.makeStore().save(items)

        #expect(try harness.makeStore().load() == items)
    }

    @Test(arguments: StoreGateway.allCases)
    func same_id_content_changes_replace_old_columns_and_can_be_restored(_ gateway: StoreGateway) throws {
        let harness = StoreHarness(gateway)
        defer { harness.tearDown() }
        let store = try harness.makeStore()
        let original = try sampleItems()[0]
        try store.save([original])
        let link = original.replacing(payload: .link(try #require(URL(string: "https://example.com/edited"))))

        try store.save([link])
        #expect(try store.load() == [link])
        try store.save([original])
        #expect(try store.load() == [original])

        let newFormat = ClipboardItem(
            id: original.id, payload: original.payload, source: nil, copiedAt: original.copiedAt,
            isPinned: original.isPinned, rtf: Data("new format".utf8))
        try store.save([newFormat])
        #expect(try store.load() == [newFormat])
    }

    @Test func sqlite_edit_and_undo_survive_closed_connections() throws {
        let harness = StoreHarness(.sqlite)
        defer { harness.tearDown() }
        let original = History(items: try sampleItems())
        let id = original.items[0].id
        try harness.makeStore().save(original.items)

        let edited = try EditItem(store: SQLiteHistoryStore(databaseURL: harness.databaseURL))(
            id, text: "func edited() {}", in: original)

        #expect(try harness.makeStore().load() == edited.items)
        #expect(edited.items[0].rtf == nil)
        _ = try RestoreHistory(store: SQLiteHistoryStore(databaseURL: harness.databaseURL))(original)
        #expect(try harness.makeStore().load() == original.items)
    }

    @Test(arguments: StoreGateway.allCases)
    func empty_rtf_is_distinct_from_absent_rtf(_ gateway: StoreGateway) throws {
        let harness = StoreHarness(gateway)
        defer { harness.tearDown() }
        let store = try harness.makeStore()
        let item = ClipboardItem(
            id: UUID(), payload: .text("hello"), source: nil, copiedAt: date(ms: 1_700_000_000_000),
            isPinned: false, rtf: Data())
        try store.save([item])
        #expect(try store.load() == [item])
        let plain = item.replacing(payload: item.payload)
        try store.save([plain])
        #expect(try store.load() == [plain])
    }

    @Test func captured_format_versions_survive_relaunch_and_write_the_selected_format() throws {
        let harness = StoreHarness(.sqlite)
        defer { harness.tearDown() }
        let board = ScriptedPasteboard()
        let clock = FakeClock()
        let formats: [Data?] = [Data("format A".utf8), Data("format B".utf8), nil]
        var history = History()
        for format in formats {
            board.pendingSnapshots = [PasteboardSnapshot(payload: .text("hello"), source: nil, rtf: format)]
            history = try CaptureClipboardChange(
                pasteboard: board, clock: clock, store: SQLiteHistoryStore(databaseURL: harness.databaseURL)
            )(into: history)
            clock.advance(by: 1)
        }
        let loaded = try harness.makeStore().load()
        #expect(loaded == history.items)
        #expect(loaded.map(\.rtf) == Array(formats.reversed()))
        for item in loaded {
            _ = try SelectItem(
                pasteboard: board, clock: clock, store: SQLiteHistoryStore(databaseURL: harness.databaseURL)
            )(item.id, in: History(items: loaded))
            #expect(board.writtenRTF.last == .some(item.rtf))
        }
    }
}

@Suite struct SQLiteHistoryStoreSpecifics {
    @Test func reorder_recency_and_pin_saves_never_update_unchanged_content() throws {
        let harness = StoreHarness(.sqlite)
        defer { harness.tearDown() }
        let store = try harness.makeStore()
        let items = try sampleItems()
        try store.save(items)
        try sabotage(
            harness.databaseURL,
            "CREATE TRIGGER refuse_update BEFORE UPDATE ON content BEGIN SELECT RAISE(ABORT, 'content rewritten'); END")

        let reordered = [items[1].copied(at: date(ms: 1_800_000_000_000)), items[0].pinToggled(), items[2], items[3]]
        try store.save(reordered)

        #expect(try store.load() == reordered)
    }

    @Test func a_failed_content_update_rolls_back_content_and_ordering() throws {
        let harness = StoreHarness(.sqlite)
        defer { harness.tearDown() }
        let store = try harness.makeStore()
        let items = try sampleItems()
        try store.save(items)
        // Content is updated first; the later ordering failure must undo it.
        try sabotage(
            harness.databaseURL,
            "CREATE TRIGGER refuse BEFORE INSERT ON ordering BEGIN SELECT RAISE(ABORT, 'refused'); END")

        #expect(throws: HistoryStoreError.self) {
            try store.save([items[0].replacing(payload: .text("changed")), items[1]])
        }
        #expect(try harness.makeStore().load() == items)
    }

    @Test func a_row_with_an_unknown_kind_is_skipped_not_fatal() throws {
        let harness = StoreHarness(.sqlite)
        defer { harness.tearDown() }
        let valid = anItem(.text("valid"))
        try harness.makeStore().save([valid])
        try insertRow(kind: "hologram", into: harness.databaseURL)

        #expect(try harness.makeStore().load() == [valid])
    }

    @Test func a_large_history_saves_and_loads_in_one_pass() throws {
        let harness = StoreHarness(.sqlite)
        defer { harness.tearDown() }
        let store = try harness.makeStore()
        let items = (0..<33_000).map { anItem(.text("item \($0)")) }

        try store.save(items)

        #expect(try store.load() == items)
    }

    @Test func a_writer_waits_for_another_connection_instead_of_failing() throws {
        let harness = StoreHarness(.sqlite)
        defer { harness.tearDown() }
        let store = try harness.makeStore()
        try store.save([anItem(.text("first"))])
        var raw: OpaquePointer?
        guard sqlite3_open(harness.databaseURL.path, &raw) == SQLITE_OK,
            sqlite3_exec(raw, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK
        else { throw RawSQLFailure() }
        let holder = raw
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            sqlite3_exec(holder, "COMMIT", nil, nil, nil)
            sqlite3_close(holder)
        }

        try store.save([anItem(.text("second"))])

        #expect(try store.load().map(\.payload) == [.text("second")])
    }

    @Test func a_file_that_is_not_a_database_fails_to_open() throws {
        let harness = StoreHarness(.sqlite)
        defer { harness.tearDown() }
        try FileManager.default.createDirectory(at: harness.directory, withIntermediateDirectories: true)
        try Data(repeating: 0x42, count: 8192).write(to: harness.databaseURL)

        #expect(throws: HistoryStoreError.self) {
            try SQLiteHistoryStore(databaseURL: harness.databaseURL)
        }
    }

    @Test func a_path_that_is_a_directory_cannot_be_opened() throws {
        let harness = StoreHarness(.sqlite)
        defer { harness.tearDown() }
        try FileManager.default.createDirectory(at: harness.databaseURL, withIntermediateDirectories: true)

        #expect(throws: HistoryStoreError.self) {
            try SQLiteHistoryStore(databaseURL: harness.databaseURL)
        }
    }

    @Test func a_load_without_its_tables_reports_unreadable() throws {
        let harness = StoreHarness(.sqlite)
        defer { harness.tearDown() }
        let store = try harness.makeStore()
        try store.save([anItem(.text("x"))])
        try sabotage(harness.databaseURL, "DROP TABLE ordering")

        #expect(throws: HistoryStoreError.self) { try store.load() }
    }

    @Test func a_save_without_its_tables_reports_unwritable() throws {
        let harness = StoreHarness(.sqlite)
        defer { harness.tearDown() }
        let store = try harness.makeStore()
        try sabotage(harness.databaseURL, "DROP TABLE content")

        #expect(throws: HistoryStoreError.self) { try store.save([anItem(.text("x"))]) }
    }

    @Test func a_save_the_schema_refuses_rolls_back_and_reports() throws {
        let harness = StoreHarness(.sqlite)
        defer { harness.tearDown() }
        let store = try harness.makeStore()
        let kept = anItem(.text("kept"))
        try store.save([kept])
        try sabotage(
            harness.databaseURL,
            "CREATE TRIGGER refuse BEFORE INSERT ON content BEGIN SELECT RAISE(ABORT, 'refused'); END")

        #expect(throws: HistoryStoreError.self) { try store.save([anItem(.text("new")), kept]) }

        #expect(try store.load() == [kept])
    }

    @Test func an_ordering_that_cannot_be_written_reports_at_prepare_or_at_step() throws {
        let viewed = StoreHarness(.sqlite)
        defer { viewed.tearDown() }
        let viewedStore = try viewed.makeStore()
        try sabotage(
            viewed.databaseURL,
            """
            DROP TABLE ordering;
            CREATE VIEW ordering AS SELECT id, 0 AS position, 0 AS copied_at_ms, 0 AS is_pinned FROM content;
            CREATE TRIGGER accept_delete INSTEAD OF DELETE ON ordering BEGIN SELECT 1; END;
            """)
        #expect(throws: HistoryStoreError.self) { try viewedStore.save([anItem(.text("x"))]) }

        let refused = StoreHarness(.sqlite)
        defer { refused.tearDown() }
        let refusedStore = try refused.makeStore()
        try sabotage(
            refused.databaseURL,
            "CREATE TRIGGER refuse BEFORE INSERT ON ordering BEGIN SELECT RAISE(ABORT, 'refused'); END")
        #expect(throws: HistoryStoreError.self) { try refusedStore.save([anItem(.text("x"))]) }
    }

    private struct RawSQLFailure: Error {}

    /// Runs DDL through a connection of its own, the way another process
    /// or another version of the app would.
    private func sabotage(_ database: URL, _ sql: String) throws {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open(database.path, &db) == SQLITE_OK else { throw RawSQLFailure() }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw RawSQLFailure() }
    }

    private func insertRow(kind: String, into database: URL) throws {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open(database.path, &db) == SQLITE_OK else { throw RawSQLFailure() }
        let id = UUID().uuidString
        let sql = """
            INSERT INTO content (id, kind, text) VALUES ('\(id)', '\(kind)', 'ghost');
            INSERT INTO ordering (id, position, copied_at_ms, is_pinned) VALUES ('\(id)', 1, 0, 0);
            """
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw RawSQLFailure() }
    }
}

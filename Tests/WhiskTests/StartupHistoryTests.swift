// WhiskyMac: modified or added 2026-11-16 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation
import Testing

@testable import Whisk

private final class StartupCountingStore: HistoryStore {
    let backing: any HistoryStore
    private(set) var reads = 0

    init(_ backing: any HistoryStore) { self.backing = backing }

    func load() throws -> [ClipboardItem] {
        reads += 1
        return try backing.load()
    }

    func save(_ items: [ClipboardItem], changedContentIDs: Set<UUID>?) throws {
        try backing.save(items, changedContentIDs: changedContentIDs)
    }
}

private final class StartupReleaseCounter {
    private let lock = NSLock()
    private var count = 0
    var released: Int { lock.lock(); defer { lock.unlock() }; return count }

    func release(_ pointer: UnsafeMutableRawPointer) {
        pointer.deallocate()
        lock.lock()
        count += 1
        lock.unlock()
    }
}

/// The gateway generates bytes on load and never retains them itself.
private final class GeneratedStartupStore: HistoryStore {
    let counter: StartupReleaseCounter

    init(counter: StartupReleaseCounter) { self.counter = counter }

    func load() throws -> [ClipboardItem] {
        let size = 1024 * 1024
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
        pointer.initializeMemory(as: UInt8.self, repeating: 0x42, count: size)
        let counter = counter
        let bytes = Data(
            bytesNoCopy: pointer, count: size,
            deallocator: .custom { pointer, _ in
                counter.release(pointer)
            })
        return [anItem(.image(bytes))]
    }

    func save(_ items: [ClipboardItem], changedContentIDs: Set<UUID>?) throws {}
}

@Suite struct StartupHistoryLoading {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("whisk-startup-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func validation_and_controller_share_one_read_without_losing_payloads() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try SQLiteHistoryStore(databaseURL: directory.appendingPathComponent("history.sqlite"))
        let rtf = Data(#"{\rtf1\ansi A \b formatted\b0  copy}"#.utf8)
        let items = [
            anItem(.text("plain copy")),
            ClipboardItem(
                id: UUID(), payload: .text("A formatted copy"), source: nil,
                copiedAt: FakeClock().now(), isPinned: true, rtf: rtf,
                pinnedMetadata: PinnedMetadata(note: "keep", tags: [.green])),
            anItem(.image(Data(repeating: 7, count: 1024 * 1024))),
            anItem(.link(try #require(URL(string: "https://example.com/clipboard")))),
            anItem(.fileReferences(["/nonexistent/a.rtf", "/nonexistent/b.png"])),
        ]
        try database.save(items)
        let counted = StartupCountingStore(database)
        let opened = HistoryStorage.openAndLoad(
            in: directory, makeStore: { _ in AnyHistoryStore(counted) }, log: { _ in })
        let board = ScriptedPasteboard()
        let controller = ClipboardController(
            pasteboard: board, store: opened.store, clock: FakeClock(), initialItems: opened.items,
            logger: RecordingLogger(), present: { _ in })

        #expect(counted.reads == 1)
        #expect(items.allSatisfy { controller.item(for: $0.id) == $0 })
        #expect(controller.select(items[1].id))
        #expect(board.written.last == items[1].payload)
        #expect(board.writtenRTF.last == .some(rtf))
        #expect(counted.reads == 1)

        // Later loads still query the gateway; no startup cache masks saves.
        let later = anItem(.text("captured later"))
        try opened.store.save([later])
        #expect(try opened.store.load() == [later])
        #expect(counted.reads == 2)
    }

    @Test func an_empty_validated_snapshot_does_not_trigger_a_second_read() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let counted = StartupCountingStore(InMemoryHistoryStore())
        let opened = HistoryStorage.openAndLoad(
            in: directory, makeStore: { _ in AnyHistoryStore(counted) }, log: { _ in })
        let controller = ClipboardController(
            pasteboard: ScriptedPasteboard(), store: opened.store, clock: FakeClock(), initialItems: opened.items,
            logger: RecordingLogger(), present: { _ in })

        #expect(opened.items.isEmpty)
        #expect(controller.presenterCacheCount == 0)
        #expect(counted.reads == 1)
    }

    @Test func callers_without_a_startup_snapshot_keep_loading_the_store() {
        let store = InMemoryHistoryStore()
        let item = anItem(.text("ordinary load"))
        store.stored = [item]
        let counted = StartupCountingStore(store)
        let controller = ClipboardController(
            pasteboard: ScriptedPasteboard(), store: counted, clock: FakeClock(),
            logger: RecordingLogger(), present: { _ in })

        #expect(counted.reads == 1)
        #expect(controller.item(for: item.id) == item)
    }

    @Test func capacity_is_applied_to_the_snapshot_and_pins_remain_exempt() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = InMemoryHistoryStore()
        let items = [
            anItem(.text("newest")), anItem(.text("middle")), anItem(.text("pinned"), pinned: true),
            anItem(.text("oldest")),
        ]
        store.stored = items
        let counted = StartupCountingStore(store)
        let opened = HistoryStorage.openAndLoad(
            in: directory, makeStore: { _ in AnyHistoryStore(counted) }, log: { _ in })
        let controller = ClipboardController(
            pasteboard: ScriptedPasteboard(), store: opened.store, clock: FakeClock(),
            retention: RetentionPolicy(capacity: try #require(HistoryCapacity(1))), initialItems: opened.items,
            logger: RecordingLogger(), present: { _ in })

        #expect(controller.item(for: items[0].id) == items[0])
        #expect(controller.item(for: items[1].id) == nil)
        #expect(controller.item(for: items[2].id) == items[2])
        #expect(controller.item(for: items[3].id) == nil)
        #expect(counted.reads == 1)
        // Loading itself never silently deletes or rewrites stored records.
        #expect(store.stored == items)
        #expect(store.saveCount == 0)
    }

    @Test func legacy_import_reuses_validation_and_hands_off_the_committed_merge() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let current = anItem(.text("already saved"))
        let legacy = ClipboardItem(
            id: UUID(), payload: .text("rich legacy"), source: nil, copiedAt: FakeClock().now(),
            isPinned: false, rtf: Data(#"{\rtf1 rich legacy}"#.utf8))
        let database = try SQLiteHistoryStore(databaseURL: directory.appendingPathComponent("history.sqlite"))
        try database.save([current])
        try LegacyHistoryFixture.write([current, legacy], in: directory)
        let counted = StartupCountingStore(database)
        let opened = HistoryStorage.openAndLoad(
            in: directory, makeStore: { _ in AnyHistoryStore(counted) }, log: { _ in })
        let controller = ClipboardController(
            pasteboard: ScriptedPasteboard(), store: opened.store, clock: FakeClock(), initialItems: opened.items,
            logger: RecordingLogger(), present: { _ in })

        #expect(counted.reads == 1)
        #expect(opened.items == [current, legacy])
        #expect(controller.item(for: legacy.id)?.rtf == legacy.rtf)
        #expect(
            try SQLiteHistoryStore(databaseURL: directory.appendingPathComponent("history.sqlite")).load()
                == [current, legacy])
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("history.json").path))
    }

    @Test func failed_legacy_save_hands_off_original_snapshot_and_preserves_import_files() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let current = anItem(.text("database"))
        let legacy = anItem(.image(Data(repeating: 9, count: 64)))
        try LegacyHistoryFixture.write([legacy], in: directory)
        let store = SaveFailingHistoryStore()
        store.stored = [current]
        let counted = StartupCountingStore(store)
        var messages: [String] = []
        let opened = HistoryStorage.openAndLoad(
            in: directory, makeStore: { _ in AnyHistoryStore(counted) }, log: { messages.append($0) })

        #expect(counted.reads == 1)
        #expect(opened.items == [current])
        #expect(!messages.isEmpty)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("history.json").path))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("blobs").path))
    }

    @Test func failed_legacy_retirement_still_hands_off_the_saved_merge() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = anItem(.text("legacy"))
        try LegacyHistoryFixture.write([legacy], in: directory)
        try Data().write(to: directory.appendingPathComponent("history.json.migrated"))
        let counted = StartupCountingStore(InMemoryHistoryStore())
        var messages: [String] = []
        let opened = HistoryStorage.openAndLoad(
            in: directory, makeStore: { _ in AnyHistoryStore(counted) }, log: { messages.append($0) })

        #expect(counted.reads == 1)
        #expect(opened.items == [legacy])
        #expect(messages.count == 1)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("history.json").path))
    }

    @Test func failed_validation_never_reaches_the_controller() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let good = InMemoryHistoryStore()
        let item = anItem(.text("recovered"))
        good.stored = [item]
        let failing = StartupCountingStore(FailingHistoryStore())
        let recovered = StartupCountingStore(good)
        var attempts = 0
        let opened = HistoryStorage.openAndLoad(
            in: directory,
            makeStore: { _ in
                attempts += 1
                return attempts == 1 ? AnyHistoryStore(failing) : AnyHistoryStore(recovered)
            }, log: { _ in })
        let controller = ClipboardController(
            pasteboard: ScriptedPasteboard(), store: opened.store, clock: FakeClock(), initialItems: opened.items,
            logger: RecordingLogger(), present: { _ in })

        #expect(failing.reads == 1)
        #expect(recovered.reads == 1)
        #expect(controller.item(for: item.id) == item)
        #expect(attempts == 2)
    }

    @Test func repeated_validation_failure_returns_a_writable_volatile_session() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let counted = StartupCountingStore(FailingHistoryStore())
        let opened = HistoryStorage.openAndLoad(
            in: directory, makeStore: { _ in AnyHistoryStore(counted) }, log: { _ in })

        #expect(counted.reads == 2)
        #expect(opened.items.isEmpty)
        let item = anItem(.text("session only"))
        try opened.store.save([item])
        #expect(try opened.store.load() == [item])
    }

    @Test func the_store_does_not_retain_the_startup_snapshot_after_handoff() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let counter = StartupReleaseCounter()
        var opened: HistoryStorage.OpenedHistory? = HistoryStorage.openAndLoad(
            in: directory, makeStore: { _ in AnyHistoryStore(GeneratedStartupStore(counter: counter)) }, log: { _ in })
        let store = opened!.store
        var controller: ClipboardController<ScriptedPasteboard, FakeClock, AnyHistoryStore, RecordingLogger>? =
            ClipboardController(
                pasteboard: ScriptedPasteboard(), store: store, clock: FakeClock(), initialItems: opened!.items,
                logger: RecordingLogger(), present: { _ in })
        opened = nil

        withExtendedLifetime(controller) { #expect(counter.released == 0) }
        controller = nil
        withExtendedLifetime(store) { #expect(counter.released == 1) }
    }
}

import Foundation
import Testing

@testable import Whisk

@Suite struct DiagnosticLogStoreTests {
    private let reference = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func cross_launch_export_sorts_events_and_keeps_only_safe_fields() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = folder.appendingPathComponent("Logs")
        let destination = folder.appendingPathComponent("report.txt")
        let canary = "/Users/Example/PRIVATE_CLIPBOARD https://example.com/?token=SECRET"

        let writer = DiagnosticLogStore(
            build: AppBuildInfo(version: canary, isDebug: false), now: { reference.addingTimeInterval(1) }
        ) { log }
        let logger = ConsoleLogger(record: writer.record)
        logger.log(.updateHTTPRejected, status: 403)
        logger.log(.historyMutationFailed, status: 415)
        _ = HistoryStorage.openAndLoad(
            in: folder.appendingPathComponent("synthetic-history"),
            makeStore: { _ in throw HistoryStoreError.unreadable(canary) },
            log: logger.log)
        try await writer.export(to: destination)

        let reopened = DiagnosticLogStore(
            build: AppBuildInfo(version: "1.2.0-beta.1", isDebug: false), now: { reference }
        ) { log }
        reopened.record(.appStarted, status: nil)
        try await reopened.export(to: destination)

        let report = try String(contentsOf: destination, encoding: .utf8)
        let lines = report.split(separator: "\n")
        try #require(lines.count == 6)
        #expect(lines[1].contains("[INFO] [lifecycle] appStarted (Beta 1.2.0-beta.1)"))
        #expect(lines[2].contains("[ERROR] [updates] updateHTTPRejected (Release) status=403"))
        #expect(lines[3].contains("[ERROR] [storage] historyMutationFailed (Release)"))
        #expect(lines[4].contains("historyDatabaseSetAside"))
        #expect(lines[5].contains("historyDatabaseCreateFailed"))
        let stored = try String(contentsOf: log.appendingPathComponent("diagnostics.jsonl"), encoding: .utf8)
        for secret in ["PRIVATE_CLIPBOARD", "SECRET", "/Users/Example", "example.com", "415"] {
            #expect(!stored.contains(secret) && !report.contains(secret))
        }
    }

    @Test func launch_prunes_old_entries_and_size_rotation_keeps_only_two_bounded_files() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = folder.appendingPathComponent("Logs")
        let destination = folder.appendingPathComponent("report.txt")
        let cap = 512
        let old = DiagnosticLogStore(now: { reference }, maxFileBytes: cap) { log }
        old.record(.historyLoadFailed, status: nil)
        try await old.export(to: destination)
        #expect(try String(contentsOf: destination, encoding: .utf8).contains("historyLoadFailed"))
        let fresh = DiagnosticLogStore(
            now: { reference.addingTimeInterval(8 * 86_400) }, maxFileBytes: cap
        ) { log }
        // A new writer prunes before appending, including when the next action never exports.
        fresh.record(.appStarted, status: nil)
        try await fresh.export(to: destination)
        #expect(!(try String(contentsOf: destination, encoding: .utf8)).contains("historyLoadFailed"))

        for _ in 0..<40 { fresh.record(.historyMutationFailed, status: nil) }
        try await fresh.export(to: destination)
        let logs = try FileManager.default.contentsOfDirectory(at: log, includingPropertiesForKeys: [.fileSizeKey])
            .filter { $0.pathExtension == "jsonl" }
        #expect(logs.count == 2)
        for url in logs {
            let bytes = try #require(url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            #expect(bytes > 0 && bytes <= cap)
        }
        let report = try String(contentsOf: destination, encoding: .utf8)
        #expect(report.contains("historyMutationFailed") && !report.contains("appStarted"))
    }

    @Test func cancelling_does_not_touch_disk_and_save_failure_allows_retry() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = folder.appendingPathComponent("Logs")
        let store = DiagnosticLogStore(now: { reference }) { log }
        try await store.export(to: nil)
        #expect(!FileManager.default.fileExists(atPath: log.path))

        store.record(.appStarted, status: nil)
        await #expect(throws: (any Error).self) {
            try await store.export(to: folder.appendingPathComponent("no-directory/report.txt"))
        }
        let valid = folder.appendingPathComponent("report.txt")
        try await store.export(to: valid)
        #expect(try String(contentsOf: valid, encoding: .utf8).contains("appStarted"))
    }

    private func temporaryFolder() throws -> URL {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        return path
    }
}

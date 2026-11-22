import Darwin
import Foundation

/// Local diagnostic events only. All mutable state and file access are confined to the serial queue.
final class DiagnosticLogStore: @unchecked Sendable {
    private struct Entry: Codable, Equatable, Sendable {
        let timestamp: Date
        let event: DiagnosticEvent
        let status: Int?
        let channel: AppBuildInfo.Channel
        let version: String?

        init(timestamp: Date, event: DiagnosticEvent, status: Int?, channel: AppBuildInfo.Channel, version: String?) {
            self.timestamp = timestamp
            self.event = event
            self.status = event.safeStatus(status)
            self.channel = channel
            self.version = Self.safeVersion(version)
        }

        var sanitized: Entry {
            Entry(timestamp: timestamp, event: event, status: status, channel: channel, version: version)
        }

        static func safeVersion(_ version: String?) -> String? {
            guard let version, version.utf8.count <= 40,
                version.range(
                    of: #"^v?[0-9]+(?:\.[0-9]+){0,3}(?:-?beta(?:[.-]?[0-9]+)?)?\z"#,
                    options: [.regularExpression, .caseInsensitive]) != nil
            else { return nil }
            return version
        }

        func line(dateFormatter: ISO8601DateFormatter) -> String {
            let detail = event.safeStatus(status).map { " status=\($0)" } ?? ""
            let build = Self.safeVersion(version).map { " \($0)" } ?? ""
            return "\(dateFormatter.string(from: timestamp)) [\(event.level)] [\(event.category)] "
                + "\(event.rawValue) (\(channel.rawValue)\(build))\(detail)"
        }
    }

    private let directory: @Sendable () throws -> URL
    private let now: @Sendable () -> Date
    private let channel: AppBuildInfo.Channel
    private let version: String?
    private let maxFileBytes: Int
    private let queue = DispatchQueue(label: "dev.whisky.maclx.diagnostics", qos: .utility)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var didReportStorageFailure = false
    private var pruneAt: Date = .distantPast
    private static let retention: TimeInterval = 7 * 24 * 60 * 60

    init(
        build: AppBuildInfo = .current,
        now: @escaping @Sendable () -> Date = { Date() },
        maxFileBytes: Int = 512 * 1024,
        directory: @escaping @Sendable () throws -> URL
    ) {
        self.directory = directory
        self.now = now
        channel = build.channel
        version = Entry.safeVersion(build.version)
        self.maxFileBytes = maxFileBytes
    }

    func record(_ event: DiagnosticEvent, status: Int?) {
        let entry = Entry(timestamp: now(), event: event, status: status, channel: channel, version: version)
        queue.async {
            do {
                try self.withFiles { active, previous in
                    if entry.timestamp >= self.pruneAt {
                        try self.prune(active, previous, now: entry.timestamp)
                    }
                    try self.append(entry, to: active, previous: previous)
                    self.pruneAt = min(self.pruneAt, entry.timestamp.addingTimeInterval(Self.retention))
                }
                self.didReportStorageFailure = false
            } catch {
                if !self.didReportStorageFailure {
                    NSLog("WhiskyMac: local diagnostic log is unavailable.")
                    self.didReportStorageFailure = true
                }
            }
        }
    }

    /// A cancelled save panel supplies nil and performs no disk I/O.
    func export(to destination: URL?) async throws {
        guard let destination else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    let entries = try self.withFiles { active, previous in
                        try self.prune(active, previous, now: self.now())
                    }
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    let sorted = entries.enumerated().sorted {
                        if $0.element.timestamp == $1.element.timestamp { return $0.offset < $1.offset }
                        return $0.element.timestamp < $1.element.timestamp
                    }
                    let lines = sorted.map { $0.element.line(dateFormatter: formatter) }
                    let contents = (["WhiskyMac diagnostic log"] + lines).joined(separator: "\n") + "\n"
                    try Data(contents.utf8).write(to: destination, options: .atomic)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func suggestedFilename(at date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "WhiskyMac-Diagnostics-\(formatter.string(from: date)).txt"
    }

    /// A file lock also serializes access if two versions share this data directory.
    private func withFiles<T>(_ body: (URL, URL) throws -> T) throws -> T {
        let folder = try directory()
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let lock = folder.appendingPathComponent("diagnostics.lock").path
        let descriptor = open(lock, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw CocoaError(.fileWriteUnknown) }
        return try body(
            folder.appendingPathComponent("diagnostics.jsonl"),
            folder.appendingPathComponent("diagnostics.previous.jsonl"))
    }

    private func regularFileSize(_ url: URL) throws -> Int? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                let size = attributes[.size] as? Int
            else { throw CocoaError(.fileReadUnknown) }
            return size
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        }
    }

    private func append(_ entry: Entry, to active: URL, previous: URL) throws {
        let line = try encodedLine(entry)
        guard line.count <= maxFileBytes else { return }
        guard let size = try regularFileSize(active) else {
            try line.write(to: active, options: .atomic)
            return
        }
        if size > maxFileBytes - line.count {
            guard rename(active.path, previous.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
            try line.write(to: active, options: .atomic)
            return
        }

        let file = try FileHandle(forWritingTo: active)
        defer { try? file.close() }
        try file.seekToEnd()
        try file.write(contentsOf: line)
    }

    @discardableResult
    private func prune(_ active: URL, _ previous: URL, now: Date) throws -> [Entry] {
        let cutoff = now.addingTimeInterval(-Self.retention)
        let older = try pruneFile(previous, cutoff: cutoff)
        let newer = try pruneFile(active, cutoff: cutoff)
        let entries = older + newer
        pruneAt = entries.lazy.map(\.timestamp).min()?.addingTimeInterval(Self.retention) ?? .distantFuture
        return entries
    }

    private func pruneFile(_ url: URL, cutoff: Date) throws -> [Entry] {
        guard let size = try regularFileSize(url) else { return [] }
        if size > maxFileBytes {
            try FileManager.default.removeItem(at: url)
            return []
        }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let original = try file.read(upToCount: size) ?? Data()
        let lines = original.split(separator: 0x0A)
        let decoded = lines.compactMap { line -> Entry? in
            guard let entry = try? decoder.decode(Entry.self, from: Data(line)),
                entry.timestamp.timeIntervalSinceReferenceDate.isFinite, entry.timestamp > cutoff
            else { return nil }
            return entry
        }
        let entries = decoded.map(\.sanitized)
        if entries != decoded || entries.count != lines.count || original.last != 0x0A {
            if entries.isEmpty {
                try FileManager.default.removeItem(at: url)
            } else {
                var preserved = Data()
                for entry in entries { preserved.append(try encodedLine(entry)) }
                try preserved.write(to: url, options: .atomic)
            }
        }
        return entries
    }

    private func encodedLine(_ entry: Entry) throws -> Data {
        var data = try encoder.encode(entry)
        data.append(0x0A)
        return data
    }
}

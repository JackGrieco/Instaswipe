import Foundation

public enum BackupKind: Sendable {
    case daily
    case step(Int)
    case preImport
}

/// A decoded backup and the file it came from: two restore sources are the same backup when
/// their names match.
public struct BackupFile: Sendable, Equatable {
    public let name: String
    public let snapshot: BackupSnapshot

    public init(name: String, snapshot: BackupSnapshot) {
        self.name = name
        self.snapshot = snapshot
    }
}

/// Writes timestamped copies of both lists (see `BackupSnapshot`) and keeps only the newest of each kind.
public struct BackupRotator: Sendable {
    private static let backupPrefixes = ["daily-", "step-", "preimport-"]

    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Writes today's daily backup and, on every 100th decision across both lists, a step backup.
    /// Existing files are never overwritten. Returns what was written.
    public func backupIfNeeded(_ snapshot: BackupSnapshot, now: Date, calendar: Calendar) throws -> [BackupKind] {
        var written: [BackupKind] = []
        let dailyName = "daily-\(FileNameStamp.day(now, calendar: calendar)).json"
        if try writeIfMissing(snapshot, name: dailyName) { written.append(.daily) }

        let decisions = snapshot.totalDecisionsMade
        if decisions > 0, decisions % Limits.backupEveryDecisions == 0,
           try writeIfMissing(snapshot, name: "step-\(decisions).json") {
            written.append(.step(decisions))
        }
        if !written.isEmpty { try prune() }
        return written
    }

    public func backup(_ snapshot: BackupSnapshot, kind: BackupKind, now: Date) throws {
        switch kind {
        case .daily:
            try write(snapshot, name: "daily-\(FileNameStamp.day(now, calendar: .current)).json")
        case let .step(count):
            try write(snapshot, name: "step-\(count).json")
        case .preImport:
            try write(snapshot, name: uniquePreImportName(now))
        }
        try prune()
    }

    /// The newest backup (daily, step or pre-import) that still decodes: newest file
    /// modification date first, then newest name. `nil` when there is none. Backups written
    /// before the follower list existed decode with `followers == nil`.
    public func newestValidBackup() throws -> BackupSnapshot? {
        try newestDecodable { _ in true }?.snapshot
    }

    /// Restore source for the state: like `newestValidBackup()`, but skips backups whose state has
    /// no accounts (the placeholder a pre-import backup holds before any following existed).
    public func newestStateBackup() throws -> BackupFile? {
        try newestDecodable { !$0.state.accounts.isEmpty }
    }

    /// Restore source for the followers: the newest decodable backup that has them. Older builds
    /// share this folder, so newer backups may lack followers.
    public func newestFollowersBackup() throws -> BackupFile? {
        try newestDecodable { $0.followers != nil }
    }

    private func newestDecodable(where isWanted: (BackupSnapshot) -> Bool) throws -> BackupFile? {
        guard FileManager.default.fileExists(atPath: directory.path) else { return nil }
        let decoder = StateCoding.decoder()
        for url in try backupFilesNewestFirst() {
            guard let data = try? Data(contentsOf: url),
                  let snapshot = try? decoder.decode(BackupSnapshot.self, from: data),
                  isWanted(snapshot) else { continue }
            return BackupFile(name: url.lastPathComponent, snapshot: snapshot)
        }
        return nil
    }

    private func backupFilesNewestFirst() throws -> [URL] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ).filter { url in
            let name = url.lastPathComponent
            return name.hasSuffix(".json") && Self.backupPrefixes.contains { name.hasPrefix($0) }
        }
        let dated = try urls.map { url in
            (url: url, modified: try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast)
        }
        return dated.sorted { lhs, rhs in
            lhs.modified != rhs.modified
                ? lhs.modified > rhs.modified
                : lhs.url.lastPathComponent > rhs.url.lastPathComponent
        }.map(\.url)
    }

    private func uniquePreImportName(_ now: Date) -> String {
        let base = "preimport-\(FileNameStamp.timestamp(now))"
        var name = "\(base).json"
        var attempt = 2
        while exists(name) {
            name = "\(base)-\(attempt).json"
            attempt += 1
        }
        return name
    }

    private func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
    }

    private func writeIfMissing(_ snapshot: BackupSnapshot, name: String) throws -> Bool {
        guard !exists(name) else { return false }
        try write(snapshot, name: name)
        return true
    }

    private func write(_ snapshot: BackupSnapshot, name: String) throws {
        let data = try StateCoding.encoder().encode(snapshot)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    private func prune() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let daily = files.filter { $0.hasPrefix("daily-") && $0.hasSuffix(".json") }
        let preImport = files.filter { $0.hasPrefix("preimport-") && $0.hasSuffix(".json") }
        let steps = files.compactMap { name -> (name: String, count: Int)? in
            guard name.hasPrefix("step-"), name.hasSuffix(".json"),
                  let count = Int(name.dropFirst("step-".count).dropLast(".json".count))
            else { return nil }
            return (name, count)
        }.sorted { $0.count > $1.count }.map(\.name)

        try removeOldest(daily.sorted(by: >), keeping: Limits.dailyBackupsKept)
        try removeOldest(steps, keeping: Limits.stepBackupsKept)
        try removeOldest(preImport.sorted(by: >), keeping: Limits.preImportBackupsKept)
    }

    /// `newestFirst` must be ordered newest to oldest.
    private func removeOldest(_ newestFirst: [String], keeping limit: Int) throws {
        for name in newestFirst.dropFirst(limit) {
            try FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}

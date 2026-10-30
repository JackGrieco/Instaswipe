import Foundation
import Testing
@testable import InstaSwipeKit

private func withTempDir(_ body: (URL) throws -> Void) throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    try body(dir)
}

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func day(_ offset: Int) -> Date {
    Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86_400)
}

private func stateWith(decisions: Int) -> AppState {
    var state = Fixtures.state([])
    state.totalDecisionsMade = decisions
    return state
}

private func snapshotWith(decisions: Int) -> BackupSnapshot {
    BackupSnapshot(state: stateWith(decisions: decisions), followers: nil)
}

private func names(_ directory: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
}

@Test func dailyBackupOncePerDay() throws {
    try withTempDir { dir in
        let rotator = BackupRotator(directory: dir)
        let first = try rotator.backupIfNeeded(snapshotWith(decisions: 1), now: day(0), calendar: utc)
        let second = try rotator.backupIfNeeded(snapshotWith(decisions: 2), now: day(0), calendar: utc)
        #expect(first.count == 1)
        #expect(second.isEmpty)
        #expect(names(dir) == ["daily-2023-11-14.json"])
    }
}

@Test func stepBackupEveryHundredDecisions() throws {
    try withTempDir { dir in
        let rotator = BackupRotator(directory: dir)
        _ = try rotator.backupIfNeeded(snapshotWith(decisions: 99), now: day(0), calendar: utc)
        #expect(!names(dir).contains { $0.hasPrefix("step-") })
        let atHundred = try rotator.backupIfNeeded(snapshotWith(decisions: 100), now: day(0), calendar: utc)
        #expect(atHundred.count == 1)
        #expect(names(dir).contains("step-100.json"))
        let again = try rotator.backupIfNeeded(snapshotWith(decisions: 100), now: day(0), calendar: utc)
        #expect(again.isEmpty)
        #expect(names(dir).filter { $0.hasPrefix("step-") } == ["step-100.json"])
    }
}

@Test func zeroDecisionsNeverWritesStepBackup() throws {
    try withTempDir { dir in
        _ = try BackupRotator(directory: dir)
            .backupIfNeeded(snapshotWith(decisions: 0), now: day(0), calendar: utc)
        #expect(!names(dir).contains { $0.hasPrefix("step-") })
    }
}

@Test func pruningKeepsNewest() throws {
    try withTempDir { dir in
        let rotator = BackupRotator(directory: dir)
        for offset in 0..<16 {
            _ = try rotator.backupIfNeeded(snapshotWith(decisions: 1), now: day(offset), calendar: utc)
        }
        let daily = names(dir)
        #expect(daily.count == Limits.dailyBackupsKept)
        #expect(daily.first == "daily-2023-11-16.json")
        #expect(daily.last == "daily-2023-11-29.json")
    }
}

@Test func stepPruningSortsNumericallyAndSparesOtherKinds() throws {
    try withTempDir { dir in
        let rotator = BackupRotator(directory: dir)
        try rotator.backup(snapshotWith(decisions: 1), kind: .daily, now: day(0))
        for step in 1...12 {
            try rotator.backup(snapshotWith(decisions: step * 100), kind: .step(step * 100), now: day(0))
        }
        let files = names(dir)
        let steps = files.filter { $0.hasPrefix("step-") }
        #expect(steps.count == Limits.stepBackupsKept)
        #expect(!steps.contains("step-100.json") && !steps.contains("step-200.json"))
        #expect(steps.contains("step-1200.json") && steps.contains("step-300.json"))
        #expect(files.contains { $0.hasPrefix("daily-") })
    }
}

@Test func preImportBackupsAreNamedKeptAndNeverOverwritten() throws {
    try withTempDir { dir in
        let rotator = BackupRotator(directory: dir)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        try rotator.backup(snapshotWith(decisions: 1), kind: .preImport, now: now)
        try rotator.backup(snapshotWith(decisions: 2), kind: .preImport, now: now)
        #expect(names(dir).count == 2)
        #expect(names(dir).allSatisfy { $0.hasPrefix("preimport-") })
        for offset in 1...8 {
            try rotator.backup(snapshotWith(decisions: 3), kind: .preImport, now: now.addingTimeInterval(Double(offset)))
        }
        #expect(names(dir).count == Limits.preImportBackupsKept)
    }
}

private func writeBackup(_ decisions: Int, named name: String, in directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try StateCoding.encoder().encode(stateWith(decisions: decisions)).write(to: directory.appendingPathComponent(name))
}

private func setModified(_ name: String, in directory: URL, _ date: Date) throws {
    try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: directory.appendingPathComponent(name).path)
}

@Test func newestValidBackupPicksNewestByModificationDateAcrossKinds() throws {
    try withTempDir { dir in
        let rotator = BackupRotator(directory: dir)
        try rotator.backup(snapshotWith(decisions: 1), kind: .daily, now: day(0))
        try rotator.backup(snapshotWith(decisions: 300), kind: .step(300), now: day(0))
        try rotator.backup(snapshotWith(decisions: 7), kind: .preImport, now: day(0))
        let files = names(dir)
        let step = try #require(files.first { $0.hasPrefix("step-") })
        let preImport = try #require(files.first { $0.hasPrefix("preimport-") })
        let daily = try #require(files.first { $0.hasPrefix("daily-") })
        try setModified(daily, in: dir, day(1))
        try setModified(step, in: dir, day(3))
        try setModified(preImport, in: dir, day(2))

        #expect(try rotator.newestValidBackup()?.state.totalDecisionsMade == 300)
    }
}

@Test func newestValidBackupSkipsCorruptNewerFile() throws {
    try withTempDir { dir in
        let rotator = BackupRotator(directory: dir)
        try writeBackup(5, named: "daily-2023-11-14.json", in: dir)
        try writeBackup(9, named: "daily-2023-11-15.json", in: dir)
        try Data("not json".utf8).write(to: dir.appendingPathComponent("daily-2023-11-16.json"))
        try setModified("daily-2023-11-14.json", in: dir, day(0))
        try setModified("daily-2023-11-15.json", in: dir, day(1))
        try setModified("daily-2023-11-16.json", in: dir, day(2))

        #expect(try rotator.newestValidBackup()?.state.totalDecisionsMade == 9)
    }
}

@Test func newestValidBackupBreaksDateTiesByNewestName() throws {
    try withTempDir { dir in
        let rotator = BackupRotator(directory: dir)
        try writeBackup(5, named: "daily-2023-11-14.json", in: dir)
        try writeBackup(9, named: "daily-2023-11-15.json", in: dir)
        try setModified("daily-2023-11-14.json", in: dir, day(4))
        try setModified("daily-2023-11-15.json", in: dir, day(4))

        #expect(try rotator.newestValidBackup()?.state.totalDecisionsMade == 9)
    }
}

@Test func newestValidBackupIgnoresOtherFilesAndReturnsNilWhenNoneDecode() throws {
    try withTempDir { dir in
        let rotator = BackupRotator(directory: dir)
        #expect(try rotator.newestValidBackup() == nil)
        try writeBackup(1, named: "state.json", in: dir)
        try Data("{}".utf8).write(to: dir.appendingPathComponent("step-100.json"))
        #expect(try rotator.newestValidBackup() == nil)
    }
}

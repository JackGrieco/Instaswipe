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

private func names(_ directory: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
}

@Test func dailyBackupOncePerDay() throws {
    try withTempDir { dir in
        let rotator = BackupRotator(directory: dir)
        let first = try rotator.backupIfNeeded(stateWith(decisions: 1), now: day(0), calendar: utc)
        let second = try rotator.backupIfNeeded(stateWith(decisions: 2), now: day(0), calendar: utc)
        #expect(first.count == 1)
        #expect(second.isEmpty)
        #expect(names(dir) == ["daily-2023-11-14.json"])
    }
}

@Test func stepBackupEveryHundredDecisions() throws {
    try withTempDir { dir in
        let rotator = BackupRotator(directory: dir)
        _ = try rotator.backupIfNeeded(stateWith(decisions: 99), now: day(0), calendar: utc)
        #expect(!names(dir).contains { $0.hasPrefix("step-") })
        let atHundred = try rotator.backupIfNeeded(stateWith(decisions: 100), now: day(0), calendar: utc)
        #expect(atHundred.count == 1)
        #expect(names(dir).contains("step-100.json"))
        let again = try rotator.backupIfNeeded(stateWith(decisions: 100), now: day(0), calendar: utc)
        #expect(again.isEmpty)
        #expect(names(dir).filter { $0.hasPrefix("step-") } == ["step-100.json"])
    }
}

@Test func zeroDecisionsNeverWritesStepBackup() throws {
    try withTempDir { dir in
        _ = try BackupRotator(directory: dir)
            .backupIfNeeded(stateWith(decisions: 0), now: day(0), calendar: utc)
        #expect(!names(dir).contains { $0.hasPrefix("step-") })
    }
}

@Test func pruningKeepsNewest() throws {
    try withTempDir { dir in
        let rotator = BackupRotator(directory: dir)
        for offset in 0..<16 {
            _ = try rotator.backupIfNeeded(stateWith(decisions: 1), now: day(offset), calendar: utc)
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
        try rotator.backup(stateWith(decisions: 1), kind: .daily, now: day(0))
        for step in 1...12 {
            try rotator.backup(stateWith(decisions: step * 100), kind: .step(step * 100), now: day(0))
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
        try rotator.backup(stateWith(decisions: 1), kind: .preImport, now: now)
        try rotator.backup(stateWith(decisions: 2), kind: .preImport, now: now)
        #expect(names(dir).count == 2)
        #expect(names(dir).allSatisfy { $0.hasPrefix("preimport-") })
        for offset in 1...8 {
            try rotator.backup(stateWith(decisions: 3), kind: .preImport, now: now.addingTimeInterval(Double(offset)))
        }
        #expect(names(dir).count == Limits.preImportBackupsKept)
    }
}

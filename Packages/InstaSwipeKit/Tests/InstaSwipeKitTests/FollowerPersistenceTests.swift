import Foundation
import Testing
@testable import InstaSwipeKit

private func withTempDirs(_ body: (URL, URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(root.appendingPathComponent("local"), root.appendingPathComponent("cloud"))
}

private func names(_ directory: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
}

/// Three followers, all decided.
private func decidedFollowers(savedAt seconds: TimeInterval) -> FollowerState {
    var followers = Fixtures.followers([
        Fixtures.account("anna", since: nil, decision: .remove),
        Fixtures.account("bruno", since: nil, decision: .keep),
        Fixtures.account("carla", since: nil, decision: .remove, unfollowedManually: true),
    ])
    followers.savedAt = Date(timeIntervalSince1970: seconds)
    followers.totalDecisionsMade = 3
    return followers
}

private func legacyBackupData() throws -> Data {
    let url = try #require(Bundle.module.url(forResource: "state-v1", withExtension: "json"))
    return try Data(contentsOf: url)
}

// MARK: FollowerStore

@Test func followerStoreRoundTrip() throws {
    try withTempDirs { local, cloud in
        let store = FollowerStore(localDirectory: local, cloudDirectory: cloud)
        let saved = decidedFollowers(savedAt: 1_000.5)
        try store.save(saved)
        try store.mirrorToCloud(saved)
        #expect(try store.load() == saved)
        #expect(names(local) == ["followers.json"])
        #expect(names(cloud) == ["followers.json"])
    }
}

@Test func followerStoreQuarantinesWithOwnPrefix() throws {
    try withTempDirs { local, _ in
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: local.appendingPathComponent("followers.json"))
        let store = FollowerStore(localDirectory: local, cloudDirectory: nil)
        do {
            _ = try store.load()
            Issue.record("expected StateStoreError.corrupted")
        } catch let StateStoreError.corrupted(quarantined) {
            #expect(quarantined.count == 1)
            #expect(quarantined.allSatisfy { $0.lastPathComponent.hasPrefix("followers.corrupt-") })
        }
        let files = names(local)
        #expect(files.count == 1)
        #expect(files.allSatisfy { $0.hasPrefix("followers.corrupt-") && $0.hasSuffix(".json") })
        #expect(!files.contains { $0.hasPrefix("state.corrupt-") })
    }
}

/// After a restore that cannot bring the followers back, their quarantined copies must stop
/// blocking the load, without ever being deleted.
@Test func discardQuarantinedRenamesBothCopiesAndUnblocksLoad() throws {
    try withTempDirs { local, cloud in
        for directory in [local, cloud] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("{ not json".utf8).write(to: directory.appendingPathComponent("followers.json"))
        }
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: local.appendingPathComponent("state.corrupt-20231114-000000.json"))
        let store = FollowerStore(localDirectory: local, cloudDirectory: cloud)
        #expect(throws: StateStoreError.self) { try store.load() }

        let discarded = try store.discardQuarantined()

        #expect(discarded.count == 2)
        #expect(discarded.allSatisfy { $0.lastPathComponent.hasPrefix("followers.discarded-") })
        #expect(try store.load() == nil)
        for directory in [local, cloud] {
            let files = names(directory).filter { $0.hasPrefix("followers.") }
            #expect(files.count == 1)
            #expect(files.allSatisfy { $0.hasPrefix("followers.discarded-") && $0.hasSuffix(".json") })
            let kept = directory.appendingPathComponent(try #require(files.first))
            #expect(try Data(contentsOf: kept) == Data("{ not json".utf8))
        }
        #expect(names(local).contains("state.corrupt-20231114-000000.json"))
    }
}

@Test func discardQuarantinedWithNothingQuarantinedDoesNothing() throws {
    try withTempDirs { local, cloud in
        let store = FollowerStore(localDirectory: local, cloudDirectory: cloud)
        try store.save(decidedFollowers(savedAt: 5))

        #expect(try store.discardQuarantined().isEmpty)
        #expect(names(local) == ["followers.json"])
    }
}

/// Tells a device that already had its own copy apart from one recovering the copy from iCloud.
@Test func hasLocalCopyIsFalseUntilACopyIsSavedLocally() throws {
    try withTempDirs { local, cloud in
        let store = FileStateStore(localDirectory: local, cloudDirectory: cloud)
        #expect(!store.hasLocalCopy)
        try store.mirrorToCloud(Fixtures.state([]))
        #expect(!store.hasLocalCopy)

        _ = try store.load()

        #expect(store.hasLocalCopy)
        #expect(!FollowerStore(localDirectory: local, cloudDirectory: cloud).hasLocalCopy)
    }
}

@Test func followerStoreAbsentGivesNil() throws {
    try withTempDirs { local, cloud in
        let loaded = try FollowerStore(localDirectory: local, cloudDirectory: cloud).load()
        #expect(loaded == nil)
    }
}

@Test func storesIgnoreEachOthersFiles() throws {
    try withTempDirs { local, cloud in
        try FollowerStore(localDirectory: local, cloudDirectory: cloud).save(decidedFollowers(savedAt: 5))
        #expect(try FileStateStore(localDirectory: local, cloudDirectory: cloud).load() == nil)
        try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
        try Data("placeholder".utf8).write(to: cloud.appendingPathComponent(".state.json.icloud"))
        #expect(try FollowerStore(localDirectory: local, cloudDirectory: cloud).load() == decidedFollowers(savedAt: 5))
    }
}

@Test func oldBuildStateSaveLeavesFollowersIntact() throws {
    try withTempDirs { local, cloud in
        let followerStore = FollowerStore(localDirectory: local, cloudDirectory: cloud)
        try followerStore.save(decidedFollowers(savedAt: 100))
        try followerStore.mirrorToCloud(decidedFollowers(savedAt: 100))

        // An older build only knows AppState: it writes a newer state.json in both places.
        var oldBuildState = Fixtures.state([Fixtures.account("dario", since: nil, decision: .keep)])
        oldBuildState.savedAt = Date(timeIntervalSince1970: 500)
        let data = try StateCoding.encoder().encode(oldBuildState)
        for directory in [local, cloud] {
            try data.write(to: directory.appendingPathComponent("state.json"), options: .atomic)
        }

        let reloadedState = try FileStateStore(localDirectory: local, cloudDirectory: cloud).load()
        let reloadedFollowers = try FollowerStore(localDirectory: local, cloudDirectory: cloud).load()
        #expect(reloadedState == oldBuildState)
        #expect(reloadedFollowers == decidedFollowers(savedAt: 100))
        #expect(reloadedFollowers?.accounts.filter { $0.decision != .pending }.count == 3)
    }
}

// MARK: BackupSnapshot

@Test func backupSnapshotDecodesLegacyBackup() throws {
    let data = try legacyBackupData()
    let snapshot = try StateCoding.decoder().decode(BackupSnapshot.self, from: data)
    #expect(snapshot.followers == nil)
    #expect(snapshot.state == (try StateCoding.decoder().decode(AppState.self, from: data)))
}

@Test func backupSnapshotIsReadableAsAppState() throws {
    let snapshot = BackupSnapshot(state: Fixtures.state([Fixtures.account("a", since: nil)]),
                                  followers: decidedFollowers(savedAt: 10))
    let data = try StateCoding.encoder().encode(snapshot)
    #expect(try StateCoding.decoder().decode(AppState.self, from: data) == snapshot.state)
}

@Test func backupSnapshotRoundTripsBothLists() throws {
    let snapshot = BackupSnapshot(state: Fixtures.state([Fixtures.account("a", since: nil)]),
                                  followers: decidedFollowers(savedAt: 10))
    let data = try StateCoding.encoder().encode(snapshot)
    #expect(try StateCoding.decoder().decode(BackupSnapshot.self, from: data) == snapshot)
}

@Test func backupSnapshotWithoutFollowersEncodesExactlyLikeAppState() throws {
    let state = Fixtures.state([Fixtures.account("a", since: nil)])
    let snapshotData = try StateCoding.encoder().encode(BackupSnapshot(state: state, followers: nil))
    #expect(snapshotData == (try StateCoding.encoder().encode(state)))
}

@Test func backupSnapshotWithCorruptFollowersDoesNotDecode() throws {
    var object = try #require(JSONSerialization.jsonObject(with: try legacyBackupData()) as? [String: Any])
    object["followers"] = ["accounts": "broken"]
    let data = try JSONSerialization.data(withJSONObject: object)
    #expect(throws: DecodingError.self) { try StateCoding.decoder().decode(BackupSnapshot.self, from: data) }
}

// MARK: BackupRotator with both lists

@Test func stepBackupCountsBothLists() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    var state = Fixtures.state([])
    state.totalDecisionsMade = 60
    var followers = Fixtures.followers([])
    followers.totalDecisionsMade = 40

    let written = try BackupRotator(directory: root)
        .backupIfNeeded(BackupSnapshot(state: state, followers: followers), now: Fixtures.referenceDate, calendar: .current)

    #expect(written.contains { if case .step(100) = $0 { true } else { false } })
    #expect(names(root).contains("step-100.json"))
}

@Test func newestValidBackupReturnsFollowersToo() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let rotator = BackupRotator(directory: root)
    let snapshot = BackupSnapshot(state: Fixtures.state([]), followers: decidedFollowers(savedAt: 10))

    try rotator.backup(snapshot, kind: .preImport, now: Fixtures.referenceDate)

    #expect(try rotator.newestValidBackup() == snapshot)
}

/// Old builds share the Backups folder: their newer daily backups have no followers.
@Test func newestFollowersBackupSkipsNewerBackupsWithoutFollowers() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let rotator = BackupRotator(directory: root)
    let encoder = StateCoding.encoder()
    let withFollowers = BackupSnapshot(state: Fixtures.state([]), followers: decidedFollowers(savedAt: 10))
    let files: [(name: String, data: Data, modified: TimeInterval)] = [
        ("step-100.json", try encoder.encode(withFollowers), 1_700_000_000),
        ("daily-2023-11-15.json", try encoder.encode(Fixtures.state([])), 1_700_100_000),
        ("daily-2023-11-16.json", Data("broken".utf8), 1_700_200_000),
    ]
    for file in files {
        let url = root.appendingPathComponent(file.name)
        try file.data.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: file.modified)], ofItemAtPath: url.path)
    }

    #expect(try rotator.newestValidBackup()?.followers == nil)
    let source = try #require(try rotator.newestFollowersBackup())
    #expect(source.content == withFollowers.followers)
    #expect(source.name == "step-100.json")
}

/// A backup whose followers key no longer decodes still restores the state; only the
/// followers source skips it.
@Test func unreadableFollowersKeyStillLeavesTheStateRestorable() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let state = Fixtures.state([Fixtures.account("aa", since: nil)])
    var json = try #require(try JSONSerialization.jsonObject(with: StateCoding.encoder().encode(state)) as? [String: Any])
    json["followers"] = ["accounts": "garbage"]
    try JSONSerialization.data(withJSONObject: json).write(to: root.appendingPathComponent("daily-2023-11-14.json"))
    let rotator = BackupRotator(directory: root)

    let source = try #require(try rotator.newestStateBackup())

    #expect(source.name == "daily-2023-11-14.json")
    #expect(source.content.accounts.map(\.username) == ["aa"])
    #expect(try rotator.newestFollowersBackup() == nil)
}

@Test func newestFollowersBackupIsNilWithoutFollowerBackups() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let rotator = BackupRotator(directory: root)
    #expect(try rotator.newestFollowersBackup() == nil)

    try rotator.backup(BackupSnapshot(state: Fixtures.state([]), followers: nil), kind: .preImport, now: Fixtures.referenceDate)

    #expect(try rotator.newestFollowersBackup() == nil)
}

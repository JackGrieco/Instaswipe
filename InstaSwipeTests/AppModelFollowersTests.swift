import Foundation
import InstaSwipeKit
import Testing
@testable import InstaSwipe

@MainActor
struct AppModelFollowersTests {
    private func account(_ name: String, decision: Decision = .pending, followsMe: Bool = false) -> FollowedAccount {
        FollowedAccount(
            username: name, profileURL: URL(string: "https://www.instagram.com/_u/\(name)")!,
            followedSince: Date(timeIntervalSince1970: 1_600_000_000), followsMe: followsMe, decision: decision
        )
    }

    private func state(_ accounts: [FollowedAccount], savedAt: TimeInterval = 1_700_000_000) -> AppState {
        var state = AppState.empty(now: Date(timeIntervalSince1970: savedAt))
        state.accounts = accounts
        return state
    }

    private func followers(_ accounts: [FollowedAccount], decisions: Int = 0) -> FollowerState {
        var followers = FollowerState.empty(now: Date(timeIntervalSince1970: 1_700_000_000))
        followers.accounts = accounts
        followers.totalDecisionsMade = decisions
        return followers
    }

    private func seed(_ local: URL, state: AppState, followers: FollowerState? = nil) throws {
        try FileStateStore(localDirectory: local, cloudDirectory: nil).save(state)
        if let followers { try FollowerStore(localDirectory: local, cloudDirectory: nil).save(followers) }
    }

    private func loadFollowers(_ local: URL) throws -> FollowerState? {
        try FollowerStore(localDirectory: local, cloudDirectory: nil).load()
    }

    private func names(_ directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    private func writeBackup(_ data: Data, named name: String, in backups: URL, modified: TimeInterval) throws {
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        let url = backups.appendingPathComponent(name)
        try data.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: modified)], ofItemAtPath: url.path)
    }

    /// Imported following [aa, bb] and followers [aa, cc].
    private func importedModel() async throws -> (model: AppModel, local: URL) {
        let local = try TestSupport.makeDirectory()
        let model = AppModel(environment: TestSupport.environment(local: local))
        await model.prepareImport(picked: [try TestSupport.makeExport(["aa", "bb"], followers: ["aa", "cc"])])
        model.confirmImport()
        return (model, local)
    }

    // MARK: Import

    @Test func importCreatesFollowersFile() async throws {
        let (model, local) = try await importedModel()

        #expect(model.followers?.accounts.map(\.username) == ["aa", "cc"])
        #expect(try loadFollowers(local)?.accounts.count == 2)
        #expect(model.pendingFollowerMerge == nil)
        #expect(model.state?.accounts.first { $0.username == "aa" }?.followsMe == true)
        #expect(model.followers?.accounts.first { $0.username == "aa" }?.followsMe == true)
        #expect(model.followers?.accounts.first { $0.username == "cc" }?.followsMe == false)
    }

    @Test func prepareImportPreviewsFollowers() async throws {
        let local = try TestSupport.makeDirectory()
        let model = AppModel(environment: TestSupport.environment(local: local))

        await model.prepareImport(picked: [try TestSupport.makeExport(["aa"], followers: ["aa", "cc"])])

        #expect(model.pendingFollowerMerge?.summary.newAccounts == 2)
        model.cancelImport()
        #expect(model.pendingFollowerMerge == nil)
    }

    @Test func importWithoutFollowerFilesKeepsFollowers() async throws {
        let local = try TestSupport.makeDirectory()
        let existing = followers([account("aa", decision: .keep)], decisions: 1)
        try seed(local, state: state([account("aa", followsMe: true)]), followers: existing)
        let model = AppModel(environment: TestSupport.environment(local: local))
        let before = try #require(model.followers)

        await model.prepareImport(picked: [try TestSupport.makeExport(["aa", "bb"])])
        #expect(model.pendingMerge != nil)
        #expect(model.pendingFollowerMerge == nil)
        model.confirmImport()

        #expect(model.state?.accounts.count == 2)
        #expect(model.followers == before)
        #expect(try loadFollowers(local)?.accounts == existing.accounts)
        #expect(model.state?.accounts.first { $0.username == "aa" }?.followsMe == true)
    }

    @Test func confirmImportKeepsFollowerDecisionsMadeAfterPreview() async throws {
        let local = try TestSupport.makeDirectory()
        try seed(local, state: state([account("aa")]), followers: followers([account("aa")]))
        let model = AppModel(environment: TestSupport.environment(local: local))
        await model.prepareImport(picked: [try TestSupport.makeExport(["aa"], followers: ["aa", "cc"])])

        model.apply(.followers) { Review.decide(.keep, username: "aa", in: $0, now: Date()) }
        model.confirmImport()

        #expect(model.followers?.accounts.first { $0.username == "aa" }?.decision == .keep)
        #expect(model.followers?.accounts.contains { $0.username == "cc" } == true)
    }

    @Test func preImportBackupHoldsBothLists() async throws {
        let local = try TestSupport.makeDirectory()
        let existing = followers([account("aa", decision: .remove)], decisions: 1)
        try seed(local, state: state([account("aa")]), followers: existing)
        let model = AppModel(environment: TestSupport.environment(local: local))

        await model.prepareImport(picked: [try TestSupport.makeExport(["aa"], followers: ["aa"])])
        model.confirmImport()

        let backups = local.appendingPathComponent("Backups", isDirectory: true)
        let preImport = try #require(names(backups).first { $0.hasPrefix("preimport-") })
        let data = try Data(contentsOf: backups.appendingPathComponent(preImport))
        let snapshot = try StateCoding.decoder().decode(BackupSnapshot.self, from: data)
        #expect(snapshot.followers?.accounts.first?.decision == .remove)
    }

    @Test func importAbortsWhenFollowerSaveFails() async throws {
        let local = try TestSupport.makeDirectory()
        try seed(local, state: state([account("aa")]))
        let model = AppModel(environment: TestSupport.environment(local: local))
        let before = try #require(model.state)
        await model.prepareImport(picked: [try TestSupport.makeExport(["aa", "bb"], followers: ["aa"])])
        // A directory in place of followers.json makes the atomic write fail.
        try FileManager.default.createDirectory(at: local.appendingPathComponent("followers.json"), withIntermediateDirectories: true)

        model.confirmImport()

        #expect(model.errorMessage != nil)
        #expect(model.state == before)
        #expect(model.followers == nil)
        #expect(model.pendingMerge != nil)
        #expect(try FileStateStore(localDirectory: local, cloudDirectory: nil).load()?.accounts.count == 1)
    }

    // MARK: Linking

    @Test func removingFollowerUpdatesFollowingCard() async throws {
        let (model, _) = try await importedModel()

        model.apply(.followers) { Review.decide(.remove, username: "aa", in: $0, now: Date()) }
        #expect(model.state?.accounts.first { $0.username == "aa" }?.followsMe == true)
        model.apply(.followers) { Report.setUnfollowed(true, username: "aa", in: $0, now: Date()) }

        #expect(model.state?.accounts.first { $0.username == "aa" }?.followsMe == false)
    }

    @Test func loadRelinksFollowsMeOverStaleStateFile() async throws {
        let (model, local) = try await importedModel()
        model.apply(.followers) { Review.decide(.remove, username: "aa", in: $0, now: Date()) }
        model.apply(.followers) { Report.setUnfollowed(true, username: "aa", in: $0, now: Date()) }
        // What an older build would write: followsMe back to true and a newer savedAt.
        var stale = try #require(model.state)
        stale.accounts = stale.accounts.map { account in
            var copy = account
            copy.followsMe = true
            return copy
        }
        stale.savedAt = Date().addingTimeInterval(3_600)
        try FileStateStore(localDirectory: local, cloudDirectory: nil).save(stale)

        let reloaded = AppModel(environment: TestSupport.environment(local: local))

        #expect(reloaded.state?.accounts.first { $0.username == "aa" }?.followsMe == false)
        #expect(reloaded.state?.accounts.first { $0.username == "bb" }?.followsMe == false)
        #expect(reloaded.followers?.accounts.first { $0.username == "aa" }?.decision == .remove)
    }

    @Test func followingUnfollowUpdatesFollowerCard() async throws {
        let (model, _) = try await importedModel()

        model.apply(.following) { Report.setUnfollowed(true, username: "aa", in: Review.decide(.remove, username: "aa", in: $0, now: Date()), now: Date()) }

        #expect(model.followers?.accounts.first { $0.username == "aa" }?.followsMe == false)
    }

    // MARK: Lists

    @Test func listReturnsEachListAndNilWithoutFollowers() throws {
        let local = try TestSupport.makeDirectory()
        try seed(local, state: state([account("aa")]))
        let model = AppModel(environment: TestSupport.environment(local: local))

        #expect(model.list(.following)?.accounts.map(\.username) == ["aa"])
        #expect(model.list(.followers) == nil)
        model.apply(.followers) { $0 }
        #expect(model.followers == nil)
        #expect(!FileManager.default.fileExists(atPath: local.appendingPathComponent("followers.json").path))
    }

    @Test func applyToOneListSavesOnlyItsFile() async throws {
        let (model, local) = try await importedModel()
        let stateFile = local.appendingPathComponent("state.json")
        let stateBefore = try Data(contentsOf: stateFile)

        model.apply(.followers) { Review.decide(.keep, username: "cc", in: $0, now: Date()) }

        #expect(try Data(contentsOf: stateFile) == stateBefore)
        #expect(try loadFollowers(local)?.accounts.first { $0.username == "cc" }?.decision == .keep)
        #expect(model.followers?.totalDecisionsMade == 1)
    }

    @Test func applyToBothListsUpdatesBothFiles() async throws {
        let (model, local) = try await importedModel()

        model.applyToBothLists { Review.markAvailability(.unavailable, displayName: nil, username: "aa", in: $0) }

        #expect(model.state?.accounts.first { $0.username == "aa" }?.availability == .unavailable)
        #expect(model.followers?.accounts.first { $0.username == "aa" }?.availability == .unavailable)
        #expect(try loadFollowers(local)?.accounts.first { $0.username == "aa" }?.availability == .unavailable)
        let savedState = try FileStateStore(localDirectory: local, cloudDirectory: nil).load()
        #expect(savedState?.accounts.first { $0.username == "aa" }?.availability == .unavailable)
    }

    @Test func actionsTodaySumsBothLists() async throws {
        let (model, _) = try await importedModel()
        let today = Date()

        model.apply(.following) { Report.setUnfollowed(true, username: "bb", in: Review.decide(.remove, username: "bb", in: $0, now: today), now: today) }
        model.apply(.followers) { Report.setUnfollowed(true, username: "cc", in: Review.decide(.remove, username: "cc", in: $0, now: today), now: today) }

        #expect(model.actionsToday(now: today, calendar: .current) == 2)
    }

    @Test func listModePersists() throws {
        let environment = TestSupport.environment(local: try TestSupport.makeDirectory())
        let model = AppModel(environment: environment)
        #expect(model.listMode == .following)

        model.listMode = .followers

        #expect(AppModel(environment: environment).listMode == .followers)
    }

    @Test func dailyBackupHoldsBothLists() async throws {
        let (model, local) = try await importedModel()
        model.apply(.followers) { Review.decide(.keep, username: "cc", in: $0, now: Date()) }

        let backups = local.appendingPathComponent("Backups", isDirectory: true)
        let daily = try #require(names(backups).first { $0.hasPrefix("daily-") })
        let data = try Data(contentsOf: backups.appendingPathComponent(daily))
        let snapshot = try StateCoding.decoder().decode(BackupSnapshot.self, from: data)
        #expect(snapshot.followers?.accounts.count == 2)
        #expect(model.followers != nil)
    }

    // MARK: Load failures

    @Test func corruptFollowersBlockAndSaveNothing() throws {
        let local = try TestSupport.makeDirectory()
        try seed(local, state: state([account("aa")]))
        try Data("not json".utf8).write(to: local.appendingPathComponent("followers.json"))
        let stateBefore = try Data(contentsOf: local.appendingPathComponent("state.json"))

        let model = AppModel(environment: TestSupport.environment(local: local))
        model.apply { Review.decide(.keep, username: "aa", in: $0, now: Date()) }
        model.apply(.following) { Review.decide(.keep, username: "aa", in: $0, now: Date()) }

        #expect(model.loadError != nil)
        #expect(model.quarantinedFileNames.contains { $0.hasPrefix("followers.corrupt-") })
        #expect(try Data(contentsOf: local.appendingPathComponent("state.json")) == stateBefore)
        #expect(!FileManager.default.fileExists(atPath: local.appendingPathComponent("followers.json").path))
    }

    @Test func bothFilesCorruptListBothQuarantines() throws {
        let local = try TestSupport.makeDirectory()
        try Data("not json".utf8).write(to: local.appendingPathComponent("state.json"))
        try Data("not json".utf8).write(to: local.appendingPathComponent("followers.json"))

        let model = AppModel(environment: TestSupport.environment(local: local))

        #expect(model.quarantinedFileNames.count == 2)
        #expect(model.quarantinedFileNames.contains { $0.hasPrefix("state.corrupt-") })
        #expect(model.quarantinedFileNames.contains { $0.hasPrefix("followers.corrupt-") })
    }

    @Test func followersStillInCloudWaitAndSaveNothing() throws {
        let local = try TestSupport.makeDirectory()
        let cloud = try TestSupport.makeDirectory()
        try seed(local, state: state([account("aa")]))
        try Data("placeholder".utf8).write(to: cloud.appendingPathComponent(".followers.json.icloud"))

        let model = AppModel(environment: TestSupport.environment(local: local, cloud: cloud))
        model.apply(.followers) { $0 }

        #expect(model.rootScreen == .waitingForCloud)
        #expect(model.followers == nil)
        #expect(!FileManager.default.fileExists(atPath: local.appendingPathComponent("followers.json").path))
        #expect(!FileManager.default.fileExists(atPath: cloud.appendingPathComponent("followers.json").path))
    }

    // MARK: Restore

    /// Corrupt state.json; the Backups folder is returned (created on demand by `writeBackup`).
    private func corruptedState() throws -> (local: URL, backups: URL) {
        let local = try TestSupport.makeDirectory()
        try Data("not json".utf8).write(to: local.appendingPathComponent("state.json"))
        return (local, local.appendingPathComponent("Backups", isDirectory: true))
    }

    @Test func restoreBringsBackFollowers() throws {
        let (local, backups) = try corruptedState()
        let backedUp = followers([account("ff", decision: .remove)], decisions: 1)
        let snapshot = BackupSnapshot(state: state([account("aa")]), followers: backedUp)
        try writeBackup(try StateCoding.encoder().encode(snapshot), named: "step-100.json", in: backups, modified: 1_700_000_000)
        let model = AppModel(environment: TestSupport.environment(local: local))

        model.prepareRestore()
        #expect(model.pendingRestore?.followers?.accounts == backedUp.accounts)
        model.confirmRestore()

        #expect(model.loadError == nil)
        #expect(model.followers?.accounts == backedUp.accounts)
        #expect(model.followers?.totalDecisionsMade == 1)
        #expect(try loadFollowers(local)?.accounts == backedUp.accounts)
    }

    @Test func restoreFromOldBackupKeepsReadableFollowersFile() throws {
        let (local, backups) = try corruptedState()
        let current = followers([account("ff", decision: .keep)], decisions: 1)
        try FollowerStore(localDirectory: local, cloudDirectory: nil).save(current)
        let fileBefore = try Data(contentsOf: local.appendingPathComponent("followers.json"))
        try writeBackup(try StateCoding.encoder().encode(state([account("aa")])), named: "daily-2023-11-14.json", in: backups, modified: 1_700_000_000)
        let model = AppModel(environment: TestSupport.environment(local: local))

        model.prepareRestore()
        model.confirmRestore()

        #expect(model.loadError == nil)
        #expect(model.state?.accounts.map(\.username) == ["aa"])
        #expect(model.followers?.accounts == current.accounts)
        #expect(try Data(contentsOf: local.appendingPathComponent("followers.json")) == fileBefore)
    }

    @Test func restoreTakesFollowersFromOlderBackupWhenFileIsCorrupt() throws {
        let (local, backups) = try corruptedState()
        try Data("not json".utf8).write(to: local.appendingPathComponent("followers.json"))
        let older = followers([account("ff", decision: .remove)], decisions: 1)
        let encoder = StateCoding.encoder()
        try writeBackup(try encoder.encode(BackupSnapshot(state: state([account("old")]), followers: older)),
                        named: "step-100.json", in: backups, modified: 1_700_000_000)
        try writeBackup(try encoder.encode(state([account("aa")])), named: "daily-2023-11-16.json", in: backups, modified: 1_700_200_000)
        let model = AppModel(environment: TestSupport.environment(local: local))
        #expect(model.quarantinedFileNames.count == 2)

        model.prepareRestore()
        model.confirmRestore()

        #expect(model.loadError == nil)
        #expect(model.state?.accounts.map(\.username) == ["aa"])
        #expect(model.followers?.accounts == older.accounts)
        #expect(try loadFollowers(local)?.accounts == older.accounts)
    }

    @Test func restoreWithoutAnyFollowerBackupLeavesFollowersNil() throws {
        let (local, backups) = try corruptedState()
        try writeBackup(try StateCoding.encoder().encode(state([account("aa")])), named: "daily-2023-11-14.json", in: backups, modified: 1_700_000_000)
        let model = AppModel(environment: TestSupport.environment(local: local))

        model.prepareRestore()
        model.confirmRestore()

        #expect(model.state?.accounts.map(\.username) == ["aa"])
        #expect(model.followers == nil)
        #expect(!FileManager.default.fileExists(atPath: local.appendingPathComponent("followers.json").path))
    }

    // MARK: UI-test seed

    @Test func seedCreatesFollowersStartingWithFan01() throws {
        let local = try TestSupport.makeDirectory()
        let environment = AppEnvironment(
            localDirectory: local, cloudDirectory: nil, isUITesting: true,
            useFakeProfiles: true, shouldSeedTestAccounts: true, defaultsSuiteName: UUID().uuidString
        )

        let model = AppModel(environment: environment)

        let seeded = try #require(model.followers)
        #expect(seeded.accounts.map(\.username) == ["fan_01", "fan_02", "test_02"])
        #expect(seeded.accounts.map(\.followsMe) == [false, false, true])
        #expect(Review.current(in: seeded)?.username == "fan_01")
        #expect(model.state?.accounts.first { $0.username == "test_02" }?.followsMe == true)
        #expect(try loadFollowers(local)?.accounts.count == 3)
    }
}

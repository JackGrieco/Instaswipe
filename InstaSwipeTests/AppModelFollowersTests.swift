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

    @Test func preImportBackupIsTakenWhenOnlyFollowersExist() async throws {
        let local = try TestSupport.makeDirectory()
        try FollowerStore(localDirectory: local, cloudDirectory: nil).save(followers([account("aa", decision: .remove)], decisions: 1))
        let model = AppModel(environment: TestSupport.environment(local: local))
        #expect(model.state == nil)

        await model.prepareImport(picked: [try TestSupport.makeExport(["aa"], followers: ["aa"])])
        model.confirmImport()

        let backups = local.appendingPathComponent("Backups", isDirectory: true)
        let preImport = try #require(names(backups).first { $0.hasPrefix("preimport-") })
        let snapshot = try StateCoding.decoder().decode(BackupSnapshot.self, from: try Data(contentsOf: backups.appendingPathComponent(preImport)))
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

    /// A profile in one list only: the other file is not rewritten nor re-stamped, so a second
    /// device never mirrors an untouched list over a newer iCloud copy.
    @Test func applyToBothListsLeavesTheUntouchedListAlone() async throws {
        let (model, local) = try await importedModel()
        let followersFile = local.appendingPathComponent("followers.json")
        let stateFile = local.appendingPathComponent("state.json")
        let followersBefore = try Data(contentsOf: followersFile)
        let followersSavedAt = try #require(model.followers?.savedAt)

        model.applyToBothLists { Review.markAvailability(.unavailable, displayName: nil, username: "bb", in: $0) }

        #expect(model.state?.accounts.first { $0.username == "bb" }?.availability == .unavailable)
        #expect(try Data(contentsOf: followersFile) == followersBefore)
        #expect(model.followers?.savedAt == followersSavedAt)

        let stateBefore = try Data(contentsOf: stateFile)
        let stateSavedAt = try #require(model.state?.savedAt)
        model.applyToBothLists { Review.markAvailability(.unavailable, displayName: nil, username: "cc", in: $0) }

        #expect(model.followers?.accounts.first { $0.username == "cc" }?.availability == .unavailable)
        #expect(try Data(contentsOf: stateFile) == stateBefore)
        #expect(model.state?.savedAt == stateSavedAt)
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

    @Test func dailyBackupWrittenOnImportHoldsBothLists() async throws {
        let (_, local) = try await importedModel()

        let backups = local.appendingPathComponent("Backups", isDirectory: true)
        let daily = try #require(names(backups).first { $0.hasPrefix("daily-") })
        let data = try Data(contentsOf: backups.appendingPathComponent(daily))
        let snapshot = try StateCoding.decoder().decode(BackupSnapshot.self, from: data)
        #expect(snapshot.state.accounts.map(\.username) == ["aa", "bb"])
        #expect(snapshot.followers?.accounts.map(\.username) == ["aa", "cc"])
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

    private func corrupt(_ name: String, in local: URL) throws {
        try Data("not json".utf8).write(to: local.appendingPathComponent(name))
    }

    private func backupsFolder(_ local: URL) -> URL {
        local.appendingPathComponent("Backups", isDirectory: true)
    }

    private func writeSnapshot(_ snapshot: BackupSnapshot, named name: String, in local: URL, modified: TimeInterval) throws {
        try writeBackup(try StateCoding.encoder().encode(snapshot), named: name, in: backupsFolder(local), modified: modified)
    }

    private func fileData(_ name: String, in local: URL) throws -> Data {
        try Data(contentsOf: local.appendingPathComponent(name))
    }

    @Test func restoreBringsBackFollowers() throws {
        let local = try TestSupport.makeDirectory()
        try corrupt("state.json", in: local)
        try corrupt("followers.json", in: local)
        let backedUp = followers([account("ff", decision: .remove)], decisions: 1)
        try writeSnapshot(BackupSnapshot(state: state([account("aa")]), followers: backedUp), named: "step-100.json", in: local, modified: 1_700_000_000)
        let model = AppModel(environment: TestSupport.environment(local: local))

        model.prepareRestore()
        #expect(model.pendingRestore?.followers?.accounts == backedUp.accounts)
        model.confirmRestore()

        #expect(model.loadError == nil)
        #expect(model.quarantinedFileNames.isEmpty)
        #expect(model.state?.accounts.map(\.username) == ["aa"])
        #expect(model.followers?.accounts == backedUp.accounts)
        #expect(model.followers?.totalDecisionsMade == 1)
        #expect(try loadFollowers(local)?.accounts == backedUp.accounts)
    }

    /// Case A: only followers.json is unreadable; the readable state must not roll back.
    @Test func restoreKeepsReadableStateWhenOnlyFollowersAreCorrupt() throws {
        let local = try TestSupport.makeDirectory()
        try seed(local, state: state([account("aa", decision: .keep), account("new")]))
        try corrupt("followers.json", in: local)
        let stateBefore = try fileData("state.json", in: local)
        let backedUp = followers([account("aa", decision: .remove)], decisions: 1)
        try writeSnapshot(BackupSnapshot(state: state([account("old")]), followers: backedUp), named: "daily-2023-11-14.json", in: local, modified: 1_700_000_000)
        let model = AppModel(environment: TestSupport.environment(local: local))

        model.prepareRestore()
        #expect(model.pendingRestore?.state == nil)
        model.confirmRestore()

        #expect(model.loadError == nil)
        #expect(try fileData("state.json", in: local) == stateBefore)
        #expect(model.state?.accounts.map(\.username) == ["aa", "new"])
        #expect(model.followers?.accounts.map(\.decision) == [.remove])
        #expect(try loadFollowers(local)?.accounts.map(\.username) == ["aa"])
    }

    /// Case B: only state.json is unreadable; readable followers must not roll back, even
    /// when the backup has followers.
    @Test func restoreKeepsReadableFollowersWhenOnlyStateIsCorrupt() throws {
        let local = try TestSupport.makeDirectory()
        try corrupt("state.json", in: local)
        let current = followers([account("ff", decision: .keep), account("gg", decision: .remove)], decisions: 2)
        try FollowerStore(localDirectory: local, cloudDirectory: nil).save(current)
        let followersBefore = try fileData("followers.json", in: local)
        let older = followers([account("ff")])
        try writeSnapshot(BackupSnapshot(state: state([account("aa")]), followers: older), named: "step-100.json", in: local, modified: 1_700_000_000)
        let model = AppModel(environment: TestSupport.environment(local: local))

        model.prepareRestore()
        #expect(model.pendingRestore?.followers == nil)
        model.confirmRestore()

        #expect(model.loadError == nil)
        #expect(model.state?.accounts.map(\.username) == ["aa"])
        #expect(model.followers?.accounts == current.accounts)
        #expect(try fileData("followers.json", in: local) == followersBefore)
    }

    @Test func restoreTakesFollowersFromOlderBackupWhenFileIsCorrupt() throws {
        let local = try TestSupport.makeDirectory()
        try corrupt("state.json", in: local)
        try corrupt("followers.json", in: local)
        let older = followers([account("ff", decision: .remove)], decisions: 1)
        try writeSnapshot(BackupSnapshot(state: state([account("old")]), followers: older), named: "step-100.json", in: local, modified: 1_700_000_000)
        try writeSnapshot(BackupSnapshot(state: state([account("aa")]), followers: nil), named: "daily-2023-11-16.json", in: local, modified: 1_700_200_000)
        let model = AppModel(environment: TestSupport.environment(local: local))
        #expect(model.quarantinedFileNames.count == 2)

        model.prepareRestore()
        #expect(model.pendingRestore?.isFromTwoBackups == true)
        model.confirmRestore()

        #expect(model.loadError == nil)
        #expect(model.state?.accounts.map(\.username) == ["aa"])
        #expect(model.followers?.accounts == older.accounts)
        #expect(try loadFollowers(local)?.accounts == older.accounts)
    }

    @Test func restoreWithoutAnyFollowerBackupLeavesFollowersNil() throws {
        let local = try TestSupport.makeDirectory()
        try corrupt("state.json", in: local)
        try writeSnapshot(BackupSnapshot(state: state([account("aa")]), followers: nil), named: "daily-2023-11-14.json", in: local, modified: 1_700_000_000)
        let model = AppModel(environment: TestSupport.environment(local: local))

        model.prepareRestore()
        model.confirmRestore()

        #expect(model.state?.accounts.map(\.username) == ["aa"])
        #expect(model.followers == nil)
        #expect(!FileManager.default.fileExists(atPath: local.appendingPathComponent("followers.json").path))
    }

    /// No backup holds followers: their quarantined copy is set aside, so the next launch loads.
    @Test func unrecoverableFollowersNoLongerBlockTheNextLaunch() throws {
        let local = try TestSupport.makeDirectory()
        try corrupt("state.json", in: local)
        try corrupt("followers.json", in: local)
        try writeSnapshot(BackupSnapshot(state: state([account("aa")]), followers: nil), named: "daily-2023-11-14.json", in: local, modified: 1_700_000_000)
        let model = AppModel(environment: TestSupport.environment(local: local))

        model.prepareRestore()
        #expect(model.pendingRestore?.discardsFollowers == true)
        model.confirmRestore()
        let relaunched = AppModel(environment: TestSupport.environment(local: local))

        #expect(model.rootScreen == .main)
        #expect(relaunched.rootScreen == .main)
        #expect(relaunched.followers == nil)
        #expect(relaunched.state?.accounts.map(\.username) == ["aa"])
        #expect(names(local).contains { $0.hasPrefix("followers.discarded-") })
        #expect(!names(local).contains { $0.hasPrefix("followers.corrupt-") })
    }

    /// Readable state, unreadable followers and no backup at all: setting the followers aside is
    /// still possible, otherwise the app would stay blocked for good.
    @Test func corruptFollowersWithoutAnyBackupCanBeSetAside() throws {
        let local = try TestSupport.makeDirectory()
        try seed(local, state: state([account("aa")]))
        try corrupt("followers.json", in: local)
        let stateBefore = try fileData("state.json", in: local)
        let model = AppModel(environment: TestSupport.environment(local: local))

        model.prepareRestore()
        #expect(model.errorMessage == nil)
        model.confirmRestore()

        #expect(model.rootScreen == .main)
        #expect(model.followers == nil)
        #expect(try fileData("state.json", in: local) == stateBefore)
        #expect(AppModel(environment: TestSupport.environment(local: local)).rootScreen == .main)
    }

    /// A pre-import backup taken with followers only holds an empty placeholder state: newer, but
    /// never the state a restore offers.
    @Test func restoreIgnoresPlaceholderStateButUsesItsFollowers() throws {
        let local = try TestSupport.makeDirectory()
        try corrupt("state.json", in: local)
        try corrupt("followers.json", in: local)
        let placeholderFollowers = followers([account("ff", decision: .keep)], decisions: 1)
        try writeSnapshot(BackupSnapshot(state: state([account("aa")]), followers: nil), named: "daily-2023-11-14.json", in: local, modified: 1_700_000_000)
        try writeSnapshot(BackupSnapshot(state: state([]), followers: placeholderFollowers), named: "preimport-20231115-000000.json", in: local, modified: 1_700_100_000)
        let model = AppModel(environment: TestSupport.environment(local: local))

        model.prepareRestore()

        #expect(model.pendingRestore?.state?.accounts.map(\.username) == ["aa"])
        #expect(model.pendingRestore?.followers?.accounts == placeholderFollowers.accounts)
    }

    /// A missing file may only be not yet listed by iCloud: a restore never fills it from a backup
    /// (stamped now, it would beat the real iCloud copy). Only quarantined files are restored.
    @Test func restoreLeavesMissingFollowersAlone() throws {
        let local = try TestSupport.makeDirectory()
        try corrupt("state.json", in: local)
        let backedUp = followers([account("ff", decision: .remove)], decisions: 1)
        try writeSnapshot(BackupSnapshot(state: state([account("aa")]), followers: backedUp), named: "step-100.json", in: local, modified: 1_700_000_000)
        let model = AppModel(environment: TestSupport.environment(local: local))

        model.prepareRestore()
        #expect(model.pendingRestore?.state?.accounts.map(\.username) == ["aa"])
        #expect(model.pendingRestore?.followers == nil)
        #expect(model.pendingRestore?.discardsFollowers == false)
        model.confirmRestore()

        #expect(model.loadError == nil)
        #expect(model.followers == nil)
        #expect(!FileManager.default.fileExists(atPath: local.appendingPathComponent("followers.json").path))
    }

    @Test func restoreLeavesMissingStateAlone() throws {
        let local = try TestSupport.makeDirectory()
        try corrupt("followers.json", in: local)
        let backedUp = followers([account("ff", decision: .remove)], decisions: 1)
        try writeSnapshot(BackupSnapshot(state: state([account("aa")]), followers: backedUp), named: "step-100.json", in: local, modified: 1_700_000_000)
        let model = AppModel(environment: TestSupport.environment(local: local))
        #expect(model.loadError != nil)

        model.prepareRestore()
        #expect(model.pendingRestore?.state == nil)
        #expect(model.pendingRestore?.followers?.accounts == backedUp.accounts)
        model.confirmRestore()

        #expect(model.loadError == nil)
        #expect(model.state == nil)
        #expect(model.followers?.accounts == backedUp.accounts)
        #expect(!FileManager.default.fileExists(atPath: local.appendingPathComponent("state.json").path))
    }

    /// The followers key of the newest backup no longer decodes: its state is still the one restored.
    @Test func restoreUsesTheStateOfABackupWithUnreadableFollowers() throws {
        let local = try TestSupport.makeDirectory()
        try corrupt("state.json", in: local)
        var json = try #require(try JSONSerialization.jsonObject(with: StateCoding.encoder().encode(state([account("new")]))) as? [String: Any])
        json["followers"] = ["accounts": "garbage"]
        try writeBackup(try JSONSerialization.data(withJSONObject: json), named: "daily-2023-11-15.json", in: backupsFolder(local), modified: 1_700_100_000)
        try writeSnapshot(BackupSnapshot(state: state([account("old")]), followers: nil), named: "daily-2023-11-14.json", in: local, modified: 1_700_000_000)
        let model = AppModel(environment: TestSupport.environment(local: local))

        model.prepareRestore()

        #expect(model.pendingRestore?.state?.accounts.map(\.username) == ["new"])
    }

    @Test func confirmRestoreAbortsWhenTheBackupsChangedSinceTheDialog() throws {
        let local = try TestSupport.makeDirectory()
        try corrupt("state.json", in: local)
        try writeSnapshot(BackupSnapshot(state: state([account("aa")]), followers: nil), named: "daily-2023-11-14.json", in: local, modified: 1_700_000_000)
        let model = AppModel(environment: TestSupport.environment(local: local))
        model.prepareRestore()
        try writeSnapshot(BackupSnapshot(state: state([account("zz")]), followers: nil), named: "daily-2023-11-15.json", in: local, modified: 1_700_100_000)

        model.confirmRestore()

        #expect(model.errorMessage == "I file sono cambiati nel frattempo: riprova il ripristino.")
        #expect(model.loadError != nil)
        #expect(model.pendingRestore == nil)
        #expect(!FileManager.default.fileExists(atPath: local.appendingPathComponent("state.json").path))
    }

    @Test func restoreTextShowsBothDatesWhenTheListsComeFromTwoBackups() {
        var older = followers([account("ff", decision: .remove)])
        older.savedAt = Date(timeIntervalSince1970: 1_600_000_000)
        let plan = RestorePlan(state: state([account("aa", decision: .keep)]), followers: older, discardsFollowers: false, isFromTwoBackups: true)
        let stateDate = Date(timeIntervalSince1970: 1_700_000_000).formatted(date: .abbreviated, time: .shortened)
        let followersDate = older.savedAt.formatted(date: .abbreviated, time: .shortened)

        #expect(plan.title == "Ripristinare le copie di sicurezza?")
        #expect(plan.message.contains("Following: 1 decisioni dalla copia del \(stateDate)."))
        #expect(plan.message.contains("Follower: 1 decisioni dalla copia del \(followersDate)."))
    }

    @Test func restoreTextNamesOnlyTheRestoredLists() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var restoredState = state([account("aa", decision: .keep), account("bb")])
        restoredState.savedAt = date
        let stateOnly = RestorePlan(state: restoredState, followers: nil, discardsFollowers: false)
        let followersOnly = RestorePlan(state: nil, followers: followers([account("ff", decision: .remove), account("gg", decision: .keep)]), discardsFollowers: false)
        let discardOnly = RestorePlan(state: nil, followers: nil, discardsFollowers: true)

        #expect(stateOnly.title.hasPrefix("Ripristinare la copia del "))
        #expect(stateOnly.message.contains("Following: 1 decisioni"))
        #expect(stateOnly.message.contains("I follower restano come sono."))
        #expect(followersOnly.message.contains("Follower: 2 decisioni"))
        #expect(followersOnly.message.contains("I following restano come sono."))
        #expect(discardOnly.title == "Mettere da parte i follower illeggibili?")
        #expect(discardOnly.message.contains("reimporta"))
    }

    // MARK: Followers saved by another device while this one runs

    /// This device has its own state.json and no followers.json, so it never looked in iCloud for
    /// one; another device then mirrored its follower list there.
    private func modelWithCloudFollowersArrivingLater() throws -> (model: AppModel, local: URL, cloud: URL) {
        let local = try TestSupport.makeDirectory()
        let cloud = try TestSupport.makeDirectory()
        try seed(local, state: state([account("aa", followsMe: true), account("bb")]))
        let model = AppModel(environment: TestSupport.environment(local: local, cloud: cloud))
        #expect(model.rootScreen == .main)
        #expect(model.followers == nil)
        return (model, local, cloud)
    }

    private func cloudFollowers(_ cloud: URL) throws -> FollowerState? {
        let url = cloud.appendingPathComponent("followers.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try StateCoding.decoder().decode(FollowerState.self, from: Data(contentsOf: url))
    }

    @Test func importMergesIntoFollowersAnotherDeviceSavedToICloud() async throws {
        let (model, local, cloud) = try modelWithCloudFollowersArrivingLater()
        let removedAt = Date()
        var removed = account("aa", decision: .remove)
        removed.decidedAt = removedAt
        removed.unfollowedManually = true
        removed.unfollowedAt = removedAt
        let other = followers([removed, account("cc", decision: .keep)], decisions: 2)
        try StateCoding.encoder().encode(other).write(to: cloud.appendingPathComponent("followers.json"))

        await model.prepareImport(picked: [try TestSupport.makeExport(["aa", "bb"], followers: ["aa", "cc", "dd"])])

        #expect(model.pendingFollowerMerge?.summary.newAccounts == 1)
        #expect(model.followers?.accounts.map(\.username) == ["aa", "cc"])
        #expect(model.state?.accounts.first { $0.username == "aa" }?.followsMe == false)

        model.confirmImport()

        let decisions = Dictionary(uniqueKeysWithValues: (model.followers?.accounts ?? []).map { ($0.username, $0.decision) })
        #expect(decisions == ["aa": .remove, "cc": .keep, "dd": .pending])
        #expect(model.followers?.totalDecisionsMade == 2)
        #expect(try loadFollowers(local)?.accounts.first { $0.username == "cc" }?.decision == .keep)
        #expect(model.state?.accounts.first { $0.username == "aa" }?.followsMe == false)
    }

    /// The list was adopted by an earlier prepare; confirm alone must also look, in case it was not.
    @Test func confirmImportAlsoAdoptsCloudFollowers() async throws {
        let (model, _, cloud) = try modelWithCloudFollowersArrivingLater()
        await model.prepareImport(picked: [try TestSupport.makeExport(["aa", "bb"], followers: ["aa", "cc"])])
        try StateCoding.encoder().encode(followers([account("cc", decision: .keep)], decisions: 1))
            .write(to: cloud.appendingPathComponent("followers.json"))

        model.confirmImport()

        #expect(model.followers?.accounts.first { $0.username == "cc" }?.decision == .keep)
        #expect(model.followers?.totalDecisionsMade == 1)
    }

    @Test func importWaitsWhileCloudFollowersDownload() async throws {
        let (model, local, cloud) = try modelWithCloudFollowersArrivingLater()
        try Data("placeholder".utf8).write(to: cloud.appendingPathComponent(".followers.json.icloud"))

        await model.prepareImport(picked: [try TestSupport.makeExport(["aa", "bb"], followers: ["aa", "cc"])])

        #expect(model.errorMessage == "I follower stanno arrivando da iCloud, riprova tra poco.")
        #expect(model.pendingMerge == nil)
        #expect(model.pendingFollowerMerge == nil)
        #expect(model.loadError == nil)
        #expect(!FileManager.default.fileExists(atPath: local.appendingPathComponent("followers.json").path))
    }

    @Test func confirmImportWaitsWhileCloudFollowersDownload() async throws {
        let (model, local, cloud) = try modelWithCloudFollowersArrivingLater()
        await model.prepareImport(picked: [try TestSupport.makeExport(["aa", "bb"], followers: ["aa", "cc"])])
        let stateBefore = try fileData("state.json", in: local)
        try Data("placeholder".utf8).write(to: cloud.appendingPathComponent(".followers.json.icloud"))

        model.confirmImport()

        #expect(model.errorMessage == "I follower stanno arrivando da iCloud, riprova tra poco.")
        #expect(model.followers == nil)
        #expect(model.pendingMerge != nil)
        #expect(try fileData("state.json", in: local) == stateBefore)
        #expect(!FileManager.default.fileExists(atPath: local.appendingPathComponent("followers.json").path))
        #expect(try cloudFollowers(cloud) == nil)
    }

    @Test func importBlocksLikeALoadFailureWhenCloudFollowersAreUnreadable() async throws {
        let (model, local, cloud) = try modelWithCloudFollowersArrivingLater()
        try Data("not json".utf8).write(to: cloud.appendingPathComponent("followers.json"))
        let stateBefore = try fileData("state.json", in: local)

        await model.prepareImport(picked: [try TestSupport.makeExport(["aa", "bb"], followers: ["aa", "cc"])])
        model.confirmImport()

        #expect(model.loadError != nil)
        #expect(model.isBlocked)
        #expect(model.quarantinedFileNames.contains { $0.hasPrefix("followers.corrupt-") })
        #expect(model.pendingMerge == nil)
        #expect(model.followers == nil)
        #expect(try fileData("state.json", in: local) == stateBefore)
        #expect(!FileManager.default.fileExists(atPath: local.appendingPathComponent("followers.json").path))
    }

    @Test func confirmImportBlocksWhenCloudFollowersBecameUnreadable() async throws {
        let (model, local, cloud) = try modelWithCloudFollowersArrivingLater()
        await model.prepareImport(picked: [try TestSupport.makeExport(["aa", "bb"], followers: ["aa", "cc"])])
        try Data("not json".utf8).write(to: cloud.appendingPathComponent("followers.json"))

        model.confirmImport()

        #expect(model.loadError != nil)
        #expect(model.quarantinedFileNames.contains { $0.hasPrefix("followers.corrupt-") })
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

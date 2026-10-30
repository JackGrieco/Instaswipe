import Foundation
import Testing
@testable import InstaSwipeKit

struct FollowerMergeTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let removedAt = Fixtures.referenceDate
    private static let dayLength: TimeInterval = 86_400

    private static func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

    private static func export(_ username: String, _ since: Date?) -> ExportedFollow {
        ExportedFollow(
            username: username,
            profileURL: URL(string: "https://www.instagram.com/_u/\(username)")!,
            followedSince: since
        )
    }

    private static func removedFollower(_ username: String) -> FollowedAccount {
        FollowedAccount(
            username: username,
            profileURL: URL(string: "https://www.instagram.com/_u/\(username)")!,
            followedSince: at(100),
            decision: .remove,
            decidedAt: removedAt,
            unfollowedManually: true,
            unfollowedAt: removedAt
        )
    }

    @Test func firstImportCreatesFollowersInReviewOrder() {
        let result = MergeEngine.previewFollowers(
            current: nil,
            exported: [Self.export("bb", Self.at(200)), Self.export("aa", Self.at(100))],
            now: Self.now
        )

        #expect(result.followers.accounts.map(\.username) == ["aa", "bb"])
        #expect(result.followers.accounts.allSatisfy { $0.decision == .pending })
        #expect(result.summary.newAccounts == 2)
    }

    @Test func goneFollowerLeavesThePile() {
        let current = Fixtures.followers([Fixtures.account("aa", since: Self.at(100))])

        let result = MergeEngine.previewFollowers(current: current, exported: [], now: Self.now)

        #expect(result.followers.accounts[0].stillInLatestExport == false)
        #expect(result.summary.noLongerFollowed == 1)
    }

    @Test func goneFollowerMarkedRemoveIsAutoDone() {
        let current = Fixtures.followers([Fixtures.account("aa", since: Self.at(100), decision: .remove)])

        let result = MergeEngine.previewFollowers(current: current, exported: [], now: Self.now)

        let account = result.followers.accounts[0]
        #expect(account.unfollowedManually == true)
        #expect(account.unfollowedAt == nil)
        #expect(result.summary.autoMarkedDone == 1)
    }

    @Test func refollowAfterRemovalReopens() {
        let current = Fixtures.followers([Self.removedFollower("aa")])
        let newDate = Self.removedAt.addingTimeInterval(Self.dayLength)

        let result = MergeEngine.previewFollowers(current: current, exported: [Self.export("aa", newDate)], now: Self.now)

        let account = result.followers.accounts[0]
        #expect(account.decision == .pending)
        #expect(account.decidedAt == nil)
        #expect(account.unfollowedManually == false)
        #expect(account.unfollowedAt == nil)
        #expect(account.followedSince == newDate)
        #expect(result.summary.refollowed == 1)
    }

    /// The real shape: removed, then gone from an export (no longer following), then back with a
    /// later "ti segue dal".
    @Test func refollowAfterLeavingTheExportReopens() {
        var gone = Self.removedFollower("aa")
        gone.stillInLatestExport = false
        let current = Fixtures.followers([gone])
        let newDate = Self.removedAt.addingTimeInterval(Self.dayLength)

        let result = MergeEngine.previewFollowers(current: current, exported: [Self.export("aa", newDate)], now: Self.now)

        let account = result.followers.accounts[0]
        #expect(account.decision == .pending)
        #expect(account.unfollowedManually == false)
        #expect(account.stillInLatestExport == true)
        #expect(account.followedSince == newDate)
        #expect(result.summary.refollowed == 1)
    }

    @Test func olderExportKeepsRemovedFollowerDone() {
        let current = Fixtures.followers([Self.removedFollower("aa")])
        let older = Self.removedAt.addingTimeInterval(-Self.dayLength)

        let result = MergeEngine.previewFollowers(current: current, exported: [Self.export("aa", older)], now: Self.now)

        let account = result.followers.accounts[0]
        #expect(account.decision == .remove)
        #expect(account.unfollowedManually == true)
        #expect(result.summary.refollowed == 0)
    }

    @Test func refollowWithoutDateKeepsRemovedFollowerDone() {
        let current = Fixtures.followers([Self.removedFollower("aa")])

        let result = MergeEngine.previewFollowers(current: current, exported: [Self.export("aa", nil)], now: Self.now)

        let account = result.followers.accounts[0]
        #expect(account.decision == .remove)
        #expect(account.unfollowedManually == true)
        #expect(result.summary.refollowed == 0)
    }

    @Test func suspiciousWhenMostFollowersVanish() {
        let names = (0..<10).map { "user\($0)" }
        let current = Fixtures.followers(names.map { Fixtures.account($0, since: Self.at(100)) })
        let exported = names.prefix(5).map { Self.export($0, Self.at(100)) }

        let result = MergeEngine.previewFollowers(current: current, exported: Array(exported), now: Self.now)

        #expect(result.summary.isSuspicious == true)
    }

    @Test func followingMergeNeverReopensManualDone() {
        let current = Fixtures.state([Self.removedFollower("aa")])
        let later = Self.removedAt.addingTimeInterval(Self.dayLength)
        let snapshot = ExportSnapshot(follows: [Self.export("aa", later)], followers: nil)

        let result = MergeEngine.preview(current: current, snapshot: snapshot, now: Self.now)

        let account = result.state.accounts[0]
        #expect(account.decision == .remove)
        #expect(account.unfollowedManually == true)
        #expect(result.summary.refollowed == 0)
    }
}

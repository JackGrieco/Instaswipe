import Foundation
import Testing
@testable import InstaSwipeKit

struct MergeEngineTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static func day(_ n: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(1_600_000_000 + n * 86_400)) }

    private static func follow(_ username: String, _ n: Int?) -> ExportedFollow {
        ExportedFollow(
            username: username,
            profileURL: URL(string: "https://www.instagram.com/_u/\(username)")!,
            followedSince: n.map(day)
        )
    }

    private static func snapshot(_ follows: [ExportedFollow], followers: Set<String> = []) -> ExportSnapshot {
        ExportSnapshot(follows: follows, followers: followers)
    }

    @Test func firstImportCreatesPendingAccountsInOldestFirstOrder() {
        let snap = Self.snapshot([Self.follow("c", 3), Self.follow("b", 2), Self.follow("a", 1)], followers: ["b"])

        let preview = MergeEngine.preview(current: nil, snapshot: snap, now: Self.now)

        #expect(preview.state.accounts.map(\.username) == ["a", "b", "c"])
        #expect(preview.state.accounts.allSatisfy { $0.decision == .pending && $0.availability == .unknown && $0.stillInLatestExport })
        #expect(preview.state.accounts.first { $0.username == "b" }?.followsMe == true)
        #expect(preview.state.savedAt == Self.now)
        #expect(preview.summary == MergeSummary(newAccounts: 3, noLongerFollowed: 0, autoMarkedDone: 0, isSuspicious: false))
    }

    @Test func reimportKeepsDecisionsAndUpdatesFollowsMe() {
        var kept = Fixtures.account("a", since: Self.day(1), decision: .keep, followsMe: false)
        kept.decidedAt = Self.day(5)
        let current = Fixtures.state([kept])
        let snap = Self.snapshot([Self.follow("a", 1)], followers: ["a"])

        let result = MergeEngine.preview(current: current, snapshot: snap, now: Self.now).state.accounts[0]

        #expect(result.decision == .keep)
        #expect(result.decidedAt == Self.day(5))
        #expect(result.followsMe == true)
    }

    @Test func reimportAddsNewAccountsInChronologicalPosition() {
        let current = Fixtures.state([Fixtures.account("a", since: Self.day(1)), Fixtures.account("c", since: Self.day(3))])
        let snap = Self.snapshot([Self.follow("c", 3), Self.follow("b", 2), Self.follow("a", 1)])

        let preview = MergeEngine.preview(current: current, snapshot: snap, now: Self.now)

        #expect(preview.state.accounts.map(\.username) == ["a", "b", "c"])
        #expect(preview.summary.newAccounts == 1)
    }

    @Test func removedAndMissingIsAutoMarkedDoneWithoutDate() {
        let current = Fixtures.state([Fixtures.account("a", since: Self.day(1), decision: .remove)])

        let preview = MergeEngine.preview(current: current, snapshot: Self.snapshot([]), now: Self.now)

        let account = preview.state.accounts[0]
        #expect(account.unfollowedManually == true)
        #expect(account.unfollowedAt == nil)
        #expect(account.stillInLatestExport == false)
        #expect(preview.summary.autoMarkedDone == 1)
        #expect(preview.summary.noLongerFollowed == 1)
    }

    @Test func keptAndMissingIsHiddenNotDeleted() {
        let current = Fixtures.state([Fixtures.account("a", since: Self.day(1), decision: .keep)])

        let preview = MergeEngine.preview(current: current, snapshot: Self.snapshot([]), now: Self.now)

        #expect(preview.state.accounts.count == 1)
        #expect(preview.state.accounts[0].stillInLatestExport == false)
        #expect(preview.state.accounts[0].decision == .keep)
        #expect(preview.summary.autoMarkedDone == 0)
    }

    @Test func unavailableAccountIsRecheckedOnReimport() {
        let current = Fixtures.state([Fixtures.account("a", since: Self.day(1), availability: .unavailable)])

        let preview = MergeEngine.preview(current: current, snapshot: Self.snapshot([Self.follow("a", 1)]), now: Self.now)

        #expect(preview.state.accounts[0].availability == .unknown)
    }

    @Test func reimportSameExportIsNoOp() {
        let current = Fixtures.state([
            Fixtures.account("a", since: Self.day(1), decision: .keep),
            Fixtures.account("b", since: Self.day(2), decision: .remove, unfollowedManually: true)
        ])
        let snap = Self.snapshot([Self.follow("a", 1), Self.follow("b", 2)])

        let preview = MergeEngine.preview(current: current, snapshot: snap, now: Self.now)

        #expect(preview.summary == MergeSummary(newAccounts: 0, noLongerFollowed: 0, autoMarkedDone: 0, isSuspicious: false))
        #expect(preview.state.accounts == current.accounts)
    }

    @Test func losingMoreThan20PercentIsSuspicious() {
        let names = (1...10).map { "u\($0)" }
        let current = Fixtures.state(names.enumerated().map { Fixtures.account($1, since: Self.day($0)) })

        func summary(keeping count: Int) -> MergeSummary {
            let snap = Self.snapshot(names.prefix(count).enumerated().map { Self.follow($1, $0) })
            return MergeEngine.preview(current: current, snapshot: snap, now: Self.now).summary
        }

        #expect(summary(keeping: 7).isSuspicious == true)
        #expect(summary(keeping: 8).isSuspicious == false)
    }

    @Test func reappearingAccountIsRestoredAndNotCountedAsNew() {
        let current = Fixtures.state([Fixtures.account("a", since: Self.day(1), decision: .keep, stillInLatestExport: false)])

        let preview = MergeEngine.preview(current: current, snapshot: Self.snapshot([Self.follow("a", 1)]), now: Self.now)

        #expect(preview.state.accounts[0].stillInLatestExport == true)
        #expect(preview.summary.newAccounts == 0)
        #expect(preview.summary.noLongerFollowed == 0)
    }

    @Test func reappearingAutoDoneAccountReturnsToDo() {
        let autoDone = Fixtures.account(
            "a", since: Self.day(1), decision: .remove, unfollowedManually: true, stillInLatestExport: false
        )

        let preview = MergeEngine.preview(current: Fixtures.state([autoDone]), snapshot: Self.snapshot([Self.follow("a", 1)]), now: Self.now)

        let account = preview.state.accounts[0]
        #expect(account.decision == .remove)
        #expect(account.unfollowedManually == false)
        #expect(account.unfollowedAt == nil)
        #expect(account.stillInLatestExport == true)
    }

    @Test func reappearingManuallyDoneAccountStaysDone() {
        var manualDone = Fixtures.account(
            "a", since: Self.day(1), decision: .remove, unfollowedManually: true, stillInLatestExport: false
        )
        manualDone.unfollowedAt = Self.day(9)

        let preview = MergeEngine.preview(current: Fixtures.state([manualDone]), snapshot: Self.snapshot([Self.follow("a", 1)]), now: Self.now)

        #expect(preview.state.accounts[0].unfollowedManually == true)
        #expect(preview.state.accounts[0].unfollowedAt == Self.day(9))
    }

    @Test func autoDoneStillInExportIsNotReset() {
        let autoDoneStillActive = Fixtures.account("a", since: Self.day(1), decision: .remove, unfollowedManually: true)

        let preview = MergeEngine.preview(
            current: Fixtures.state([autoDoneStillActive]), snapshot: Self.snapshot([Self.follow("a", 1)]), now: Self.now
        )

        #expect(preview.state.accounts[0].unfollowedManually == true)
    }

    @Test func emptyActiveSetIsNeverSuspicious() {
        let current = Fixtures.state([Fixtures.account("a", since: Self.day(1), stillInLatestExport: false)])

        let preview = MergeEngine.preview(current: current, snapshot: Self.snapshot([]), now: Self.now)

        #expect(preview.summary.isSuspicious == false)
    }

    @Test func previewDoesNotMutateInputsOrTouchSavedAtOfExistingState() {
        let current = Fixtures.state([Fixtures.account("a", since: Self.day(1))])

        let preview = MergeEngine.preview(current: current, snapshot: Self.snapshot([]), now: Self.now)

        #expect(preview.state.savedAt == current.savedAt)
        #expect(current.accounts[0].stillInLatestExport == true)
    }
}

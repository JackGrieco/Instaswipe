import Foundation
import Testing
@testable import InstaSwipeKit

struct ReviewTests {
    private let t0 = Fixtures.referenceDate
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }
    private func day(_ n: Double) -> Date { Date(timeIntervalSince1970: n * 86_400) }

    private func threeAccounts() -> AppState {
        Fixtures.state([
            Fixtures.account("a", since: day(1)),
            Fixtures.account("b", since: day(2)),
            Fixtures.account("c", since: day(3))
        ])
    }

    private func account(_ username: String, in state: AppState) -> FollowedAccount {
        state.accounts.first { $0.username == username }!
    }

    @Test func currentIsOldestPendingSkippingUnavailableAndHidden() {
        let state = Fixtures.state([
            Fixtures.account("a", since: day(1), availability: .unavailable),
            Fixtures.account("b", since: day(2), stillInLatestExport: false),
            Fixtures.account("c", since: day(3), decision: .keep),
            Fixtures.account("d", since: day(4)),
            Fixtures.account("e", since: day(5))
        ])
        #expect(Review.current(in: state)?.username == "d")
    }

    @Test func currentIsNilWhenNothingPending() {
        let state = Fixtures.state([Fixtures.account("a", since: day(1), decision: .keep)])
        #expect(Review.current(in: state) == nil)
    }

    @Test func nextSkipsTheSameWay() {
        let state = Fixtures.state([
            Fixtures.account("a", since: day(1)),
            Fixtures.account("b", since: day(2), availability: .unavailable),
            Fixtures.account("c", since: day(3), stillInLatestExport: false),
            Fixtures.account("d", since: day(4), decision: .remove),
            Fixtures.account("e", since: day(5))
        ])
        #expect(Review.next(after: "a", in: state)?.username == "e")
        #expect(Review.next(after: "e", in: state) == nil)
        #expect(Review.next(after: "missing", in: state) == nil)
    }

    @Test func decideSetsDecisionDateAndCounter() {
        let result = Review.decide(.keep, username: "b", in: threeAccounts(), now: at(10))
        #expect(account("b", in: result).decision == .keep)
        #expect(account("b", in: result).decidedAt == at(10))
        #expect(result.totalDecisionsMade == 1)
    }

    @Test func decidePendingClearsDate() {
        let decided = Review.decide(.remove, username: "a", in: threeAccounts(), now: at(10))
        let result = Review.decide(.pending, username: "a", in: decided, now: at(20))
        #expect(account("a", in: result).decision == .pending)
        #expect(account("a", in: result).decidedAt == nil)
        #expect(result.totalDecisionsMade == 1)
    }

    @Test func decideSameDecisionRefreshesDateAndCountsAgain() {
        let first = Review.decide(.keep, username: "a", in: threeAccounts(), now: at(10))
        let second = Review.decide(.keep, username: "a", in: first, now: at(20))
        #expect(account("a", in: second).decidedAt == at(20))
        #expect(second.totalDecisionsMade == 2)
    }

    @Test(arguments: [Decision.keep, .pending])
    func decideAwayFromRemoveClearsDoneFlag(_ decision: Decision) {
        var state = Review.decide(.remove, username: "a", in: threeAccounts(), now: at(1))
        state.accounts[0].unfollowedManually = true
        state.accounts[0].unfollowedAt = at(5)
        let result = Review.decide(decision, username: "a", in: state, now: at(10))
        #expect(account("a", in: result).unfollowedManually == false)
        #expect(account("a", in: result).unfollowedAt == nil)
    }

    @Test func decideRemoveAgainKeepsDoneFlag() {
        var state = Review.decide(.remove, username: "a", in: threeAccounts(), now: at(1))
        state.accounts[0].unfollowedManually = true
        state.accounts[0].unfollowedAt = at(5)
        let result = Review.decide(.remove, username: "a", in: state, now: at(10))
        #expect(account("a", in: result).unfollowedManually == true)
        #expect(account("a", in: result).unfollowedAt == at(5))
    }

    @Test func decideUnknownUsernameIsNoOp() {
        let state = threeAccounts()
        #expect(Review.decide(.keep, username: "zzz", in: state, now: at(10)) == state)
    }

    @Test func decideDoesNotMutateInput() {
        let state = threeAccounts()
        let copy = state
        _ = Review.decide(.remove, username: "a", in: state, now: at(10))
        #expect(state == copy)
    }

    @Test func undoRevertsMostRecentDecision() {
        var state = Review.decide(.remove, username: "a", in: threeAccounts(), now: at(1))
        state = Review.decide(.keep, username: "b", in: state, now: at(2))
        let result = Review.undo(in: state)
        #expect(account("b", in: result).decision == .pending)
        #expect(account("b", in: result).decidedAt == nil)
        #expect(account("a", in: result).decision == .remove)
    }

    @Test func undoClearsDoneFlag() {
        var state = Review.decide(.remove, username: "a", in: threeAccounts(), now: at(1))
        state.accounts[0].unfollowedManually = true
        state.accounts[0].unfollowedAt = at(5)
        let result = Review.undo(in: state)
        #expect(account("a", in: result).decision == .pending)
        #expect(account("a", in: result).unfollowedManually == false)
        #expect(account("a", in: result).unfollowedAt == nil)
        #expect(account("a", in: result).decidedAt == nil)
    }

    @Test func undoWithNothingDecidedIsNoOp() {
        let state = threeAccounts()
        #expect(Review.undo(in: state) == state)
    }

    @Test func undoTieBreaksToLaterAccountInOrder() {
        var state = Review.decide(.keep, username: "a", in: threeAccounts(), now: at(1))
        state = Review.decide(.keep, username: "c", in: state, now: at(1))
        let result = Review.undo(in: state)
        #expect(account("c", in: result).decision == .pending)
        #expect(account("a", in: result).decision == .keep)
    }

    @Test func unsureAccountsComeBackAfterThePendingOnes() {
        var state = Review.decide(.unsure, username: "a", in: threeAccounts(), now: at(1))
        #expect(Review.current(in: state)?.username == "b")
        #expect(Review.next(after: "b", in: state)?.username == "c")
        #expect(Review.next(after: "c", in: state)?.username == "a")

        state = Review.decide(.keep, username: "b", in: state, now: at(2))
        state = Review.decide(.remove, username: "c", in: state, now: at(3))
        #expect(Review.current(in: state)?.username == "a")
        #expect(Review.next(after: "a", in: state) == nil)
    }

    @Test func unsureAgainSendsTheAccountToTheBackOfTheDoubts() {
        var state = Review.decide(.unsure, username: "a", in: threeAccounts(), now: at(1))
        state = Review.decide(.unsure, username: "b", in: state, now: at(2))
        state = Review.decide(.keep, username: "c", in: state, now: at(3))
        #expect(Review.current(in: state)?.username == "a")

        state = Review.decide(.unsure, username: "a", in: state, now: at(4))

        #expect(Review.current(in: state)?.username == "b")
        #expect(Review.next(after: "b", in: state)?.username == "a")
    }

    @Test func progressCountsOnlyKeepAndRemoveAsDecided() {
        var state = Review.decide(.unsure, username: "a", in: threeAccounts(), now: at(1))
        state = Review.decide(.keep, username: "b", in: state, now: at(2))
        #expect(Review.progress(in: state) == ReviewProgress(decided: 1, total: 3))
    }

    @Test func undoRevertsAnUnsureDecision() {
        let state = Review.decide(.unsure, username: "a", in: threeAccounts(), now: at(1))
        #expect(account("a", in: Review.undo(in: state)).decision == .pending)
    }

    @Test func lastDecidedIsTheAccountUndoWouldRevert() {
        var state = Review.decide(.remove, username: "a", in: threeAccounts(), now: at(2))
        state = Review.decide(.keep, username: "b", in: state, now: at(1))
        #expect(Review.lastDecided(in: state)?.username == "a")
        #expect(Review.lastDecided(in: state)?.decision == .remove)
    }

    @Test func lastDecidedIsNilWithNothingDecided() {
        #expect(Review.lastDecided(in: threeAccounts()) == nil)
    }

    @Test func markAvailabilityKeepsExistingDecision() {
        let decided = Review.decide(.remove, username: "a", in: threeAccounts(), now: at(1))
        let result = Review.markAvailability(.unavailable, displayName: nil, username: "a", in: decided)
        #expect(account("a", in: result).decision == .remove)
        #expect(account("a", in: result).availability == .unavailable)
    }

    @Test func markAvailabilityUpdatesDisplayNameOnlyWhenGiven() {
        let named = Review.markAvailability(.available, displayName: "Alice", username: "a", in: threeAccounts())
        #expect(account("a", in: named).displayName == "Alice")
        let kept = Review.markAvailability(.available, displayName: nil, username: "a", in: named)
        #expect(account("a", in: kept).displayName == "Alice")
    }

    @Test func markAvailabilityUnknownUsernameIsNoOp() {
        let state = threeAccounts()
        #expect(Review.markAvailability(.available, displayName: "X", username: "zzz", in: state) == state)
    }

    @Test func progressExcludesUnavailableAndHidden() {
        let state = Fixtures.state([
            Fixtures.account("a", since: day(1), decision: .keep),
            Fixtures.account("b", since: day(2)),
            Fixtures.account("c", since: day(3)),
            Fixtures.account("d", since: day(4), availability: .unavailable),
            Fixtures.account("e", since: day(5), stillInLatestExport: false)
        ])
        #expect(Review.progress(in: state) == ReviewProgress(decided: 1, total: 3))
    }
}

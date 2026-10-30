import Foundation
import Testing
@testable import InstaSwipeKit

struct FollowerStateTests {
    private let t0 = Fixtures.referenceDate
    private func day(_ n: Double) -> Date { Date(timeIntervalSince1970: n * 86_400) }

    @Test func followerStateRoundTripsThroughStateCoding() throws {
        let original = Fixtures.followers([
            Fixtures.account("aa", since: day(1)),
            Fixtures.account("bb", since: day(2), decision: .remove)
        ])

        let data = try StateCoding.encoder().encode(original)
        let decoded = try StateCoding.decoder().decode(FollowerState.self, from: data)

        #expect(decoded == original)
    }

    @Test func reviewWorksOnFollowerState() {
        let state = Fixtures.followers([
            Fixtures.account("aa", since: day(1)),
            Fixtures.account("bb", since: day(2))
        ])
        #expect(Review.current(in: state)?.username == "aa")

        let decided = Review.decide(.remove, username: "aa", in: state, now: t0)
        #expect(Review.current(in: decided)?.username == "bb")
        #expect(decided.totalDecisionsMade == 1)

        let undone = Review.undo(in: decided)
        #expect(Review.current(in: undone)?.username == "aa")
    }

    @Test func reportWorksOnFollowerState() {
        let state = Fixtures.followers([Fixtures.account("aa", since: day(1), decision: .remove)])
        #expect(Report.counts(in: state)[.toDo] == 1)

        let done = Report.setUnfollowed(true, username: "aa", in: state, now: t0)
        #expect(Report.counts(in: done)[.done] == 1)
    }

    @Test func appStateListRoundTrip() {
        let original = Fixtures.state([Fixtures.account("old", since: day(1))])
        let replacement = Fixtures.account("x", since: day(2))

        var updated = original
        updated.list = AccountList(accounts: [replacement], totalDecisionsMade: 7)

        #expect(updated.accounts == [replacement])
        #expect(updated.totalDecisionsMade == 7)
        #expect(updated.profileLoads == original.profileLoads)
        #expect(updated.dailyProfileLimit == original.dailyProfileLimit)
        #expect(updated.savedAt == original.savedAt)
    }
}

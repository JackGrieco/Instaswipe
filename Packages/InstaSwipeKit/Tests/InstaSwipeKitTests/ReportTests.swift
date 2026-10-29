import Testing
import Foundation
@testable import InstaSwipeKit

@Suite struct ReportTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        return calendar
    }

    private static func usernames(_ accounts: [FollowedAccount]) -> [String] { accounts.map(\.username) }

    private static var mixedState: AppState {
        var luca = Fixtures.account("luca_x", since: Fixtures.referenceDate, decision: .keep)
        luca.displayName = "Luca"
        return Fixtures.state([
            Fixtures.account("todo", since: nil, decision: .remove),
            Fixtures.account("done", since: nil, decision: .remove, unfollowedManually: true),
            Fixtures.account("gone", since: nil, decision: .remove, availability: .unavailable),
            Fixtures.account("goneExport", since: nil, decision: .keep, availability: .unavailable, stillInLatestExport: false),
            luca,
            Fixtures.account("pending", since: nil),
            Fixtures.account("doubt", since: nil, decision: .unsure),
            Fixtures.account("goneDoubt", since: nil, decision: .unsure, availability: .unavailable)
        ])
    }

    @Test func toDoListsRemovedNotDoneAndNotGone() {
        let result = Report.accounts(.toDo, search: "", in: Self.mixedState)
        #expect(Self.usernames(result) == ["todo"])
    }

    @Test func doneGoneAndKeptFiltersApply() {
        let state = Self.mixedState
        #expect(Self.usernames(Report.accounts(.done, search: "", in: state)) == ["done"])
        #expect(Self.usernames(Report.accounts(.gone, search: "", in: state)) == ["gone", "goneDoubt"])
        #expect(Self.usernames(Report.accounts(.kept, search: "", in: state)) == ["goneExport", "luca_x"])
        #expect(Self.usernames(Report.accounts(.unsure, search: "", in: state)) == ["doubt"])
    }

    @Test func countsMatchFilters() {
        let counts = Report.counts(in: Self.mixedState)
        #expect(counts == [.toDo: 1, .unsure: 1, .done: 1, .gone: 2, .kept: 2])
    }

    @Test func searchIgnoresFilterAndMatchesDisplayNameWithoutAccents() {
        let result = Report.accounts(.toDo, search: "lucà", in: Self.mixedState)
        #expect(Self.usernames(result) == ["luca_x"])
    }

    @Test func searchMatchesUsernameCaseInsensitivelyAndExcludesPending() {
        let state = Self.mixedState
        #expect(Self.usernames(Report.accounts(.done, search: "  TO", in: state)) == ["todo"])
        #expect(Report.accounts(.toDo, search: "pend", in: state).isEmpty)
    }

    @Test func whitespaceOnlySearchAppliesFilter() {
        let result = Report.accounts(.toDo, search: "   ", in: Self.mixedState)
        #expect(Self.usernames(result) == ["todo"])
    }

    @Test func setUnfollowedStampsAndClearsDate() {
        let state = Fixtures.state([Fixtures.account("a", since: nil, decision: .remove)])
        let done = Report.setUnfollowed(true, username: "a", in: state, now: Fixtures.referenceDate)
        #expect(done.accounts[0].unfollowedManually)
        #expect(done.accounts[0].unfollowedAt == Fixtures.referenceDate)
        let undone = Report.setUnfollowed(false, username: "a", in: done, now: Fixtures.referenceDate)
        #expect(!undone.accounts[0].unfollowedManually)
        #expect(undone.accounts[0].unfollowedAt == nil)
        #expect(state.accounts[0].unfollowedAt == nil)
    }

    @Test func setUnfollowedWithUnknownUsernameLeavesStateUnchanged() {
        let state = Fixtures.state([Fixtures.account("a", since: nil)])
        #expect(Report.setUnfollowed(true, username: "zzz", in: state, now: Fixtures.referenceDate) == state)
    }

    @Test func unfollowsTodayCountsOnlyToday() {
        let calendar = Self.calendar
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 12))!
        let earlier = calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 0, minute: 1))!
        let yesterday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 23, minute: 59))!
        var state = Fixtures.state([
            Fixtures.account("a", since: nil, decision: .remove),
            Fixtures.account("b", since: nil, decision: .remove),
            Fixtures.account("c", since: nil, decision: .remove),
            Fixtures.account("d", since: nil, decision: .remove)
        ])
        state.accounts[0].unfollowedAt = now
        state.accounts[1].unfollowedAt = earlier
        state.accounts[2].unfollowedAt = yesterday
        #expect(Report.unfollowsToday(in: state, now: now, calendar: calendar) == 2)
    }
}

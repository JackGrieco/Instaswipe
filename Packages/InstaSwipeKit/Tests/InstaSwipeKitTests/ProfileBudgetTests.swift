import Testing
import Foundation
@testable import InstaSwipeKit

@Suite struct ProfileBudgetTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        return calendar
    }

    private static func date(day: Int, hour: Int, minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private static func state(loads: Int, on day: Int) -> AppState {
        var state = Fixtures.state([])
        state.profileLoads = DailyCount(day: calendar.startOfDay(for: date(day: day, hour: 8, minute: 0)), count: loads)
        return state
    }

    @Test func countersResetOnNewDay() {
        let late = Self.date(day: 29, hour: 23, minute: 59)
        let early = Self.date(day: 30, hour: 0, minute: 1)
        let state = Self.state(loads: 400, on: 29)
        #expect(ProfileBudget.status(in: state, now: late, calendar: Self.calendar) == .limitReached)
        #expect(ProfileBudget.status(in: state, now: early, calendar: Self.calendar) == .available(remaining: 400))
    }

    @Test func budgetReachesLimitAtDailyLimit() {
        let now = Self.date(day: 29, hour: 10, minute: 0)
        let state = Self.state(loads: 399, on: 29)
        #expect(ProfileBudget.status(in: state, now: now, calendar: Self.calendar) == .available(remaining: 1))
        let after = ProfileBudget.recordLoad(in: state, now: now, calendar: Self.calendar)
        #expect(after.profileLoads.count == 400)
        #expect(ProfileBudget.status(in: after, now: now, calendar: Self.calendar) == .limitReached)
        #expect(state.profileLoads.count == 399)
    }

    @Test func recordLoadOnNewDayResetsToOne() {
        let now = Self.date(day: 30, hour: 9, minute: 0)
        let result = ProfileBudget.recordLoad(in: Self.state(loads: 250, on: 29), now: now, calendar: Self.calendar)
        #expect(result.profileLoads == DailyCount(day: Self.calendar.startOfDay(for: now), count: 1))
    }

    @Test func emergencyStopBlocksTodayOnly() {
        let now = Self.date(day: 29, hour: 10, minute: 0)
        let stopped = ProfileBudget.recordEmergencyStop(in: Self.state(loads: 0, on: 29), now: now, calendar: Self.calendar)
        #expect(stopped.emergencyStopDay == Self.calendar.startOfDay(for: now))
        let later = Self.date(day: 29, hour: 23, minute: 0)
        #expect(ProfileBudget.status(in: stopped, now: later, calendar: Self.calendar) == .emergencyStopped)
    }

    @Test func emergencyStopExpiresNextDay() {
        let now = Self.date(day: 29, hour: 10, minute: 0)
        let stopped = ProfileBudget.recordEmergencyStop(in: Self.state(loads: 5, on: 29), now: now, calendar: Self.calendar)
        let tomorrow = Self.date(day: 30, hour: 0, minute: 1)
        #expect(ProfileBudget.status(in: stopped, now: tomorrow, calendar: Self.calendar) == .available(remaining: 400))
    }

    @Test func emergencyStopTakesPrecedenceOverLimit() {
        let now = Self.date(day: 29, hour: 10, minute: 0)
        let stopped = ProfileBudget.recordEmergencyStop(in: Self.state(loads: 400, on: 29), now: now, calendar: Self.calendar)
        #expect(ProfileBudget.status(in: stopped, now: now, calendar: Self.calendar) == .emergencyStopped)
    }

    @Test func dailyLimitIsClamped() {
        let state = Fixtures.state([])
        #expect(ProfileBudget.setDailyLimit(10, in: state).dailyProfileLimit == 50)
        #expect(ProfileBudget.setDailyLimit(99_999, in: state).dailyProfileLimit == 2000)
        #expect(ProfileBudget.setDailyLimit(700, in: state).dailyProfileLimit == 700)
    }
}

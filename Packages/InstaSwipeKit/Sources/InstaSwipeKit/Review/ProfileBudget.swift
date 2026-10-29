import Foundation

public enum BudgetStatus: Equatable, Sendable {
    case available(remaining: Int)
    case limitReached
    case emergencyStopped
}

/// Daily Instagram profile-load budget with emergency stop. Days are local (`calendar`).
public enum ProfileBudget {
    private static func loadsToday(_ state: AppState, now: Date, calendar: Calendar) -> Int {
        calendar.isDate(state.profileLoads.day, inSameDayAs: now) ? state.profileLoads.count : 0
    }

    public static func status(in state: AppState, now: Date, calendar: Calendar) -> BudgetStatus {
        if let stopDay = state.emergencyStopDay, calendar.isDate(stopDay, inSameDayAs: now) {
            return .emergencyStopped
        }
        let remaining = state.dailyProfileLimit - loadsToday(state, now: now, calendar: calendar)
        return remaining > 0 ? .available(remaining: remaining) : .limitReached
    }

    public static func recordLoad(in state: AppState, now: Date, calendar: Calendar) -> AppState {
        var next = state
        next.profileLoads = DailyCount(
            day: calendar.startOfDay(for: now),
            count: loadsToday(state, now: now, calendar: calendar) + 1
        )
        return next
    }

    public static func recordEmergencyStop(in state: AppState, now: Date, calendar: Calendar) -> AppState {
        var next = state
        next.emergencyStopDay = calendar.startOfDay(for: now)
        return next
    }

    public static func setDailyLimit(_ limit: Int, in state: AppState) -> AppState {
        var next = state
        next.dailyProfileLimit = min(max(limit, Limits.minDailyProfileLoads), Limits.maxDailyProfileLoads)
        return next
    }
}

import Foundation

public enum ReportFilter: String, CaseIterable, Sendable { case toDo, done, gone, kept }

/// Pure logic for the "Da togliere" list. Results keep `AppState.accounts` order.
public enum Report {
    private static func matches(_ filter: ReportFilter, _ account: FollowedAccount) -> Bool {
        switch filter {
        case .toDo: account.decision == .remove && !account.unfollowedManually && account.availability != .unavailable
        case .done: account.decision == .remove && account.unfollowedManually
        case .gone: account.availability == .unavailable && account.stillInLatestExport
        case .kept: account.decision == .keep
        }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func matchesSearch(_ query: String, _ account: FollowedAccount) -> Bool {
        account.decision != .pending
            && (fold(account.username).contains(query) || fold(account.displayName ?? "").contains(query))
    }

    public static func accounts(_ filter: ReportFilter, search: String, in state: AppState) -> [FollowedAccount] {
        let query = fold(search.trimmingCharacters(in: .whitespacesAndNewlines))
        if query.isEmpty { return state.accounts.filter { matches(filter, $0) } }
        return state.accounts.filter { matchesSearch(query, $0) }
    }

    public static func counts(in state: AppState) -> [ReportFilter: Int] {
        Dictionary(uniqueKeysWithValues: ReportFilter.allCases.map { filter in
            (filter, state.accounts.filter { matches(filter, $0) }.count)
        })
    }

    public static func setUnfollowed(_ done: Bool, username: String, in state: AppState, now: Date) -> AppState {
        guard let index = state.accounts.firstIndex(where: { $0.username == username }) else { return state }
        var next = state
        next.accounts[index].unfollowedManually = done
        next.accounts[index].unfollowedAt = done ? now : nil
        return next
    }

    public static func unfollowsToday(in state: AppState, now: Date, calendar: Calendar) -> Int {
        state.accounts.filter { account in
            guard let at = account.unfollowedAt else { return false }
            return calendar.isDate(at, inSameDayAs: now)
        }.count
    }
}

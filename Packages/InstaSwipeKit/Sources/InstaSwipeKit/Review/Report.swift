import Foundation

public enum ReportFilter: String, CaseIterable, Sendable { case toDo, unsure, done, gone, kept }

/// Pure logic for the "Da togliere" list. Results keep the list's account order.
public enum Report {
    private static func matches(_ filter: ReportFilter, _ account: FollowedAccount) -> Bool {
        switch filter {
        case .toDo: account.decision == .remove && !account.unfollowedManually && account.availability != .unavailable
        case .unsure: account.decision == .unsure && account.availability != .unavailable
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

    public static func accounts<L: ReviewList>(_ filter: ReportFilter, search: String, in list: L) -> [FollowedAccount] {
        let query = fold(search.trimmingCharacters(in: .whitespacesAndNewlines))
        if query.isEmpty { return list.accounts.filter { matches(filter, $0) } }
        return list.accounts.filter { matchesSearch(query, $0) }
    }

    public static func counts<L: ReviewList>(in list: L) -> [ReportFilter: Int] {
        Dictionary(uniqueKeysWithValues: ReportFilter.allCases.map { filter in
            (filter, list.accounts.filter { matches(filter, $0) }.count)
        })
    }

    public static func setUnfollowed<L: ReviewList>(_ done: Bool, username: String, in list: L, now: Date) -> L {
        guard let index = list.accounts.firstIndex(where: { $0.username == username }) else { return list }
        var next = list
        next.accounts[index].unfollowedManually = done
        next.accounts[index].unfollowedAt = done ? now : nil
        return next
    }

    public static func unfollowsToday<L: ReviewList>(in list: L, now: Date, calendar: Calendar) -> Int {
        list.accounts.filter { account in
            guard let at = account.unfollowedAt else { return false }
            return calendar.isDate(at, inSameDayAs: now)
        }.count
    }
}

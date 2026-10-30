import Foundation

public struct ReviewProgress: Equatable, Sendable {
    public let decided: Int
    public let total: Int

    public init(decided: Int, total: Int) {
        self.decided = decided
        self.total = total
    }
}

/// Which accounts the swipe queue and its progress cover.
public enum ReviewScope: String, Codable, Sendable {
    case everyone
    /// Only the accounts that don't follow you back ("Solo chi non ti segue"). In the followers list it
    /// means "Solo chi non segui".
    case notFollowingBack

    func includes(_ account: FollowedAccount) -> Bool {
        switch self {
        case .everyone: true
        case .notFollowingBack: !account.followsMe
        }
    }
}

/// Pure review-queue logic. Relies on the list's accounts already being in review order.
public enum Review {
    private static func reviewable<L: ReviewList>(in list: L, scope: ReviewScope) -> [FollowedAccount] {
        list.accounts.filter { $0.stillInLatestExport && $0.availability != .unavailable && scope.includes($0) }
    }

    /// Swipe order: pending accounts in list order, then the doubts, least recently doubted first.
    private static func queue<L: ReviewList>(in list: L, scope: ReviewScope) -> [FollowedAccount] {
        let reviewable = reviewable(in: list, scope: scope)
        let pending = reviewable.filter { $0.decision == .pending }
        let unsure = reviewable.enumerated()
            .filter { $0.element.decision == .unsure }
            .sorted { lhs, rhs in
                let lhsDate = lhs.element.decidedAt ?? .distantPast
                let rhsDate = rhs.element.decidedAt ?? .distantPast
                return lhsDate == rhsDate ? lhs.offset < rhs.offset : lhsDate < rhsDate
            }
            .map(\.element)
        return pending + unsure
    }

    public static func current<L: ReviewList>(in list: L, scope: ReviewScope = .everyone) -> FollowedAccount? {
        queue(in: list, scope: scope).first
    }

    public static func next<L: ReviewList>(after username: String, in list: L, scope: ReviewScope = .everyone) -> FollowedAccount? {
        let queue = queue(in: list, scope: scope)
        guard let index = queue.firstIndex(where: { $0.username == username }), index + 1 < queue.count else { return nil }
        return queue[index + 1]
    }

    /// Any decision other than `.remove` also clears the "unfollowed" tick, so swipe and list agree.
    public static func decide<L: ReviewList>(_ decision: Decision, username: String, in list: L, now: Date) -> L {
        guard let index = list.accounts.firstIndex(where: { $0.username == username }) else { return list }
        var next = list
        next.accounts[index].decision = decision
        next.accounts[index].decidedAt = decision == .pending ? nil : now
        if decision != .remove {
            next.accounts[index].unfollowedManually = false
            next.accounts[index].unfollowedAt = nil
        }
        if decision != .pending { next.totalDecisionsMade += 1 }
        return next
    }

    /// The account `undo` would revert: the most recent decision within `scope`.
    public static func lastDecided<L: ReviewList>(in list: L, scope: ReviewScope = .everyone) -> FollowedAccount? {
        lastDecidedIndex(in: list, scope: scope).map { list.accounts[$0] }
    }

    public static func undo<L: ReviewList>(in list: L, scope: ReviewScope = .everyone) -> L {
        guard let index = lastDecidedIndex(in: list, scope: scope) else { return list }
        var next = list
        next.accounts[index].decision = .pending
        next.accounts[index].decidedAt = nil
        next.accounts[index].unfollowedManually = false
        next.accounts[index].unfollowedAt = nil
        return next
    }

    private static func lastDecidedIndex<L: ReviewList>(in list: L, scope: ReviewScope) -> Int? {
        var latestIndex: Int?
        for (index, account) in list.accounts.enumerated() {
            guard scope.includes(account), account.decision != .pending, let decidedAt = account.decidedAt else { continue }
            if let best = latestIndex, let bestDate = list.accounts[best].decidedAt, decidedAt < bestDate { continue }
            latestIndex = index // ties resolve to the later account in order
        }
        return latestIndex
    }

    public static func markAvailability<L: ReviewList>(
        _ availability: Availability,
        displayName: String?,
        username: String,
        in list: L
    ) -> L {
        guard let index = list.accounts.firstIndex(where: { $0.username == username }) else { return list }
        var next = list
        next.accounts[index].availability = availability
        if let displayName { next.accounts[index].displayName = displayName }
        return next
    }

    public static func progress<L: ReviewList>(in list: L, scope: ReviewScope = .everyone) -> ReviewProgress {
        let reviewable = reviewable(in: list, scope: scope)
        let decided = reviewable.filter { $0.decision == .keep || $0.decision == .remove }.count
        return ReviewProgress(decided: decided, total: reviewable.count)
    }
}

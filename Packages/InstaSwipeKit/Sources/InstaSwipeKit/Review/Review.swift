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
    /// Only the accounts that don't follow you back ("Solo chi non ti segue").
    case notFollowingBack

    func includes(_ account: FollowedAccount) -> Bool {
        switch self {
        case .everyone: true
        case .notFollowingBack: !account.followsMe
        }
    }
}

/// Pure review-queue logic. Relies on `AppState.accounts` already being in review order.
public enum Review {
    private static func reviewable(in state: AppState, scope: ReviewScope) -> [FollowedAccount] {
        state.accounts.filter { $0.stillInLatestExport && $0.availability != .unavailable && scope.includes($0) }
    }

    /// Swipe order: pending accounts in list order, then the doubts, least recently doubted first.
    private static func queue(in state: AppState, scope: ReviewScope) -> [FollowedAccount] {
        let reviewable = reviewable(in: state, scope: scope)
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

    public static func current(in state: AppState, scope: ReviewScope = .everyone) -> FollowedAccount? {
        queue(in: state, scope: scope).first
    }

    public static func next(after username: String, in state: AppState, scope: ReviewScope = .everyone) -> FollowedAccount? {
        let queue = queue(in: state, scope: scope)
        guard let index = queue.firstIndex(where: { $0.username == username }), index + 1 < queue.count else { return nil }
        return queue[index + 1]
    }

    /// Any decision other than `.remove` also clears the "unfollowed" tick, so swipe and list agree.
    public static func decide(_ decision: Decision, username: String, in state: AppState, now: Date) -> AppState {
        guard let index = state.accounts.firstIndex(where: { $0.username == username }) else { return state }
        var next = state
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
    public static func lastDecided(in state: AppState, scope: ReviewScope = .everyone) -> FollowedAccount? {
        lastDecidedIndex(in: state, scope: scope).map { state.accounts[$0] }
    }

    public static func undo(in state: AppState, scope: ReviewScope = .everyone) -> AppState {
        guard let index = lastDecidedIndex(in: state, scope: scope) else { return state }
        var next = state
        next.accounts[index].decision = .pending
        next.accounts[index].decidedAt = nil
        next.accounts[index].unfollowedManually = false
        next.accounts[index].unfollowedAt = nil
        return next
    }

    private static func lastDecidedIndex(in state: AppState, scope: ReviewScope) -> Int? {
        var latestIndex: Int?
        for (index, account) in state.accounts.enumerated() {
            guard scope.includes(account), account.decision != .pending, let decidedAt = account.decidedAt else { continue }
            if let best = latestIndex, let bestDate = state.accounts[best].decidedAt, decidedAt < bestDate { continue }
            latestIndex = index // ties resolve to the later account in order
        }
        return latestIndex
    }

    public static func markAvailability(
        _ availability: Availability,
        displayName: String?,
        username: String,
        in state: AppState
    ) -> AppState {
        guard let index = state.accounts.firstIndex(where: { $0.username == username }) else { return state }
        var next = state
        next.accounts[index].availability = availability
        if let displayName { next.accounts[index].displayName = displayName }
        return next
    }

    public static func progress(in state: AppState, scope: ReviewScope = .everyone) -> ReviewProgress {
        let reviewable = reviewable(in: state, scope: scope)
        let decided = reviewable.filter { $0.decision == .keep || $0.decision == .remove }.count
        return ReviewProgress(decided: decided, total: reviewable.count)
    }
}

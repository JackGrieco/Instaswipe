import Foundation

public struct ReviewProgress: Equatable, Sendable {
    public let decided: Int
    public let total: Int

    public init(decided: Int, total: Int) {
        self.decided = decided
        self.total = total
    }
}

/// Pure review-queue logic. Relies on `AppState.accounts` already being in review order.
public enum Review {
    private static func isReviewable(_ account: FollowedAccount) -> Bool {
        account.stillInLatestExport && account.availability != .unavailable
    }

    /// Swipe order: pending accounts in list order, then the doubts, least recently doubted first.
    private static func queue(in state: AppState) -> [FollowedAccount] {
        let reviewable = state.accounts.filter(isReviewable)
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

    public static func current(in state: AppState) -> FollowedAccount? {
        queue(in: state).first
    }

    public static func next(after username: String, in state: AppState) -> FollowedAccount? {
        let queue = queue(in: state)
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

    /// The account `undo` would revert: the most recent decision.
    public static func lastDecided(in state: AppState) -> FollowedAccount? {
        lastDecidedIndex(in: state).map { state.accounts[$0] }
    }

    public static func undo(in state: AppState) -> AppState {
        guard let index = lastDecidedIndex(in: state) else { return state }
        var next = state
        next.accounts[index].decision = .pending
        next.accounts[index].decidedAt = nil
        next.accounts[index].unfollowedManually = false
        next.accounts[index].unfollowedAt = nil
        return next
    }

    private static func lastDecidedIndex(in state: AppState) -> Int? {
        var latestIndex: Int?
        for (index, account) in state.accounts.enumerated() {
            guard account.decision != .pending, let decidedAt = account.decidedAt else { continue }
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

    public static func progress(in state: AppState) -> ReviewProgress {
        let reviewable = state.accounts.filter(isReviewable)
        let decided = reviewable.filter { $0.decision == .keep || $0.decision == .remove }.count
        return ReviewProgress(decided: decided, total: reviewable.count)
    }
}

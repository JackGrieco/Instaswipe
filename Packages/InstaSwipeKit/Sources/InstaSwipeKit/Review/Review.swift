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

    private static func isPendingInQueue(_ account: FollowedAccount) -> Bool {
        account.decision == .pending && isReviewable(account)
    }

    public static func current(in state: AppState) -> FollowedAccount? {
        state.accounts.first(where: isPendingInQueue)
    }

    public static func next(after username: String, in state: AppState) -> FollowedAccount? {
        guard let index = state.accounts.firstIndex(where: { $0.username == username }) else { return nil }
        return state.accounts[(index + 1)...].first(where: isPendingInQueue)
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

    public static func undo(in state: AppState) -> AppState {
        var latestIndex: Int?
        for (index, account) in state.accounts.enumerated() {
            guard account.decision != .pending, let decidedAt = account.decidedAt else { continue }
            if let best = latestIndex, let bestDate = state.accounts[best].decidedAt, decidedAt < bestDate { continue }
            latestIndex = index // ties resolve to the later account in order
        }
        guard let index = latestIndex else { return state }
        var next = state
        next.accounts[index].decision = .pending
        next.accounts[index].decidedAt = nil
        next.accounts[index].unfollowedManually = false
        next.accounts[index].unfollowedAt = nil
        return next
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
        return ReviewProgress(decided: reviewable.filter { $0.decision != .pending }.count, total: reviewable.count)
    }
}

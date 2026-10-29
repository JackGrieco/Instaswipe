import Foundation

public struct MergeSummary: Equatable, Sendable {
    public let newAccounts: Int
    public let noLongerFollowed: Int
    public let autoMarkedDone: Int
    public let isSuspicious: Bool

    public init(newAccounts: Int, noLongerFollowed: Int, autoMarkedDone: Int, isSuspicious: Bool) {
        self.newAccounts = newAccounts
        self.noLongerFollowed = noLongerFollowed
        self.autoMarkedDone = autoMarkedDone
        self.isSuspicious = isSuspicious
    }
}

public struct MergePreview: Equatable, Sendable {
    public let state: AppState
    public let summary: MergeSummary

    public init(state: AppState, summary: MergeSummary) {
        self.state = state
        self.summary = summary
    }
}

public enum MergeEngine {
    /// Merges `snapshot` into `current` without ever discarding a decision.
    /// Pure: `savedAt` is only set (via `AppState.empty`) on a first import; the caller stamps it on save.
    public static func preview(current: AppState?, snapshot: ExportSnapshot, now: Date) -> MergePreview {
        let base = current ?? AppState.empty(now: now)
        let exportedUsernames = Set(snapshot.follows.map(\.username))
        let existingUsernames = Set(base.accounts.map(\.username))
        let activeBefore = base.accounts.filter(\.stillInLatestExport).count

        var noLongerFollowed = 0
        var autoMarkedDone = 0

        let updated = base.accounts.map { account -> FollowedAccount in
            var next = account
            if exportedUsernames.contains(account.username) {
                next.stillInLatestExport = true
                next.followsMe = snapshot.followers.contains(account.username)
                if next.availability == .unavailable { next.availability = .unknown }
                return next
            }
            if account.stillInLatestExport { noLongerFollowed += 1 }
            next.stillInLatestExport = false
            if account.decision == .remove && !account.unfollowedManually {
                next.unfollowedManually = true
                next.unfollowedAt = nil
                autoMarkedDone += 1
            }
            return next
        }

        let added = snapshot.follows
            .filter { !existingUsernames.contains($0.username) }
            .map { follow in
                FollowedAccount(
                    username: follow.username,
                    profileURL: follow.profileURL,
                    followedSince: follow.followedSince,
                    followsMe: snapshot.followers.contains(follow.username)
                )
            }

        var state = base
        state.accounts = AppState.reviewOrdered(updated + added)

        let summary = MergeSummary(
            newAccounts: added.count,
            noLongerFollowed: noLongerFollowed,
            autoMarkedDone: autoMarkedDone,
            isSuspicious: Double(noLongerFollowed) > Limits.reimportSuspiciousRatio * Double(activeBefore)
        )
        return MergePreview(state: state, summary: summary)
    }
}

import Foundation

public struct MergeSummary: Equatable, Sendable {
    public let newAccounts: Int
    public let noLongerFollowed: Int
    public let autoMarkedDone: Int
    public let isSuspicious: Bool
    /// Followers who had been removed and follow you again (followers mode only).
    public let refollowed: Int

    public init(newAccounts: Int, noLongerFollowed: Int, autoMarkedDone: Int, isSuspicious: Bool, refollowed: Int = 0) {
        self.newAccounts = newAccounts
        self.noLongerFollowed = noLongerFollowed
        self.autoMarkedDone = autoMarkedDone
        self.isSuspicious = isSuspicious
        self.refollowed = refollowed
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

public struct FollowerMergePreview: Equatable, Sendable {
    public let followers: FollowerState
    public let summary: MergeSummary

    public init(followers: FollowerState, summary: MergeSummary) {
        self.followers = followers
        self.summary = summary
    }
}

public enum MergeEngine {
    /// Merges `snapshot` into `current` without ever discarding a decision.
    /// Pure: `savedAt` is only set (via `AppState.empty`) on a first import; the caller stamps it on save.
    public static func preview(current: AppState?, snapshot: ExportSnapshot, now: Date) -> MergePreview {
        let base = current ?? AppState.empty(now: now)
        let followerUsernames = snapshot.followerUsernames

        let merged = merge(
            accounts: base.accounts,
            exported: snapshot.follows,
            followsMe: { followerUsernames?.contains($0) },
            reopensRemoved: false
        )

        var state = base
        state.accounts = merged.accounts
        return MergePreview(state: state, summary: merged.summary)
    }

    /// Merges the exported followers into `current`. Someone removed by hand who follows you again
    /// (export date later than the removal) goes back to "to do".
    public static func previewFollowers(current: FollowerState?, exported: [ExportedFollow], now: Date) -> FollowerMergePreview {
        let base = current ?? FollowerState.empty(now: now)

        let merged = merge(accounts: base.accounts, exported: exported, followsMe: { _ in nil }, reopensRemoved: true)

        var followers = base
        followers.accounts = merged.accounts
        return FollowerMergePreview(followers: followers, summary: merged.summary)
    }

    /// Shared core. `followsMe` returns the flag for a username, or nil to leave it as it was
    /// (false on a new record). `reopensRemoved` is on only for followers.
    private static func merge(
        accounts: [FollowedAccount],
        exported: [ExportedFollow],
        followsMe: (String) -> Bool?,
        reopensRemoved: Bool
    ) -> (accounts: [FollowedAccount], summary: MergeSummary) {
        let exportedByUsername = Dictionary(exported.map { ($0.username, $0) }, uniquingKeysWith: { first, _ in first })
        let existingUsernames = Set(accounts.map(\.username))
        let activeBefore = accounts.filter(\.stillInLatestExport).count

        var noLongerFollowed = 0
        var autoMarkedDone = 0
        var refollowed = 0

        let updated = accounts.map { account -> FollowedAccount in
            if let entry = exportedByUsername[account.username] {
                let flag = followsMe(account.username) ?? account.followsMe
                if reopensRemoved, let reopened = reopened(account, entry: entry, followsMe: flag) {
                    refollowed += 1
                    return reopened
                }
                return refreshed(account, followsMe: flag)
            }
            var next = account
            if account.stillInLatestExport { noLongerFollowed += 1 }
            next.stillInLatestExport = false
            if account.decision == .remove && !account.unfollowedManually {
                next.unfollowedManually = true
                next.unfollowedAt = nil
                autoMarkedDone += 1
            }
            return next
        }

        let added = exported
            .filter { !existingUsernames.contains($0.username) }
            .map { entry in
                FollowedAccount(
                    username: entry.username,
                    profileURL: entry.profileURL,
                    followedSince: entry.followedSince,
                    followsMe: followsMe(entry.username) ?? false
                )
            }

        let summary = MergeSummary(
            newAccounts: added.count,
            noLongerFollowed: noLongerFollowed,
            autoMarkedDone: autoMarkedDone,
            isSuspicious: Double(noLongerFollowed) > Limits.reimportSuspiciousRatio * Double(activeBefore),
            refollowed: refollowed
        )
        return (AppState.reviewOrdered(updated + added), summary)
    }

    /// A person removed by hand who follows you again after the removal: back to "to do" with the
    /// new date. Rebuilt because `followedSince` is a `let`. Nil when it does not apply.
    private static func reopened(_ account: FollowedAccount, entry: ExportedFollow, followsMe: Bool) -> FollowedAccount? {
        guard account.decision == .remove, account.unfollowedManually,
              let removedAt = account.unfollowedAt,
              let followedAgainAt = entry.followedSince,
              followedAgainAt > removedAt
        else { return nil }
        return FollowedAccount(
            username: account.username,
            profileURL: account.profileURL,
            followedSince: followedAgainAt,
            followsMe: followsMe,
            displayName: account.displayName,
            availability: account.availability == .unavailable ? .unknown : account.availability,
            decision: .pending,
            decidedAt: nil,
            unfollowedManually: false,
            unfollowedAt: nil,
            stillInLatestExport: true
        )
    }

    /// An account present in the export. If it was missing before and had been auto-marked
    /// done (no `unfollowedAt` date), the unfollow clearly did not happen: it returns to "to do".
    private static func refreshed(_ account: FollowedAccount, followsMe: Bool) -> FollowedAccount {
        var next = account
        let isAutoDone = account.decision == .remove && account.unfollowedManually && account.unfollowedAt == nil
        if !account.stillInLatestExport && isAutoDone {
            next.unfollowedManually = false
        }
        next.stillInLatestExport = true
        next.followsMe = followsMe
        if next.availability == .unavailable { next.availability = .unknown }
        return next
    }
}

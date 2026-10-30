import Foundation

/// Cross-links the two lists: each following's `followsMe` says whether they are an active follower,
/// each follower's `followsMe` ("lo segui") says whether they are an active following.
public enum Linking {
    public static func linked(
        state: AppState,
        followers: FollowerState?
    ) -> (state: AppState, followers: FollowerState?) {
        guard let followers else { return (state, nil) }

        let activeFollowers = activeUsernames(followers.accounts)
        let activeFollowing = activeUsernames(state.accounts)

        var linkedState = state
        linkedState.accounts = state.accounts.map { updated($0, followsMe: activeFollowers.contains($0.username)) }
        var linkedFollowers = followers
        linkedFollowers.accounts = followers.accounts.map { updated($0, followsMe: activeFollowing.contains($0.username)) }
        return (linkedState, linkedFollowers)
    }

    /// Still in the latest export and not already removed by hand.
    private static func activeUsernames(_ accounts: [FollowedAccount]) -> Set<String> {
        Set(accounts.filter { $0.stillInLatestExport && !($0.decision == .remove && $0.unfollowedManually) }.map(\.username))
    }

    private static func updated(_ account: FollowedAccount, followsMe: Bool) -> FollowedAccount {
        var copy = account
        copy.followsMe = followsMe
        return copy
    }
}

import Foundation
@testable import InstaSwipeKit

enum Fixtures {
    static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    static func account(
        _ username: String,
        since: Date?,
        decision: Decision = .pending,
        followsMe: Bool = false,
        availability: Availability = .unknown,
        unfollowedManually: Bool = false,
        stillInLatestExport: Bool = true
    ) -> FollowedAccount {
        FollowedAccount(
            username: username,
            profileURL: URL(string: "https://www.instagram.com/_u/\(username)")!,
            followedSince: since,
            followsMe: followsMe,
            availability: availability,
            decision: decision,
            unfollowedManually: unfollowedManually,
            stillInLatestExport: stillInLatestExport
        )
    }

    static func state(_ accounts: [FollowedAccount]) -> AppState {
        var state = AppState.empty(now: referenceDate)
        state.accounts = accounts
        return state
    }

    static func followers(_ accounts: [FollowedAccount]) -> FollowerState {
        var state = FollowerState.empty(now: referenceDate)
        state.accounts = accounts
        return state
    }

    /// Export "following.json": object root, username in `title`, no `value`.
    static func followingJSON(_ entries: [(String, Int?)]) -> Data {
        let items: [[String: Any]] = entries.map { username, timestamp in
            var data: [String: Any] = ["href": "https://www.instagram.com/_u/\(username)"]
            if let timestamp { data["timestamp"] = timestamp }
            return ["title": username, "media_list_data": [], "string_list_data": [data]]
        }
        return try! JSONSerialization.data(withJSONObject: ["relationships_following": items])
    }

    /// Export "followers_1.json": array root, empty `title`, username in `value`.
    static func followersJSON(_ usernames: [String]) -> Data {
        followersJSON(usernames.map { ($0, 1_600_000_000) })
    }

    static func followersJSON(_ entries: [(String, Int)]) -> Data {
        let items: [[String: Any]] = entries.map { username, timestamp in
            [
                "title": "",
                "media_list_data": [],
                "string_list_data": [[
                    "href": "https://www.instagram.com/\(username)",
                    "value": username,
                    "timestamp": timestamp
                ]]
            ]
        }
        return try! JSONSerialization.data(withJSONObject: items)
    }
}

import Foundation

/// One backup holding both lists, so a restore brings them back to the same moment.
///
/// Encoded flat: the keys of `AppState` plus an optional `followers` key, omitted when `nil`.
/// Older backups therefore decode with `followers == nil`, and older builds read a new backup as
/// a plain `AppState`. `AppState` must never gain a key named `followers`.
public struct BackupSnapshot: Codable, Sendable, Equatable {
    public var state: AppState
    public var followers: FollowerState?

    public init(state: AppState, followers: FollowerState?) {
        self.state = state
        self.followers = followers
    }

    private enum CodingKeys: String, CodingKey {
        case followers
    }

    /// Unreadable followers make the whole backup unreadable instead of silently dropping them.
    public init(from decoder: any Decoder) throws {
        state = try AppState(from: decoder)
        followers = try decoder.container(keyedBy: CodingKeys.self)
            .decodeIfPresent(FollowerState.self, forKey: .followers)
    }

    public func encode(to encoder: any Encoder) throws {
        try state.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(followers, forKey: .followers)
    }

    /// Decisions across both lists, used for step backups.
    var totalDecisionsMade: Int {
        state.totalDecisionsMade + (followers?.totalDecisionsMade ?? 0)
    }
}

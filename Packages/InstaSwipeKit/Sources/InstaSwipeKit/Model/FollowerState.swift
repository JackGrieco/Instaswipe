import Foundation

/// Persisted to `followers.json`: the accounts that follow you. Same schema evolution rule as
/// `AppState`: a new field must be optional or decoded with `decodeIfPresent` and a default.
public struct FollowerState: Codable, Sendable, Equatable, ReviewList {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var savedAt: Date
    /// Always in review order, see `AppState.reviewOrdered(_:)`.
    public var accounts: [FollowedAccount]
    public var totalDecisionsMade: Int

    public init(schemaVersion: Int, savedAt: Date, accounts: [FollowedAccount], totalDecisionsMade: Int) {
        self.schemaVersion = schemaVersion
        self.savedAt = savedAt
        self.accounts = accounts
        self.totalDecisionsMade = totalDecisionsMade
    }

    public static func empty(now: Date) -> FollowerState {
        FollowerState(schemaVersion: currentSchemaVersion, savedAt: now, accounts: [], totalDecisionsMade: 0)
    }

    public var list: AccountList {
        get { AccountList(accounts: accounts, totalDecisionsMade: totalDecisionsMade) }
        set {
            accounts = newValue.accounts
            totalDecisionsMade = newValue.totalDecisionsMade
        }
    }
}

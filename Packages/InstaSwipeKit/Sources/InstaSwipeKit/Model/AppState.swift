import Foundation

/// Count of profile loads for one local day (`day` = start of the local day).
public struct DailyCount: Codable, Sendable, Equatable {
    public var day: Date
    public var count: Int

    public init(day: Date, count: Int) {
        self.day = day
        self.count = count
    }
}

public struct AppState: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var savedAt: Date
    /// Always in review order, see `reviewOrdered(_:)`.
    public var accounts: [FollowedAccount]
    public var totalDecisionsMade: Int
    public var profileLoads: DailyCount
    public var dailyProfileLimit: Int
    public var emergencyStopDay: Date?

    public init(
        schemaVersion: Int,
        savedAt: Date,
        accounts: [FollowedAccount],
        totalDecisionsMade: Int,
        profileLoads: DailyCount,
        dailyProfileLimit: Int,
        emergencyStopDay: Date?
    ) {
        self.schemaVersion = schemaVersion
        self.savedAt = savedAt
        self.accounts = accounts
        self.totalDecisionsMade = totalDecisionsMade
        self.profileLoads = profileLoads
        self.dailyProfileLimit = dailyProfileLimit
        self.emergencyStopDay = emergencyStopDay
    }

    public static func empty(now: Date) -> AppState {
        AppState(
            schemaVersion: currentSchemaVersion,
            savedAt: now,
            accounts: [],
            totalDecisionsMade: 0,
            profileLoads: DailyCount(day: now, count: 0),
            dailyProfileLimit: Limits.defaultDailyProfileLoads,
            emergencyStopDay: nil
        )
    }

    /// Review order: `followedSince` ascending, `nil` last, ties by `username` ascending.
    public static func reviewOrdered(_ accounts: [FollowedAccount]) -> [FollowedAccount] {
        accounts.sorted { lhs, rhs in
            switch (lhs.followedSince, rhs.followedSince) {
            case let (l?, r?) where l != r: return l < r
            case (nil, .some): return false
            case (.some, nil): return true
            default: return lhs.username < rhs.username
            }
        }
    }
}

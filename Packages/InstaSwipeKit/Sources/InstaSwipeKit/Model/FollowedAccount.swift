import Foundation

public enum Decision: String, Codable, Sendable { case pending, keep, remove }

public enum Availability: String, Codable, Sendable { case unknown, available, unavailable }

/// Persisted inside `AppState`: same schema evolution rule (new fields optional or decoded with
/// `decodeIfPresent` and a default; bump `AppState.schemaVersion` only with a migration).
public struct FollowedAccount: Codable, Sendable, Equatable, Identifiable {
    public var id: String { username }
    public let username: String
    public let profileURL: URL
    public let followedSince: Date?
    public var followsMe: Bool
    public var displayName: String?
    public var availability: Availability
    public var decision: Decision
    public var decidedAt: Date?
    public var unfollowedManually: Bool
    public var unfollowedAt: Date?
    public var stillInLatestExport: Bool

    public init(
        username: String,
        profileURL: URL,
        followedSince: Date?,
        followsMe: Bool = false,
        displayName: String? = nil,
        availability: Availability = .unknown,
        decision: Decision = .pending,
        decidedAt: Date? = nil,
        unfollowedManually: Bool = false,
        unfollowedAt: Date? = nil,
        stillInLatestExport: Bool = true
    ) {
        self.username = username
        self.profileURL = profileURL
        self.followedSince = followedSince
        self.followsMe = followsMe
        self.displayName = displayName
        self.availability = availability
        self.decision = decision
        self.decidedAt = decidedAt
        self.unfollowedManually = unfollowedManually
        self.unfollowedAt = unfollowedAt
        self.stillInLatestExport = stillInLatestExport
    }
}

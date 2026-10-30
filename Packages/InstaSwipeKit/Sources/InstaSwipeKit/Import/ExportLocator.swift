import Foundation

public struct ExportFiles: Equatable {
    public let following: [URL]
    public let followers: [URL]

    public init(following: [URL], followers: [URL]) {
        self.following = following
        self.followers = followers
    }
}

public struct ExportSnapshot: Equatable, Sendable {
    public let follows: [ExportedFollow]
    /// `nil` when the export has no `followers*.json` file (as opposed to an empty list).
    public let followers: [ExportedFollow]?

    public init(follows: [ExportedFollow], followers: [ExportedFollow]?) {
        self.follows = follows
        self.followers = followers
    }

    public var followerUsernames: Set<String>? { followers.map { Set($0.map(\.username)) } }
}

public enum ExportLocator {
    private static let excludedFollowingNames: Set<String> = ["following_hashtags.json"]

    public static func locate(in folder: URL) throws -> ExportFiles {
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey]
        ) else { throw ExportParserError.followingNotFound }

        return try classify(enumerator.compactMap { $0 as? URL })
    }

    /// Sorts JSON file URLs into following / followers by file name (same rules as `locate`).
    public static func classify(_ urls: [URL]) throws -> ExportFiles {
        let files = urls.filter { $0.pathExtension.lowercased() == "json" }
        let following = files.filter {
            let name = $0.lastPathComponent.lowercased()
            return name.hasPrefix("following") && !excludedFollowingNames.contains(name)
        }
        let followers = files.filter { $0.lastPathComponent.lowercased().hasPrefix("followers") }
        guard !following.isEmpty else { throw ExportParserError.followingNotFound }
        return ExportFiles(following: sortedByName(following), followers: sortedByName(followers))
    }

    public static func load(_ files: ExportFiles) throws -> ExportSnapshot {
        let follows = try loadDeduplicated(files.following, parse: ExportParser.parseFollowing)
        let followers = files.followers.isEmpty
            ? nil
            : try loadDeduplicated(files.followers, parse: ExportParser.parseFollowers)
        return ExportSnapshot(follows: follows, followers: followers)
    }

    /// Parses every file, keeping one entry per username (the oldest) in first-seen order.
    private static func loadDeduplicated(
        _ urls: [URL], parse: (Data) throws -> [ExportedFollow]
    ) throws -> [ExportedFollow] {
        var oldestByUsername: [String: ExportedFollow] = [:]
        var order: [String] = []
        for url in urls {
            for follow in try parse(Data(contentsOf: url)) {
                guard let existing = oldestByUsername[follow.username] else {
                    oldestByUsername[follow.username] = follow
                    order.append(follow.username)
                    continue
                }
                if isOlder(follow.followedSince, than: existing.followedSince) {
                    oldestByUsername[follow.username] = follow
                }
            }
        }
        return order.compactMap { oldestByUsername[$0] }
    }

    private static func sortedByName(_ urls: [URL]) -> [URL] {
        urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// A known date beats a missing one; between two known dates the earlier wins.
    private static func isOlder(_ candidate: Date?, than current: Date?) -> Bool {
        switch (candidate, current) {
        case let (c?, e?): return c < e
        case (_?, nil): return true
        default: return false
        }
    }
}

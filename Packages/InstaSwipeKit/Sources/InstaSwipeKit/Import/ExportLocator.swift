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
    public let followers: Set<String>

    public init(follows: [ExportedFollow], followers: Set<String>) {
        self.follows = follows
        self.followers = followers
    }
}

public enum ExportLocator {
    private static let excludedFollowingNames: Set<String> = ["following_hashtags.json"]

    public static func locate(in folder: URL) throws -> ExportFiles {
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey]
        ) else { throw ExportParserError.followingNotFound }

        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension.lowercased() == "json" }
        let following = files.filter {
            let name = $0.lastPathComponent.lowercased()
            return name.hasPrefix("following") && !excludedFollowingNames.contains(name)
        }
        let followers = files.filter { $0.lastPathComponent.lowercased().hasPrefix("followers") }
        guard !following.isEmpty else { throw ExportParserError.followingNotFound }
        return ExportFiles(following: sortedByName(following), followers: sortedByName(followers))
    }

    public static func load(_ files: ExportFiles) throws -> ExportSnapshot {
        var oldestByUsername: [String: ExportedFollow] = [:]
        var order: [String] = []
        for url in files.following {
            for follow in try ExportParser.parseFollowing(Data(contentsOf: url)) {
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
        var followers = Set<String>()
        for url in files.followers {
            followers.formUnion(try ExportParser.parseFollowers(Data(contentsOf: url)))
        }
        return ExportSnapshot(follows: order.compactMap { oldestByUsername[$0] }, followers: followers)
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

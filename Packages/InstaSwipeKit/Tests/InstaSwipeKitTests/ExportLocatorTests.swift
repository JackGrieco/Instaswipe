import Foundation
import Testing
@testable import InstaSwipeKit

struct ExportLocatorTests {
    private func makeFolder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ data: Data, _ name: String, in dir: URL) throws {
        try data.write(to: dir.appendingPathComponent(name))
    }

    @Test func locateFindsSplitFilesAndIgnoresHashtags() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("followers_and_following")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let empty = Data("[]".utf8)
        for name in ["following.json", "following_2.json", "following_hashtags.json", "followers_1.json"] {
            try write(empty, name, in: nested)
        }
        let files = try ExportLocator.locate(in: root)
        #expect(files.following.map(\.lastPathComponent) == ["following.json", "following_2.json"])
        #expect(files.followers.map(\.lastPathComponent) == ["followers_1.json"])
    }

    @Test func classifyPickedFilesByName() throws {
        let urls = ["following_2.json", "following.json", "following_hashtags.json", "followers_1.json", "other.json"]
            .map { URL(fileURLWithPath: "/picked/\($0)") }
        let files = try ExportLocator.classify(urls)
        #expect(files.following.map(\.lastPathComponent) == ["following.json", "following_2.json"])
        #expect(files.followers.map(\.lastPathComponent) == ["followers_1.json"])
    }

    @Test func classifyThrowsWithoutFollowingFile() {
        let urls = [URL(fileURLWithPath: "/picked/followers_1.json")]
        #expect(throws: ExportParserError.followingNotFound) {
            try ExportLocator.classify(urls)
        }
    }

    @Test func locateThrowsWhenNoFollowing() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(Data("[]".utf8), "followers_1.json", in: root)
        #expect(throws: ExportParserError.followingNotFound) {
            try ExportLocator.locate(in: root)
        }
    }

    @Test func loadDedupesCaseInsensitiveKeepingOldest() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(Fixtures.followingJSON([("Anna", 200), ("bob", 50)]), "following.json", in: root)
        try write(Fixtures.followingJSON([("anna", 100)]), "following_2.json", in: root)
        try write(Fixtures.followersJSON(["Bob"]), "followers_1.json", in: root)

        let snapshot = try ExportLocator.load(ExportLocator.locate(in: root))

        #expect(snapshot.follows.count == 2)
        let anna = snapshot.follows.first { $0.username == "anna" }
        #expect(anna?.followedSince == Date(timeIntervalSince1970: 100))
        #expect(snapshot.followers == ["bob"])
    }
}

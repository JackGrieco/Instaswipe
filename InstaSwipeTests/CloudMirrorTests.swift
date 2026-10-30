import Foundation
import InstaSwipeKit
import Testing
@testable import InstaSwipe

@MainActor
struct CloudMirrorTests {
    private func seed(_ local: URL, usernames: [String]) throws {
        var state = AppState.empty(now: Date(timeIntervalSince1970: 1_700_000_000))
        state.accounts = usernames.map { name in
            FollowedAccount(
                username: name, profileURL: URL(string: "https://www.instagram.com/_u/\(name)")!,
                followedSince: Date(timeIntervalSince1970: 1_600_000_000)
            )
        }
        try FileStateStore(localDirectory: local, cloudDirectory: nil).save(state)
    }

    private func cloudState(_ cloud: URL) throws -> AppState {
        let data = try Data(contentsOf: cloud.appendingPathComponent("state.json"))
        return try StateCoding.decoder().decode(AppState.self, from: data)
    }

    @Test func flushWritesTheLatestStateToCloud() async throws {
        let local = try TestSupport.makeDirectory()
        let cloud = try TestSupport.makeDirectory()
        try seed(local, usernames: ["a", "b"])
        let model = AppModel(environment: TestSupport.environment(local: local, cloud: cloud))

        model.apply { Review.decide(.keep, username: "a", in: $0, now: Date()) }
        await model.flushCloudMirror()
        model.apply { Review.decide(.remove, username: "b", in: $0, now: Date()) }
        await model.flushCloudMirror()

        // Compared field by field: JSON dates keep milliseconds only.
        let mirrored = try cloudState(cloud)
        #expect(mirrored.accounts.map(\.decision) == [.keep, .remove])
        #expect(mirrored.totalDecisionsMade == 2)
        #expect(model.bannerMessage == nil)
    }

    @Test func flushWritesFollowersToCloudToo() async throws {
        let local = try TestSupport.makeDirectory()
        let cloud = try TestSupport.makeDirectory()
        try seed(local, usernames: ["a"])
        var followers = FollowerState.empty(now: Date(timeIntervalSince1970: 1_700_000_000))
        followers.accounts = [FollowedAccount(
            username: "f", profileURL: URL(string: "https://www.instagram.com/_u/f")!, followedSince: nil
        )]
        try FollowerStore(localDirectory: local, cloudDirectory: nil).save(followers)
        let model = AppModel(environment: TestSupport.environment(local: local, cloud: cloud))

        model.apply(.followers) { Review.decide(.remove, username: "f", in: $0, now: Date()) }
        await model.flushCloudMirror()

        let data = try Data(contentsOf: cloud.appendingPathComponent("followers.json"))
        let mirrored = try StateCoding.decoder().decode(FollowerState.self, from: data)
        #expect(mirrored.accounts.map(\.decision) == [.remove])
        #expect(try cloudState(cloud).accounts.map(\.username) == ["a"])
        #expect(model.bannerMessage == nil)
    }

    @Test func flushWithoutFollowersWritesNoFollowersFile() async throws {
        let local = try TestSupport.makeDirectory()
        let cloud = try TestSupport.makeDirectory()
        try seed(local, usernames: ["a"])
        let model = AppModel(environment: TestSupport.environment(local: local, cloud: cloud))

        model.apply { Review.decide(.keep, username: "a", in: $0, now: Date()) }
        await model.flushCloudMirror()

        #expect(FileManager.default.fileExists(atPath: cloud.appendingPathComponent("state.json").path))
        #expect(!FileManager.default.fileExists(atPath: cloud.appendingPathComponent("followers.json").path))
    }

    @Test func flushWithoutCloudDoesNothing() async throws {
        let local = try TestSupport.makeDirectory()
        try seed(local, usernames: ["a"])
        let model = AppModel(environment: TestSupport.environment(local: local))

        await model.flushCloudMirror()

        #expect(model.bannerMessage == nil)
        #expect(model.state?.accounts.count == 1)
    }
}

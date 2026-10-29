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

    @Test func flushWithoutCloudDoesNothing() async throws {
        let local = try TestSupport.makeDirectory()
        try seed(local, usernames: ["a"])
        let model = AppModel(environment: TestSupport.environment(local: local))

        await model.flushCloudMirror()

        #expect(model.bannerMessage == nil)
        #expect(model.state?.accounts.count == 1)
    }
}

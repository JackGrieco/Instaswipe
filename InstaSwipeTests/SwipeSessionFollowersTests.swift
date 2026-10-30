import Foundation
import InstaSwipeKit
import SwiftUI
import Testing
@testable import InstaSwipe

@MainActor
struct SwipeSessionFollowersTests {
    private let followingNames = ["aa", "bb", "cc"]
    private let followerNames = ["fan_01", "fan_02", "aa"]

    private func makeAccounts(_ names: [String]) -> [FollowedAccount] {
        names.enumerated().map { index, name in
            FollowedAccount(
                username: name, profileURL: URL(string: "https://www.instagram.com/_u/\(name)")!,
                followedSince: Date(timeIntervalSince1970: 1_600_000_000 + Double(index)), followsMe: false
            )
        }
    }

    private func makeSession(
        withFollowers: Bool = true, instant: Bool = false
    ) throws -> (SwipeSession, AppModel, ManualProfileLoader) {
        let local = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        var state = AppState.empty(now: Date())
        state.accounts = makeAccounts(followingNames)
        try FileStateStore(localDirectory: local, cloudDirectory: nil).save(state)
        if withFollowers {
            var followers = FollowerState.empty(now: Date())
            followers.accounts = makeAccounts(followerNames)
            try FollowerStore(localDirectory: local, cloudDirectory: nil).save(followers)
        }
        let environment = AppEnvironment(
            localDirectory: local, cloudDirectory: nil, isUITesting: true,
            useFakeProfiles: true, shouldSeedTestAccounts: false,
            defaultsSuiteName: UUID().uuidString
        )
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(instant, forKey: SwipeSession.instantUnfollowDefaultsKey)
        let loader = ManualProfileLoader()
        let model = AppModel(environment: environment)
        return (SwipeSession(model: model, loader: loader, defaults: defaults), model, loader)
    }

    private func decision(_ name: String, _ mode: ListMode, in model: AppModel) -> Decision? {
        model.list(mode)?.accounts.first { $0.username == name }?.decision
    }

    @Test func followerModeShowsFollowers() throws {
        let (session, _, _) = try makeSession()
        session.mode = .followers
        #expect(session.current?.username == "fan_01")
        #expect(session.screen == .card)
    }

    @Test func followerModeWithoutListShowsInvite() throws {
        let (session, model, _) = try makeSession(withFollowers: false)
        session.mode = .followers
        #expect(session.screen == .noFollowers)
        session.undo()
        #expect(session.decide(.keep) == false)
        #expect(model.followers == nil)
        #expect(decision("aa", .following, in: model) == .pending)
    }

    @Test func undoIsPerMode() throws {
        let (session, model, _) = try makeSession()
        session.decide(.keep)
        session.mode = .followers
        session.decide(.keep)
        session.mode = .following
        session.undo()
        #expect(decision("aa", .following, in: model) == .pending)
        #expect(decision("fan_01", .followers, in: model) == .keep)
    }

    @Test func scopeIsPerMode() throws {
        let (session, _, _) = try makeSession()
        session.mode = .followers
        session.isNotFollowingBackOnly = true
        session.mode = .following
        #expect(session.isNotFollowingBackOnly == false)
        session.mode = .followers
        #expect(session.isNotFollowingBackOnly == true)
    }

    @Test func instantRemoveInFollowerModeHandsOffToInstagram() throws {
        let (session, model, _) = try makeSession(instant: true)
        session.mode = .followers
        let loadsBefore = model.state?.profileLoads.count
        session.decide(.remove)
        #expect(session.appHandoffURL?.absoluteString == "https://www.instagram.com/_u/fan_01")
        #expect(session.profilePageURL == nil)
        #expect(session.unfollowUsername == nil)
        #expect(model.state?.profileLoads.count == loadsBefore)
        session.appHandoffOpened()
        #expect(session.appHandoffURL == nil)
    }

    @Test func returnPromptActsOnOriginListAfterModeSwitch() throws {
        let (session, model, _) = try makeSession(instant: true)
        session.mode = .followers
        session.decide(.remove)
        session.mode = .following
        session.returnPrompt.scenePhaseChanged(.background)
        session.returnPrompt.scenePhaseChanged(.active)
        session.confirmReturnPrompt()
        #expect(model.list(.followers)?.accounts.first { $0.username == "fan_01" }?.unfollowedManually == true)
        #expect(model.list(.following)?.accounts.allSatisfy { !$0.unfollowedManually } == true)
        #expect(session.returnPrompt.prompt == nil)
    }

    @Test func keepFromReturnPromptKeepsOnOriginList() throws {
        let (session, model, _) = try makeSession(instant: true)
        session.mode = .followers
        session.decide(.remove)
        session.mode = .following
        session.returnPrompt.scenePhaseChanged(.background)
        session.returnPrompt.scenePhaseChanged(.active)
        session.keepFromReturnPrompt()
        #expect(decision("fan_01", .followers, in: model) == .keep)
        #expect(decision("aa", .following, in: model) == .pending)
    }

    @Test func availabilityAppliesToBothLists() async throws {
        let (session, model, loader) = try makeSession()
        session.start()
        for _ in 0..<10 { await Task.yield() }
        loader.complete("aa", with: .unavailable)
        for _ in 0..<10 { await Task.yield() }
        #expect(model.list(.following)?.accounts.first { $0.username == "aa" }?.availability == .unavailable)
        #expect(model.list(.followers)?.accounts.first { $0.username == "aa" }?.availability == .unavailable)
    }
}

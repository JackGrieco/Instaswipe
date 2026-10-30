import Testing
import Foundation
@testable import InstaSwipeKit

struct LinkingTests {
    private func followsMe(_ state: AppState, _ name: String) -> Bool? {
        state.accounts.first { $0.username == name }?.followsMe
    }

    private func followedByMe(_ followers: FollowerState?, _ name: String) -> Bool? {
        followers?.accounts.first { $0.username == name }?.followsMe
    }

    @Test func removedFollowerLosesFollowsMe() {
        let state = Fixtures.state([Fixtures.account("aa", since: nil, followsMe: true)])
        let followers = Fixtures.followers([
            Fixtures.account("aa", since: nil, decision: .remove, unfollowedManually: true)
        ])

        let result = Linking.linked(state: state, followers: followers)

        #expect(followsMe(result.state, "aa") == false)
    }

    @Test func untickedRemovalRestoresFollowsMe() {
        let state = Fixtures.state([Fixtures.account("aa", since: nil, followsMe: false)])
        let followers = Fixtures.followers([
            Fixtures.account("aa", since: nil, decision: .remove, unfollowedManually: false)
        ])

        let result = Linking.linked(state: state, followers: followers)

        #expect(followsMe(result.state, "aa") == true)
    }

    @Test func untickedRemovalOfGoneFollowerStaysFalse() {
        let state = Fixtures.state([Fixtures.account("aa", since: nil, followsMe: true)])
        let followers = Fixtures.followers([
            Fixtures.account("aa", since: nil, decision: .remove, unfollowedManually: false, stillInLatestExport: false)
        ])

        let result = Linking.linked(state: state, followers: followers)

        #expect(followsMe(result.state, "aa") == false)
    }

    @Test func followerShowsFollowedByMe() {
        let state = Fixtures.state([
            Fixtures.account("aa", since: nil),
            Fixtures.account("bb", since: nil, decision: .remove, unfollowedManually: true)
        ])
        let followers = Fixtures.followers([
            Fixtures.account("aa", since: nil),
            Fixtures.account("bb", since: nil),
            Fixtures.account("cc", since: nil)
        ])

        let result = Linking.linked(state: state, followers: followers)

        #expect(followedByMe(result.followers, "aa") == true)
        #expect(followedByMe(result.followers, "bb") == false)
        #expect(followedByMe(result.followers, "cc") == false)
    }

    @Test func nilFollowersLeavesStateUntouched() {
        let state = Fixtures.state([Fixtures.account("aa", since: nil, followsMe: true)])

        let result = Linking.linked(state: state, followers: nil)

        #expect(result.state == state)
        #expect(result.followers == nil)
    }

    @Test func linkingIsIdempotent() {
        let state = Fixtures.state([
            Fixtures.account("aa", since: nil, followsMe: true),
            Fixtures.account("bb", since: nil, decision: .remove, unfollowedManually: true)
        ])
        let followers = Fixtures.followers([
            Fixtures.account("aa", since: nil, decision: .remove, unfollowedManually: true),
            Fixtures.account("bb", since: nil)
        ])

        let once = Linking.linked(state: state, followers: followers)
        let twice = Linking.linked(state: once.state, followers: once.followers)

        #expect(twice.state == once.state)
        #expect(twice.followers == once.followers)
    }
}

import Foundation
import Testing
@testable import InstaSwipeKit

@Test func appStateRoundTripsThroughJSON() throws {
    let state = Fixtures.state([Fixtures.account("anna", since: .init(timeIntervalSince1970: 1_580_000_000), decision: .remove)])
    let data = try StateCoding.encoder().encode(state)
    #expect(try StateCoding.decoder().decode(AppState.self, from: data) == state)
}

@Test func emptyStateHasDefaults() {
    let now = Date(timeIntervalSince1970: 0)
    let s = AppState.empty(now: now)
    #expect(s.schemaVersion == 1 && s.accounts.isEmpty && s.dailyProfileLimit == 400 && s.emergencyStopDay == nil)
    #expect(s.savedAt == now && s.totalDecisionsMade == 0)
    #expect(s.profileLoads == DailyCount(day: now, count: 0))
}

@Test func accountIdIsUsernameAndDefaultsArePending() {
    let a = Fixtures.account("bruno", since: nil)
    #expect(a.id == "bruno")
    #expect(a.decision == .pending && a.availability == .unknown)
    #expect(!a.followsMe && !a.unfollowedManually && a.stillInLatestExport)
    #expect(a.displayName == nil && a.decidedAt == nil && a.unfollowedAt == nil)
}

@Test func encodingIsSortedAndUsesISO8601Dates() throws {
    let state = Fixtures.state([])
    let json = String(decoding: try StateCoding.encoder().encode(state), as: UTF8.self)
    #expect(json.contains("\"savedAt\" : \"2023-11-14T22:13:20.000Z\""))
    let accountsIndex = try #require(json.range(of: "\"accounts\""))
    let schemaIndex = try #require(json.range(of: "\"schemaVersion\""))
    #expect(accountsIndex.lowerBound < schemaIndex.lowerBound)
    #expect(json.contains("\n"))
}

@Test func decisionAndAvailabilityEncodeAsStrings() throws {
    let a = Fixtures.account("carla", since: nil, decision: .keep, availability: .unavailable)
    let json = String(decoding: try StateCoding.encoder().encode(a), as: UTF8.self)
    #expect(json.contains("\"keep\"") && json.contains("\"unavailable\""))
}

@Test func reviewOrderedSortsOldestFirstNilLastTiesByUsername() {
    let old = Date(timeIntervalSince1970: 1_000)
    let new = Date(timeIntervalSince1970: 2_000)
    let input = [
        Fixtures.account("zed", since: nil),
        Fixtures.account("mario", since: new),
        Fixtures.account("beta", since: old),
        Fixtures.account("alfa", since: old),
        Fixtures.account("anna", since: nil)
    ]
    let ordered = AppState.reviewOrdered(input).map(\.username)
    #expect(ordered == ["alfa", "beta", "mario", "anna", "zed"])
}

@Test func reviewOrderedDoesNotMutateInput() {
    let input = [Fixtures.account("b", since: nil), Fixtures.account("a", since: nil)]
    _ = AppState.reviewOrdered(input)
    #expect(input.map(\.username) == ["b", "a"])
}

@Test func limitsMatchGlobalConstraints() {
    #expect(Limits.defaultDailyProfileLoads == 400)
    #expect(Limits.dailyUnfollowWarning == 150)
    #expect(Limits.reimportSuspiciousRatio == 0.2)
    #expect(Limits.profileLoadTimeout == .seconds(10))
    #expect(Limits.dailyBackupsKept == 14)
    #expect(Limits.stepBackupsKept == 10)
    #expect(Limits.backupEveryDecisions == 100)
    #expect(Limits.preImportBackupsKept == 5)
    #expect(Limits.cloudMirrorDebounce == .seconds(5))
}

@Test func fixtureExportJSONHasExpectedShape() throws {
    let following = try JSONSerialization.jsonObject(with: Fixtures.followingJSON([("anna", 1_580_000_000), ("bruno", nil)])) as? [String: Any]
    #expect((following?["relationships_following"] as? [Any])?.count == 2)
    let followers = try JSONSerialization.jsonObject(with: Fixtures.followersJSON(["anna"])) as? [Any]
    #expect(followers?.count == 1)
}

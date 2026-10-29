import Foundation
import Testing
@testable import InstaSwipeKit

/// `Fixtures/state-v1.json` is frozen: it was written once by the v1 encoder and must never be
/// regenerated. If this test fails, a model change broke files already on users' devices.
@Test func frozenV1StateFileStillDecodes() throws {
    let url = try #require(Bundle.module.url(forResource: "state-v1", withExtension: "json"))
    let state = try StateCoding.decoder().decode(AppState.self, from: Data(contentsOf: url))

    #expect(state.schemaVersion == 1)
    #expect(state.savedAt == Date(timeIntervalSince1970: 1_700_007_200))
    #expect(state.totalDecisionsMade == 2)
    #expect(state.profileLoads == DailyCount(day: Date(timeIntervalSince1970: 1_700_000_000), count: 37))
    #expect(state.dailyProfileLimit == 450)
    #expect(state.emergencyStopDay == Date(timeIntervalSince1970: 1_700_000_000))
    #expect(state.accounts.map(\.username) == ["fixture_anna", "fixture_bruno", "fixture_carla"])

    let anna = state.accounts[0]
    #expect(anna.decision == .remove && anna.unfollowedManually && anna.availability == .available)
    #expect(anna.decidedAt == Date(timeIntervalSince1970: 1_700_000_010.25))
    #expect(anna.unfollowedAt == Date(timeIntervalSince1970: 1_700_003_600))
    #expect(anna.displayName == "Anna Fixture")

    let bruno = state.accounts[1]
    #expect(bruno.decision == .keep && bruno.followsMe && bruno.displayName == nil)

    let carla = state.accounts[2]
    #expect(carla.decision == .pending && carla.followedSince == nil && carla.decidedAt == nil)
    #expect(carla.availability == .unavailable && !carla.stillInLatestExport)
}

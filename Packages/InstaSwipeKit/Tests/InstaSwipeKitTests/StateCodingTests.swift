import Foundation
import Testing
@testable import InstaSwipeKit

@Test func subSecondDateRoundTrips() throws {
    var state = Fixtures.state([])
    state.savedAt = Date(timeIntervalSince1970: 1_700_000_000.123)
    let data = try StateCoding.encoder().encode(state)
    let decoded = try StateCoding.decoder().decode(AppState.self, from: data)
    #expect(abs(decoded.savedAt.timeIntervalSince1970 - 1_700_000_000.123) < 0.001)
}

@Test func wholeSecondISOStringStillDecodes() throws {
    let state = Fixtures.state([])
    let json = String(decoding: try StateCoding.encoder().encode(state), as: UTF8.self)
        .replacingOccurrences(of: "2023-11-14T22:13:20.000Z", with: "2023-11-14T22:13:20Z")
    let decoded = try StateCoding.decoder().decode(AppState.self, from: Data(json.utf8))
    #expect(decoded.savedAt == Fixtures.referenceDate)
}

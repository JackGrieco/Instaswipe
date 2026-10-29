import Foundation
import Testing
import InstaSwipeKit
@testable import InstaSwipe

@Suite struct ProfileSnapshotMapperTests {
    private let requested = URL(string: "https://www.instagram.com/luca/")!

    @Test func mapsAllFields() {
        let result: [String: Any] = [
            "url": "https://www.instagram.com/luca/",
            "title": "Luca",
            "ogTitle": "Luca (@luca)",
            "ogImage": "https://cdn.example.com/p.jpg",
            "body": "hello"
        ]
        let snapshot = ProfileSnapshotMapper.snapshot(from: result, requestedURL: requested)
        #expect(snapshot?.finalURL == requested)
        #expect(snapshot?.ogTitle == "Luca (@luca)")
        #expect(snapshot?.ogImage == URL(string: "https://cdn.example.com/p.jpg"))
        #expect(snapshot?.bodyText == "hello")
    }

    @Test func fallsBackToRequestedURLAndNilsMissingFields() {
        let snapshot = ProfileSnapshotMapper.snapshot(from: ["ogTitle": NSNull()], requestedURL: requested)
        #expect(snapshot?.finalURL == requested)
        #expect(snapshot?.ogTitle == nil)
        #expect(snapshot?.ogImage == nil)
        #expect(snapshot?.title == "")
        #expect(snapshot?.bodyText == "")
    }

    @Test func returnsNilWhenResultIsNotADictionary() {
        #expect(ProfileSnapshotMapper.snapshot(from: "nope", requestedURL: requested) == nil)
        #expect(ProfileSnapshotMapper.snapshot(from: nil, requestedURL: requested) == nil)
    }
}

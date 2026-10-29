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

    @Test func prefersLargestRenderedCopyOfTheProfilePhoto() {
        let small = "https://cdn.example.com/v/p_n.jpg?stp=dst-jpg_s100x100_tt6"
        let medium = "https://cdn.example.com/v/p_n.jpg?stp=dst-jpg_s150x150_tt6"
        let large = "https://cdn.example.com/v/p_n.jpg?stp=dst-jpg_s320x320_tt6"
        let result: [String: Any] = ["ogImage": small, "images": [medium, large, small]]
        let snapshot = ProfileSnapshotMapper.snapshot(from: result, requestedURL: requested)
        #expect(snapshot?.ogImage == URL(string: large))
    }

    @Test func keepsOgImageWhenNoLargerCopyWasRendered() {
        let small = "https://cdn.example.com/v/p_n.jpg?stp=dst-jpg_s100x100_tt6"
        let result: [String: Any] = ["ogImage": small, "images": [String]()]
        let snapshot = ProfileSnapshotMapper.snapshot(from: result, requestedURL: requested)
        #expect(snapshot?.ogImage == URL(string: small))
    }

    @Test func treatsUnsizedCopyAsFullResolution() {
        let small = "https://cdn.example.com/v/p_n.jpg?stp=dst-jpg_s100x100_tt6"
        let unsized = "https://cdn.example.com/v/p_n.jpg?stp=dst-jpg_tt6"
        let result: [String: Any] = ["ogImage": small, "images": [unsized]]
        let snapshot = ProfileSnapshotMapper.snapshot(from: result, requestedURL: requested)
        #expect(snapshot?.ogImage == URL(string: unsized))
    }

    @Test func returnsNilWhenResultIsNotADictionary() {
        #expect(ProfileSnapshotMapper.snapshot(from: "nope", requestedURL: requested) == nil)
        #expect(ProfileSnapshotMapper.snapshot(from: nil, requestedURL: requested) == nil)
    }
}

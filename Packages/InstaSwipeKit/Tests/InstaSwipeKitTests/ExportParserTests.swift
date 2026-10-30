import Foundation
import Testing
@testable import InstaSwipeKit

struct ExportParserTests {
    @Test func parsesRealFollowingShape() throws {
        let f = try ExportParser.parseFollowing(Fixtures.followingJSON([("flipper_zero", 1_793_097_949)]))
        #expect(f == [ExportedFollow(
            username: "flipper_zero",
            profileURL: URL(string: "https://www.instagram.com/_u/flipper_zero")!,
            followedSince: Date(timeIntervalSince1970: 1_793_097_949)
        )])
    }

    @Test func parsesFollowersArrayWithEmptyTitle() throws {
        #expect(try ExportParser.parseFollowers(Fixtures.followersJSON(["zoe"])).map(\.username) == ["zoe"])
    }

    @Test func parseFollowersLowercases() throws {
        #expect(try ExportParser.parseFollowers(Fixtures.followersJSON(["Zoe"])).map(\.username) == ["zoe"])
    }

    @Test func parseFollowersKeepsTimestamp() throws {
        let json = #"[{"string_list_data":[{"value":"aa","timestamp":1600000000}]}]"#
        let f = try ExportParser.parseFollowers(Data(json.utf8))
        #expect(f == [ExportedFollow(
            username: "aa",
            profileURL: URL(string: "https://www.instagram.com/_u/aa")!,
            followedSince: Date(timeIntervalSince1970: 1_600_000_000)
        )])
    }

    @Test func usernameFallsBackToValueThenHref() throws {
        let json = """
        [{"title":"","string_list_data":[{"value":"FromValue","href":"https://www.instagram.com/x"}]},
         {"title":"","string_list_data":[{"href":"https://www.instagram.com/_u/FromHref"}]},
         {"title":"","string_list_data":[]}]
        """
        let f = try ExportParser.parseFollowing(Data(json.utf8))
        #expect(f.map(\.username) == ["fromvalue", "fromhref"])
    }

    @Test func missingTimestampGivesNilDate() throws {
        let f = try ExportParser.parseFollowing(Fixtures.followingJSON([("anna", nil)]))
        #expect(f.first?.followedSince == nil)
    }

    @Test func rejectsUnknownRoot() {
        #expect(throws: ExportParserError.unrecognizedFormat) {
            try ExportParser.parseFollowing(Data(#"{"foo": 1}"#.utf8))
        }
        #expect(throws: ExportParserError.unrecognizedFormat) {
            try ExportParser.parseFollowers(Data("not json".utf8))
        }
    }

    @Test func fixesMojibake() {
        #expect(ExportParser.fixMojibake("caff\u{00C3}\u{00A8}") == "caffè")
        #expect(ExportParser.fixMojibake("caffè") == "caffè")
        #expect(ExportParser.fixMojibake("plain") == "plain")
        #expect(ExportParser.fixMojibake("日本") == "日本")
    }
}

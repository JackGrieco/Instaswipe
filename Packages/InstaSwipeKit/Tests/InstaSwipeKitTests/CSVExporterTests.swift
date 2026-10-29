import Testing
import Foundation
@testable import InstaSwipeKit

@Suite struct CSVExporterTests {
    private static let header = "username,link,data follow,decisione,fatto,ti segue"

    @Test func csvHasExactHeaderAndEscapes() {
        let csv = CSVExporter.csv(for: [])
        #expect(csv.components(separatedBy: "\n")[0] == Self.header)
        #expect(CSVExporter.escape("a,\"b\"") == "\"a,\"\"b\"\"\"")
        #expect(CSVExporter.escape("line\nbreak") == "\"line\nbreak\"")
        #expect(CSVExporter.escape("plain") == "plain")
    }

    @Test func csvFormatsDecisionAndFlagsInItalian() {
        let since = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2024, month: 3, day: 5, hour: 12))!
        let accounts = [
            Fixtures.account("mario", since: since, decision: .remove, followsMe: true, unfollowedManually: true),
            Fixtures.account("anna", since: nil, decision: .keep),
            Fixtures.account("zed", since: nil)
        ]
        let lines = CSVExporter.csv(for: accounts).components(separatedBy: "\n")
        #expect(lines[1] == "mario,https://www.instagram.com/_u/mario,2024-03-05,tolgo,sì,sì")
        #expect(lines[2] == "anna,https://www.instagram.com/_u/anna,,tengo,no,no")
        #expect(lines[3] == "zed,https://www.instagram.com/_u/zed,,da decidere,no,no")
        #expect(lines.count == 4)
    }
}

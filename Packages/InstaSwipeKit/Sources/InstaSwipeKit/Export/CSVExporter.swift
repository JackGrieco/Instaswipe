import Foundation

public enum CSVExporter {
    static let header = "username,link,data follow,decisione,fatto,ti segue"

    public static func csv(for accounts: [FollowedAccount]) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let rows = accounts.map { row(for: $0, formatter: formatter) }
        return ([header] + rows).joined(separator: "\n")
    }

    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func row(for account: FollowedAccount, formatter: DateFormatter) -> String {
        [
            account.username,
            account.profileURL.absoluteString,
            account.followedSince.map(formatter.string(from:)) ?? "",
            decisionLabel(account.decision),
            yesNo(account.unfollowedManually),
            yesNo(account.followsMe)
        ].map(escape).joined(separator: ",")
    }

    private static func decisionLabel(_ decision: Decision) -> String {
        switch decision {
        case .pending: "da decidere"
        case .keep: "tengo"
        case .remove: "tolgo"
        }
    }

    private static func yesNo(_ value: Bool) -> String { value ? "sì" : "no" }
}

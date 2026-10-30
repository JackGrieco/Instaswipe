import Foundation

public enum CSVExporter {
    static func header(for mode: ListMode) -> String {
        switch mode {
        case .following: "username,link,data follow,decisione,fatto,ti segue"
        case .followers: "username,link,ti segue dal,decisione,fatto,lo segui"
        }
    }

    public static func csv(for accounts: [FollowedAccount], mode: ListMode = .following) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let rows = accounts.map { row(for: $0, formatter: formatter) }
        return ([header(for: mode)] + rows).joined(separator: "\n")
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
        case .unsure: "in dubbio"
        }
    }

    private static func yesNo(_ value: Bool) -> String { value ? "sì" : "no" }
}

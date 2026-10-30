import Foundation

public struct ExportedFollow: Equatable, Sendable {
    public let username: String
    public let profileURL: URL
    public let followedSince: Date?

    public init(username: String, profileURL: URL, followedSince: Date?) {
        self.username = username
        self.profileURL = profileURL
        self.followedSince = followedSince
    }
}

public enum ExportParserError: Error, Equatable {
    case unrecognizedFormat
    case followingNotFound
}

public enum ExportParser {
    private static let profileURLPrefix = "https://www.instagram.com/_u/"
    private static let relationshipsKeyPrefix = "relationships_"

    public static func parseFollowing(_ data: Data) throws -> [ExportedFollow] {
        try entries(in: data).compactMap { entry in
            guard let username = username(from: entry),
                  let url = URL(string: profileURLPrefix + username) else { return nil }
            return ExportedFollow(username: username, profileURL: url, followedSince: timestamp(from: entry))
        }
    }

    /// Same file shape as following; `followedSince` is when that account started following you.
    public static func parseFollowers(_ data: Data) throws -> [ExportedFollow] {
        try parseFollowing(data)
    }

    /// Instagram exports UTF-8 bytes re-encoded as Latin-1 scalars; undo that when possible.
    public static func fixMojibake(_ s: String) -> String {
        let scalars = s.unicodeScalars
        guard scalars.allSatisfy({ $0.value <= 0xFF }) else { return s }
        let bytes = scalars.map { UInt8($0.value) }
        guard let fixed = String(bytes: bytes, encoding: .utf8), fixed != s else { return s }
        return fixed
    }

    // MARK: - Private

    private static func entries(in data: Data) throws -> [[String: Any]] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            throw ExportParserError.unrecognizedFormat
        }
        if let array = root as? [Any] { return array.compactMap { $0 as? [String: Any] } }
        if let object = root as? [String: Any],
           let key = object.keys.sorted().first(where: {
               $0.hasPrefix(relationshipsKeyPrefix) && object[$0] is [Any]
           }),
           let array = object[key] as? [Any] {
            return array.compactMap { $0 as? [String: Any] }
        }
        throw ExportParserError.unrecognizedFormat
    }

    private static func username(from entry: [String: Any]) -> String? {
        let data = (entry["string_list_data"] as? [[String: Any]])?.first
        let candidates: [String?] = [
            entry["title"] as? String,
            data?["value"] as? String,
            (data?["href"] as? String).flatMap { URL(string: $0)?.lastPathComponent }
        ]
        guard let raw = candidates.compactMap({ $0 }).first(where: { !$0.isEmpty }) else { return nil }
        return fixMojibake(raw).lowercased()
    }

    private static func timestamp(from entry: [String: Any]) -> Date? {
        let data = (entry["string_list_data"] as? [[String: Any]])?.first
        guard let seconds = (data?["timestamp"] as? NSNumber)?.doubleValue else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}

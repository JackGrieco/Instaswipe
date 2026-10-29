import Foundation
@testable import InstaSwipe

/// Shared helpers for `AppModel` tests.
enum TestSupport {
    static func makeDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Each call gets its own `UserDefaults` suite, so tutorial progress never leaks between tests.
    static func environment(local: URL, cloud: URL? = nil) -> AppEnvironment {
        AppEnvironment(
            localDirectory: local, cloudDirectory: cloud, isUITesting: true,
            useFakeProfiles: true, shouldSeedTestAccounts: false,
            defaultsSuiteName: UUID().uuidString
        )
    }

    /// Export folder whose following.json lists `usernames`.
    static func makeExport(_ usernames: [String]) throws -> URL {
        let dir = try makeDirectory()
        let items: [[String: Any]] = usernames.map { name in
            ["title": name, "media_list_data": [],
             "string_list_data": [["href": "https://www.instagram.com/_u/\(name)", "timestamp": 1_600_000_000]]]
        }
        let data = try JSONSerialization.data(withJSONObject: ["relationships_following": items])
        try data.write(to: dir.appendingPathComponent("following.json"))
        return dir
    }
}

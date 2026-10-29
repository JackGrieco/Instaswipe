import Foundation
@testable import InstaSwipe

/// Shared helpers for `AppModel` tests.
enum TestSupport {
    static func makeDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func environment(local: URL, cloud: URL? = nil) -> AppEnvironment {
        AppEnvironment(
            localDirectory: local, cloudDirectory: cloud, isUITesting: true,
            useFakeProfiles: true, shouldSeedTestAccounts: false
        )
    }
}

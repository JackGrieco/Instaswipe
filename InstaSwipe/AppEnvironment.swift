import Foundation

struct AppEnvironment: Sendable {
    static let cloudContainerIdentifier = "iCloud.com.giacomogrieco.InstaSwipe"
    private static let stateDirArgument = "-uiTestStateDir"
    private static let seedArgument = "-uiTestSeed"

    let localDirectory: URL
    let cloudDirectory: URL?
    let isUITesting: Bool
    let useFakeProfiles: Bool
    let shouldSeedTestAccounts: Bool
    /// `UserDefaults` suite for UI preferences; nil means `.standard`.
    let defaultsSuiteName: String?

    /// Resolves directories off the main thread: the ubiquity container lookup can block.
    static func resolve(arguments: [String] = ProcessInfo.processInfo.arguments) async -> AppEnvironment {
        if let index = arguments.firstIndex(of: stateDirArgument), arguments.indices.contains(index + 1) {
            return AppEnvironment(
                localDirectory: URL(fileURLWithPath: arguments[index + 1], isDirectory: true),
                cloudDirectory: nil,
                isUITesting: true,
                useFakeProfiles: true,
                shouldSeedTestAccounts: arguments.contains(seedArgument),
                // One suite per state dir: fresh for each test, kept across a relaunch.
                defaultsSuiteName: "uitest-" + URL(fileURLWithPath: arguments[index + 1]).lastPathComponent
            )
        }
        let cloud = await Task.detached(priority: .userInitiated) { cloudDocumentsDirectory() }.value
        return AppEnvironment(
            localDirectory: localSupportDirectory(),
            cloudDirectory: cloud,
            isUITesting: false,
            useFakeProfiles: false,
            shouldSeedTestAccounts: false,
            defaultsSuiteName: nil
        )
    }

    var defaults: UserDefaults {
        defaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    private static func localSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("InstaSwipe", isDirectory: true)
    }

    private static func cloudDocumentsDirectory() -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: cloudContainerIdentifier)?
            .appendingPathComponent("Documents", isDirectory: true)
    }
}

import Foundation
import InstaSwipeKit
import Testing
@testable import InstaSwipe

@MainActor
struct AppModelTests {
    private func makeDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func environment(local: URL, cloud: URL? = nil) -> AppEnvironment {
        AppEnvironment(
            localDirectory: local, cloudDirectory: cloud, isUITesting: true,
            useFakeProfiles: true, shouldSeedTestAccounts: false
        )
    }

    private func account(_ name: String) -> FollowedAccount {
        FollowedAccount(
            username: name, profileURL: URL(string: "https://www.instagram.com/_u/\(name)")!,
            followedSince: Date(timeIntervalSince1970: 1_600_000_000)
        )
    }

    private func seedState(in local: URL, accounts: [String]) throws {
        var state = AppState.empty(now: Date(timeIntervalSince1970: 1_700_000_000))
        state.accounts = accounts.map(account)
        try FileStateStore(localDirectory: local, cloudDirectory: nil).save(state)
    }

    /// Export folder whose following.json lists `usernames`.
    private func makeExport(_ usernames: [String]) throws -> URL {
        let dir = try makeDirectory()
        let items: [[String: Any]] = usernames.map { name in
            ["title": name, "media_list_data": [],
             "string_list_data": [["href": "https://www.instagram.com/_u/\(name)", "timestamp": 1_600_000_000]]]
        }
        let data = try JSONSerialization.data(withJSONObject: ["relationships_following": items])
        try data.write(to: dir.appendingPathComponent("following.json"))
        return dir
    }

    private func setPermissions(_ mode: Int, _ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }

    @Test func corruptStateBlocksEverythingAndKeepsTheFile() throws {
        let local = try makeDirectory()
        try Data("not json".utf8).write(to: local.appendingPathComponent("state.json"))

        let model = AppModel(environment: environment(local: local))
        model.apply { $0 }

        #expect(model.loadError != nil)
        #expect(model.state == nil)
        #expect(!FileManager.default.fileExists(atPath: local.appendingPathComponent("state.json").path))
        #expect(model.quarantinedFileNames.count == 1)
        let names = try FileManager.default.contentsOfDirectory(atPath: local.path)
        #expect(names.contains { $0.hasPrefix("state.corrupt-") })
    }

    @Test func missingCloudDirectoryFlagsCloudUnavailable() throws {
        let model = AppModel(environment: environment(local: try makeDirectory(), cloud: nil))
        #expect(!model.isCloudAvailable)
    }

    @Test func failedSaveLeavesStateUnchanged() throws {
        let local = try makeDirectory()
        try seedState(in: local, accounts: ["a"])
        let model = AppModel(environment: environment(local: local))
        let before = try #require(model.state)
        try setPermissions(0o555, local)
        defer { try? setPermissions(0o755, local) }

        model.apply { current in
            var next = current
            next.totalDecisionsMade += 1
            return next
        }

        #expect(model.state == before)
        #expect(model.errorMessage != nil)
    }

    @Test func importAbortsWhenPreImportBackupFails() async throws {
        let local = try makeDirectory()
        try seedState(in: local, accounts: ["a"])
        let backups = local.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        let model = AppModel(environment: environment(local: local))
        let before = try #require(model.state)
        await model.prepareImport(picked: [try makeExport(["a", "b"])])
        #expect(model.pendingMerge != nil)
        try setPermissions(0o555, backups)
        defer { try? setPermissions(0o755, backups) }

        model.confirmImport()

        #expect(model.state == before)
        #expect(model.errorMessage != nil)
        #expect(model.pendingMerge != nil)
    }

    @Test func confirmImportKeepsDecisionsMadeAfterPreview() async throws {
        let local = try makeDirectory()
        try seedState(in: local, accounts: ["a"])
        let model = AppModel(environment: environment(local: local))
        await model.prepareImport(picked: [try makeExport(["a", "b"])])

        model.apply { current in
            var next = current
            next.accounts = next.accounts.map { account in
                var copy = account
                copy.decision = .keep
                return copy
            }
            return next
        }
        model.confirmImport()

        let accounts = try #require(model.state).accounts
        #expect(accounts.first { $0.username == "a" }?.decision == .keep)
        #expect(accounts.contains { $0.username == "b" })
    }

    @Test func importFromPickedJSONFilesWorks() async throws {
        let local = try makeDirectory()
        let model = AppModel(environment: environment(local: local))
        let folder = try makeExport(["x"])
        await model.prepareImport(picked: [folder.appendingPathComponent("following.json")])
        model.confirmImport()
        #expect(model.state?.accounts.map(\.username) == ["x"])
    }

    @Test func exportWithoutFollowsIsRefused() async throws {
        let local = try makeDirectory()
        try seedState(in: local, accounts: ["a"])
        let model = AppModel(environment: environment(local: local))
        let before = try #require(model.state)

        await model.prepareImport(picked: [try makeExport([])])

        #expect(model.pendingMerge == nil)
        #expect(model.errorMessage == "L'export non contiene account seguiti.")
        model.confirmImport()
        #expect(model.state == before)
    }
}

import Foundation
import InstaSwipeKit
import Testing
@testable import InstaSwipe

@MainActor
struct AppModelRestoreTests {
    private func makeDirectory() throws -> URL { try TestSupport.makeDirectory() }

    private func environment(local: URL, cloud: URL? = nil) -> AppEnvironment {
        TestSupport.environment(local: local, cloud: cloud)
    }

    private func state(_ usernames: [String]) -> AppState {
        var state = AppState.empty(now: Date(timeIntervalSince1970: 1_700_000_000))
        state.accounts = usernames.map { name in
            FollowedAccount(
                username: name, profileURL: URL(string: "https://www.instagram.com/_u/\(name)")!,
                followedSince: Date(timeIntervalSince1970: 1_600_000_000)
            )
        }
        return state
    }

    private func writeBackup(_ data: Data, named name: String, in backups: URL, modified: TimeInterval) throws {
        let url = backups.appendingPathComponent(name)
        try data.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: modified)], ofItemAtPath: url.path)
    }

    /// Local folder with a corrupt state.json and an empty Backups folder.
    private func corruptedLocal() throws -> (local: URL, backups: URL) {
        let local = try makeDirectory()
        try Data("not json".utf8).write(to: local.appendingPathComponent("state.json"))
        let backups = local.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        return (local, backups)
    }

    @Test func restorePicksNewestDecodableBackupAndApplyWorksAfterwards() throws {
        let (local, backups) = try corruptedLocal()
        let encoder = StateCoding.encoder()
        try writeBackup(try encoder.encode(state(["old"])), named: "daily-2023-11-14.json", in: backups, modified: 1_700_000_000)
        try writeBackup(try encoder.encode(state(["a", "b"])), named: "step-100.json", in: backups, modified: 1_700_100_000)
        try writeBackup(Data("broken".utf8), named: "daily-2023-11-16.json", in: backups, modified: 1_700_200_000)
        let model = AppModel(environment: environment(local: local))
        #expect(model.loadError != nil)

        model.prepareRestore()
        #expect(model.pendingRestore?.state.accounts.map(\.username) == ["a", "b"])
        model.confirmRestore()

        #expect(model.loadError == nil)
        #expect(model.pendingRestore == nil)
        #expect(model.state?.accounts.map(\.username) == ["a", "b"])
        model.apply { Review.decide(.keep, username: "a", in: $0, now: Date()) }
        let saved = try FileStateStore(localDirectory: local, cloudDirectory: nil).load()
        #expect(saved?.accounts.first { $0.username == "a" }?.decision == .keep)
        let names = try FileManager.default.contentsOfDirectory(atPath: local.path)
        #expect(names.contains { $0.hasPrefix("state.corrupt-") })
    }

    @Test func restoreWithoutBackupsShowsErrorAndKeepsBlocking() throws {
        let (local, _) = try corruptedLocal()
        let model = AppModel(environment: environment(local: local))

        model.prepareRestore()
        model.confirmRestore()

        #expect(model.pendingRestore == nil)
        #expect(model.errorMessage == "Non ho trovato copie di sicurezza leggibili.")
        #expect(model.loadError != nil)
    }

    @Test func cancelRestoreKeepsBlocking() throws {
        let (local, backups) = try corruptedLocal()
        try writeBackup(try StateCoding.encoder().encode(state(["a"])), named: "step-100.json", in: backups, modified: 1_700_000_000)
        let model = AppModel(environment: environment(local: local))

        model.prepareRestore()
        model.cancelRestore()
        model.confirmRestore()

        #expect(model.state == nil)
        #expect(model.loadError != nil)
    }

    @Test func retryLoadRecoversWhenAReadableStateAppears() throws {
        let (local, _) = try corruptedLocal()
        let model = AppModel(environment: environment(local: local))
        #expect(model.loadError != nil)
        try FileStateStore(localDirectory: local, cloudDirectory: nil).save(state(["a"]))

        model.retryLoad()

        #expect(model.loadError == nil)
        #expect(model.state?.accounts.map(\.username) == ["a"])
    }

    @Test func corruptionMessageDependsOnCloudAvailability() throws {
        let localOnly = AppModel(environment: environment(local: try corruptedLocal().local))
        let cloud = try makeDirectory()
        let withCloud = AppModel(environment: environment(local: try corruptedLocal().local, cloud: cloud))

        #expect(localOnly.loadError?.contains("dentro l'app") == true)
        #expect(localOnly.loadError?.contains("iCloud Drive") == false)
        #expect(withCloud.loadError?.contains("File → iCloud Drive → InstaSwipe → Backups") == true)
    }
}

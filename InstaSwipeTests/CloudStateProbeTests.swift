import Foundation
import InstaSwipeKit
import Testing
@testable import InstaSwipe

@MainActor
final class FakeCloudStateProbe: CloudStateProbe {
    /// File names the fake iCloud holds.
    let existing: Set<String>
    /// File names asked for, in order.
    private(set) var calls: [String] = []

    init(existing: Set<String>) {
        self.existing = existing
    }

    func cloudFileExists(named fileName: String) async -> Bool {
        calls = calls + [fileName]
        return existing.contains(fileName)
    }
}

@MainActor
struct CloudStateProbeTests {
    private func model(probe: FakeCloudStateProbe, cloud: URL?) throws -> AppModel {
        AppModel(environment: TestSupport.environment(local: try TestSupport.makeDirectory(), cloud: cloud), cloudProbe: probe)
    }

    @Test func checkingScreenWhileProbeRunsNeverImport() throws {
        let model = try model(probe: FakeCloudStateProbe(existing: []), cloud: try TestSupport.makeDirectory())
        #expect(model.rootScreen == .checkingCloud)
    }

    @Test func probeFindsCloudStateSoAppWaitsInsteadOfImporting() async throws {
        let probe = FakeCloudStateProbe(existing: ["state.json"])
        let model = try model(probe: probe, cloud: try TestSupport.makeDirectory())

        await model.cloudCheckTask?.value

        #expect(probe.calls == ["state.json"])
        #expect(model.rootScreen == .waitingForCloud)
        #expect(model.isWaitingForCloud)
    }

    @Test func waitingForCloudStateNeverSaves() async throws {
        let model = try model(probe: FakeCloudStateProbe(existing: ["state.json"]), cloud: try TestSupport.makeDirectory())
        await model.cloudCheckTask?.value

        await model.prepareImport(picked: [try TestSupport.makeDirectory()])

        #expect(model.pendingMerge == nil)
        #expect(model.state == nil)
    }

    @Test func probeFindsNothingSoImportIsShownWithConfirmation() async throws {
        let model = try model(probe: FakeCloudStateProbe(existing: []), cloud: try TestSupport.makeDirectory())

        await model.cloudCheckTask?.value

        #expect(model.rootScreen == .importer)
        #expect(model.needsFirstImportConfirmation)
    }

    @Test func waitingEndsWhenTheCloudStateArrives() async throws {
        let cloud = try TestSupport.makeDirectory()
        let model = try model(probe: FakeCloudStateProbe(existing: ["state.json"]), cloud: cloud)
        await model.cloudCheckTask?.value
        var state = AppState.empty(now: Date(timeIntervalSince1970: 1_700_000_000))
        state.totalDecisionsMade = 42
        try StateCoding.encoder().encode(state).write(to: cloud.appendingPathComponent("state.json"))

        model.retryLoad()
        // With the state in, the probe is asked once for followers.json (not in this fake iCloud).
        await model.cloudCheckTask?.value

        #expect(model.rootScreen == .main)
        #expect(model.state?.totalDecisionsMade == 42)
    }

    @Test func withoutCloudTheProbeIsSkipped() throws {
        let probe = FakeCloudStateProbe(existing: ["state.json"])
        let model = try model(probe: probe, cloud: nil)

        #expect(model.cloudCheckTask == nil)
        #expect(probe.calls.isEmpty)
        #expect(model.rootScreen == .importer)
        #expect(!model.needsFirstImportConfirmation)
    }

    @Test func existingLocalListsSkipTheProbe() throws {
        let local = try TestSupport.makeDirectory()
        try FileStateStore(localDirectory: local, cloudDirectory: nil).save(AppState.empty(now: Date()))
        try FollowerStore(localDirectory: local, cloudDirectory: nil).save(FollowerState.empty(now: Date()))
        let probe = FakeCloudStateProbe(existing: [])
        let model = AppModel(
            environment: TestSupport.environment(local: local, cloud: try TestSupport.makeDirectory()), cloudProbe: probe
        )

        #expect(model.cloudCheckTask == nil)
        #expect(model.rootScreen == .main)
    }

    // MARK: followers.json not yet listed by iCloud

    /// Local state.json only; the cloud folder is empty, as on a fresh install before iCloud lists the files.
    private func modelWithStateOnly(probe: FakeCloudStateProbe) throws -> (model: AppModel, local: URL, cloud: URL) {
        let local = try TestSupport.makeDirectory()
        let cloud = try TestSupport.makeDirectory()
        var state = AppState.empty(now: Date(timeIntervalSince1970: 1_700_000_000))
        state.accounts = [FollowedAccount(username: "a", profileURL: URL(string: "https://www.instagram.com/_u/a")!, followedSince: nil)]
        try FileStateStore(localDirectory: local, cloudDirectory: nil).save(state)
        let model = AppModel(environment: TestSupport.environment(local: local, cloud: cloud), cloudProbe: probe)
        return (model, local, cloud)
    }

    @Test func probeFindsCloudFollowersSoAppWaitsAndSavesNothing() async throws {
        let probe = FakeCloudStateProbe(existing: ["followers.json"])
        let (model, local, cloud) = try modelWithStateOnly(probe: probe)
        #expect(model.rootScreen == .checkingCloud)
        let stateBefore = try Data(contentsOf: local.appendingPathComponent("state.json"))

        await model.cloudCheckTask?.value
        model.apply { Review.decide(.keep, username: "a", in: $0, now: Date()) }
        await model.prepareImport(picked: [try TestSupport.makeExport(["a"], followers: ["a"])])
        model.confirmImport()
        await model.flushCloudMirror()

        #expect(probe.calls == ["followers.json"])
        #expect(model.rootScreen == .waitingForCloud)
        #expect(model.pendingMerge == nil)
        #expect(try Data(contentsOf: local.appendingPathComponent("state.json")) == stateBefore)
        #expect(!FileManager.default.fileExists(atPath: local.appendingPathComponent("followers.json").path))
        #expect(!FileManager.default.fileExists(atPath: cloud.appendingPathComponent("followers.json").path))
    }

    @Test func waitingEndsWhenTheCloudFollowersArrive() async throws {
        let (model, _, cloud) = try modelWithStateOnly(probe: FakeCloudStateProbe(existing: ["followers.json"]))
        await model.cloudCheckTask?.value
        var followers = FollowerState.empty(now: Date(timeIntervalSince1970: 1_700_000_000))
        followers.totalDecisionsMade = 7
        try StateCoding.encoder().encode(followers).write(to: cloud.appendingPathComponent("followers.json"))

        model.retryLoad()

        #expect(model.rootScreen == .main)
        #expect(model.followers?.totalDecisionsMade == 7)
    }

    @Test func probeFindsNoCloudFollowersSoAppLoadsWithoutThem() async throws {
        let probe = FakeCloudStateProbe(existing: [])
        let (model, _, _) = try modelWithStateOnly(probe: probe)

        await model.cloudCheckTask?.value

        #expect(probe.calls == ["followers.json"])
        #expect(model.rootScreen == .main)
        #expect(model.state?.accounts.count == 1)
        #expect(model.followers == nil)
    }
}

import Foundation
import InstaSwipeKit
import Testing
@testable import InstaSwipe

@MainActor
final class FakeCloudStateProbe: CloudStateProbe {
    /// File names the fake iCloud holds.
    let existing: Set<String>
    /// File names whose query times out.
    let timingOut: Set<String>
    /// File names asked for, in order.
    private(set) var calls: [String] = []

    init(existing: Set<String>, timingOut: Set<String> = []) {
        self.existing = existing
        self.timingOut = timingOut
    }

    func cloudFile(named fileName: String) async -> CloudProbeAnswer {
        calls = calls + [fileName]
        if timingOut.contains(fileName) { return .unknown }
        return existing.contains(fileName) ? .found : .absent
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

    private func stateWithOneAccount() -> AppState {
        var state = AppState.empty(now: Date(timeIntervalSince1970: 1_700_000_000))
        state.accounts = [FollowedAccount(username: "a", profileURL: URL(string: "https://www.instagram.com/_u/a")!, followedSince: nil)]
        return state
    }

    /// Fresh install: no local files, iCloud has state.json but has not listed followers.json yet.
    private func modelWithStateOnly(probe: FakeCloudStateProbe) throws -> (model: AppModel, local: URL, cloud: URL) {
        let launch = try freshInstall(probe: probe)
        return (launch.model, launch.environment.localDirectory, try #require(launch.environment.cloudDirectory))
    }

    private func freshInstall(probe: FakeCloudStateProbe) throws -> (model: AppModel, environment: AppEnvironment) {
        let cloud = try TestSupport.makeDirectory()
        try StateCoding.encoder().encode(stateWithOneAccount()).write(to: cloud.appendingPathComponent("state.json"))
        let environment = TestSupport.environment(local: try TestSupport.makeDirectory(), cloud: cloud)
        return (AppModel(environment: environment, cloudProbe: probe), environment)
    }

    private func isFollowerProbePending(_ environment: AppEnvironment) -> Bool {
        environment.defaults.bool(forKey: "followerCloudProbePending")
    }

    /// Force-quit on the waiting screen: the first launch already copied state.json locally, but
    /// the next one must still look for the followers instead of offering a reimport.
    @Test func relaunchDuringTheFollowerWaitStillWaits() async throws {
        let (first, environment) = try freshInstall(probe: FakeCloudStateProbe(existing: ["followers.json"]))
        await first.cloudCheckTask?.value
        #expect(first.rootScreen == .waitingForCloud)
        let probe = FakeCloudStateProbe(existing: ["followers.json"])

        let relaunched = AppModel(environment: environment, cloudProbe: probe)
        await relaunched.cloudCheckTask?.value

        #expect(probe.calls == ["followers.json"])
        #expect(relaunched.rootScreen == .waitingForCloud)
        #expect(isFollowerProbePending(environment))
    }

    @Test func probeTimeoutKeepsLookingOnTheNextLaunch() async throws {
        let (first, environment) = try freshInstall(probe: FakeCloudStateProbe(existing: [], timingOut: ["followers.json"]))
        await first.cloudCheckTask?.value
        #expect(first.rootScreen == .main)
        #expect(first.followers == nil)
        #expect(isFollowerProbePending(environment))
        let probe = FakeCloudStateProbe(existing: [])

        let relaunched = AppModel(environment: environment, cloudProbe: probe)
        await relaunched.cloudCheckTask?.value

        #expect(probe.calls == ["followers.json"])
        #expect(relaunched.rootScreen == .main)
        #expect(!isFollowerProbePending(environment))
    }

    /// iCloud that never answers must not cost a wait on every launch forever.
    @Test func threeUnknownAnswersInARowStopTheProbe() async throws {
        let timingOut = { FakeCloudStateProbe(existing: [], timingOut: ["followers.json"]) }
        let (first, environment) = try freshInstall(probe: timingOut())
        await first.cloudCheckTask?.value
        let second = AppModel(environment: environment, cloudProbe: timingOut())
        await second.cloudCheckTask?.value
        #expect(isFollowerProbePending(environment))
        let third = AppModel(environment: environment, cloudProbe: timingOut())
        await third.cloudCheckTask?.value
        #expect(!isFollowerProbePending(environment))
        let probe = FakeCloudStateProbe(existing: ["followers.json"])

        let fourth = AppModel(environment: environment, cloudProbe: probe)

        #expect(probe.calls.isEmpty)
        #expect(fourth.rootScreen == .main)
    }

    /// Only consecutive unknowns count: a definite answer in between starts the count again.
    @Test func aDefiniteAnswerResetsTheUnknownCount() async throws {
        let timingOut = { FakeCloudStateProbe(existing: [], timingOut: ["followers.json"]) }
        let (first, environment) = try freshInstall(probe: timingOut())
        await first.cloudCheckTask?.value
        let second = AppModel(environment: environment, cloudProbe: timingOut())
        await second.cloudCheckTask?.value
        // iCloud lists the file; the app is closed before it downloads.
        let finding = AppModel(environment: environment, cloudProbe: FakeCloudStateProbe(existing: ["followers.json"]))
        await finding.cloudCheckTask?.value
        #expect(finding.rootScreen == .waitingForCloud)

        let afterFound = AppModel(environment: environment, cloudProbe: timingOut())
        await afterFound.cloudCheckTask?.value
        #expect(isFollowerProbePending(environment))
        let again = AppModel(environment: environment, cloudProbe: timingOut())
        await again.cloudCheckTask?.value

        #expect(isFollowerProbePending(environment))
    }

    @Test func definiteAbsenceStopsTheProbeOnLaterLaunches() async throws {
        let (first, environment) = try freshInstall(probe: FakeCloudStateProbe(existing: []))
        await first.cloudCheckTask?.value
        #expect(!isFollowerProbePending(environment))
        let probe = FakeCloudStateProbe(existing: ["followers.json"])

        let relaunched = AppModel(environment: environment, cloudProbe: probe)

        #expect(probe.calls.isEmpty)
        #expect(relaunched.rootScreen == .main)
    }

    @Test func loadedFollowersClearThePendingFlag() async throws {
        let (first, environment) = try freshInstall(probe: FakeCloudStateProbe(existing: ["followers.json"]))
        await first.cloudCheckTask?.value
        let followers = FollowerState.empty(now: Date(timeIntervalSince1970: 1_700_000_000))
        try StateCoding.encoder().encode(followers).write(to: try #require(environment.cloudDirectory).appendingPathComponent("followers.json"))

        first.retryLoad()

        #expect(first.rootScreen == .main)
        #expect(!isFollowerProbePending(environment))
    }

    /// A device with its own state.json and no followers.json simply never imported followers.
    @Test func localStateWithoutFollowersSkipsTheProbe() throws {
        let local = try TestSupport.makeDirectory()
        try FileStateStore(localDirectory: local, cloudDirectory: nil).save(stateWithOneAccount())
        let probe = FakeCloudStateProbe(existing: ["followers.json"])

        let model = AppModel(environment: TestSupport.environment(local: local, cloud: try TestSupport.makeDirectory()), cloudProbe: probe)

        #expect(probe.calls.isEmpty)
        #expect(model.cloudCheckTask == nil)
        #expect(model.rootScreen == .main)
        #expect(model.followers == nil)
    }

    @Test func probeFindsCloudFollowersSoAppWaitsAndSavesNothing() async throws {
        let probe = FakeCloudStateProbe(existing: ["followers.json"])
        let (model, local, cloud) = try modelWithStateOnly(probe: probe)
        #expect(model.rootScreen == .checkingCloud)
        // The load already copied the iCloud state locally; nothing may change it afterwards.
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

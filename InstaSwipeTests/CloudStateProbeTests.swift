import Foundation
import InstaSwipeKit
import Testing
@testable import InstaSwipe

@MainActor
final class FakeCloudStateProbe: CloudStateProbe {
    let exists: Bool
    private(set) var calls = 0

    init(exists: Bool) {
        self.exists = exists
    }

    func cloudStateExists() async -> Bool {
        calls += 1
        return exists
    }
}

@MainActor
struct CloudStateProbeTests {
    private func model(probe: FakeCloudStateProbe, cloud: URL?) throws -> AppModel {
        AppModel(environment: TestSupport.environment(local: try TestSupport.makeDirectory(), cloud: cloud), cloudProbe: probe)
    }

    @Test func checkingScreenWhileProbeRunsNeverImport() throws {
        let model = try model(probe: FakeCloudStateProbe(exists: false), cloud: try TestSupport.makeDirectory())
        #expect(model.rootScreen == .checkingCloud)
    }

    @Test func probeFindsCloudStateSoAppWaitsInsteadOfImporting() async throws {
        let probe = FakeCloudStateProbe(exists: true)
        let model = try model(probe: probe, cloud: try TestSupport.makeDirectory())

        await model.cloudCheckTask?.value

        #expect(probe.calls == 1)
        #expect(model.rootScreen == .waitingForCloud)
        #expect(model.isWaitingForCloud)
    }

    @Test func waitingForCloudStateNeverSaves() async throws {
        let model = try model(probe: FakeCloudStateProbe(exists: true), cloud: try TestSupport.makeDirectory())
        await model.cloudCheckTask?.value

        await model.prepareImport(picked: [try TestSupport.makeDirectory()])

        #expect(model.pendingMerge == nil)
        #expect(model.state == nil)
    }

    @Test func probeFindsNothingSoImportIsShownWithConfirmation() async throws {
        let model = try model(probe: FakeCloudStateProbe(exists: false), cloud: try TestSupport.makeDirectory())

        await model.cloudCheckTask?.value

        #expect(model.rootScreen == .importer)
        #expect(model.needsFirstImportConfirmation)
    }

    @Test func waitingEndsWhenTheCloudStateArrives() async throws {
        let cloud = try TestSupport.makeDirectory()
        let model = try model(probe: FakeCloudStateProbe(exists: true), cloud: cloud)
        await model.cloudCheckTask?.value
        var state = AppState.empty(now: Date(timeIntervalSince1970: 1_700_000_000))
        state.totalDecisionsMade = 42
        try StateCoding.encoder().encode(state).write(to: cloud.appendingPathComponent("state.json"))

        model.retryLoad()

        #expect(model.rootScreen == .main)
        #expect(model.state?.totalDecisionsMade == 42)
    }

    @Test func withoutCloudTheProbeIsSkipped() throws {
        let probe = FakeCloudStateProbe(exists: true)
        let model = try model(probe: probe, cloud: nil)

        #expect(model.cloudCheckTask == nil)
        #expect(probe.calls == 0)
        #expect(model.rootScreen == .importer)
        #expect(!model.needsFirstImportConfirmation)
    }

    @Test func existingLocalStateSkipsTheProbe() throws {
        let local = try TestSupport.makeDirectory()
        try FileStateStore(localDirectory: local, cloudDirectory: nil).save(AppState.empty(now: Date()))
        let probe = FakeCloudStateProbe(exists: false)
        let model = AppModel(
            environment: TestSupport.environment(local: local, cloud: try TestSupport.makeDirectory()), cloudProbe: probe
        )

        #expect(model.cloudCheckTask == nil)
        #expect(model.rootScreen == .main)
    }
}

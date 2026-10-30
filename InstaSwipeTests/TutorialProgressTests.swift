import Foundation
import Testing
@testable import InstaSwipe

@MainActor
struct TutorialProgressTests {
    private func makeModel(_ environment: AppEnvironment) -> AppModel {
        AppModel(environment: environment)
    }

    private func freshEnvironment() throws -> AppEnvironment {
        TestSupport.environment(local: try TestSupport.makeDirectory())
    }

    @Test func freshModelHasNotStartedExport() throws {
        let model = makeModel(try freshEnvironment())
        #expect(!model.hasStartedExport)
    }

    @Test func markExportStartedSurvivesANewModel() throws {
        let environment = try freshEnvironment()
        makeModel(environment).markExportStarted()

        #expect(makeModel(environment).hasStartedExport)
    }

    @Test func confirmedImportResetsTheResumePoint() async throws {
        let environment = try freshEnvironment()
        let model = makeModel(environment)
        model.markExportStarted()

        await model.prepareImport(picked: [try TestSupport.makeExport(["a"])])
        model.confirmImport()

        #expect(!model.hasStartedExport)
        #expect(!makeModel(environment).hasStartedExport)
        #expect(model.confirmedImportCount == 1)
    }

    @Test func cancelledImportKeepsTheResumePoint() async throws {
        let model = makeModel(try freshEnvironment())
        model.markExportStarted()

        await model.prepareImport(picked: [try TestSupport.makeExport(["a"])])
        model.cancelImport()

        #expect(model.hasStartedExport)
        #expect(model.confirmedImportCount == 0)
    }

    @Test func failedImportKeepsTheResumePoint() async throws {
        let model = makeModel(try freshEnvironment())
        model.markExportStarted()

        await model.prepareImport(picked: [try TestSupport.makeDirectory()])

        #expect(model.errorMessage != nil)
        #expect(model.hasStartedExport)
    }

    @Test func restartTutorialClearsTheResumePoint() throws {
        let environment = try freshEnvironment()
        let model = makeModel(environment)
        model.markExportStarted()

        model.restartTutorial()

        #expect(!model.hasStartedExport)
        #expect(!makeModel(environment).hasStartedExport)
    }
}

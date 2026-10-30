import Testing
@testable import InstaSwipe

struct ExportTutorialTests {
    @Test func fourteenStepsNumberedInOrder() {
        #expect(ExportTutorial.steps.map(\.number) == Array(1...14))
    }

    @Test func phasesSplitStepsAsInTheSpec() {
        #expect(TutorialPhase.openExport.steps.map(\.number) == Array(1...6))
        #expect(TutorialPhase.chooseData.steps.map(\.number) == Array(7...10))
        #expect(TutorialPhase.waitForEmail.steps.map(\.number) == [11])
        #expect(TutorialPhase.importFile.steps.map(\.number) == [12, 13, 14])
    }

    @Test func stepTextsMatchTheSpec() {
        #expect(ExportTutorial.steps[6].text == "In «Personalizza informazioni» deseleziona tutto tranne «Follower e persone/Pagine seguite»")
        #expect(ExportTutorial.steps[13].text == "Comincia a swipare!")
    }

    @Test func imageNamesAreZeroPaddedAndLastStepHasNone() {
        #expect(ExportTutorial.steps[4].imageName == "TutorialStep05")
        #expect(ExportTutorial.steps[13].imageName == nil)
    }

    @Test func startsFromImportOnlyAfterExportStarted() {
        #expect(ExportTutorial.startPhase(hasStartedExport: false) == .openExport)
        #expect(ExportTutorial.startPhase(hasStartedExport: true) == .importFile)
    }

    @Test func phaseNavigationStopsAtTheEnds() {
        #expect(TutorialPhase.openExport.previous == nil)
        #expect(TutorialPhase.importFile.next == nil)
        #expect(TutorialPhase.chooseData.next == .waitForEmail)
    }
}

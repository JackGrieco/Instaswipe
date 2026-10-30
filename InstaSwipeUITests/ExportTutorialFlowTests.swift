import XCTest

final class ExportTutorialFlowTests: XCTestCase {
    private let waitTimeout: TimeInterval = 10

    /// No seed: the app starts without a state, on the tutorial.
    private func makeApp() -> XCUIApplication {
        let stateDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestStateDir", stateDir]
        return app
    }

    private func relaunch(_ app: XCUIApplication) {
        app.terminate()
        app.launch()
    }

    private func assertPhase(_ app: XCUIApplication, _ number: Int, file: StaticString = #filePath, line: UInt = #line) {
        let kicker = app.staticTexts["tutorialPhaseKicker"]
        XCTAssertTrue(kicker.waitForExistence(timeout: waitTimeout), "missing kicker", file: file, line: line)
        let predicate = NSPredicate(format: "label == %@", "FASE \(number) DI 4")
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: kicker)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: waitTimeout), .completed,
                       "kicker was '\(kicker.label)'", file: file, line: line)
    }

    private func tap(_ app: XCUIApplication, _ identifier: String) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: waitTimeout), "missing \(identifier)")
        button.tap()
    }

    /// Every tab has its own settings button; only the visible one opens the sheet.
    private func openSettings(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Impostazioni"].firstMatch.waitForExistence(timeout: waitTimeout))
        let visible = app.buttons.matching(identifier: "gearshape").allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(visible, "no visible settings button")
        visible?.tap()
        XCTAssertTrue(app.navigationBars["Impostazioni"].waitForExistence(timeout: waitTimeout))
    }

    @MainActor
    func testResumesFromImportAfterReachingTheWaitPhase() throws {
        let app = makeApp()
        app.launch()
        assertPhase(app, 1)

        tap(app, "tutorialNextButton")
        assertPhase(app, 2)
        tap(app, "tutorialNextButton")
        assertPhase(app, 3)

        relaunch(app)
        assertPhase(app, 4)
        XCTAssertTrue(app.buttons["Scegli cartella o file JSON"].waitForExistence(timeout: waitTimeout))

        // The link sits at the end of phase 4, under the bottom bar until the user scrolls.
        app.swipeUp()
        tap(app, "tutorialRestartButton")
        assertPhase(app, 1)
        relaunch(app)
        assertPhase(app, 1)
    }

    @MainActor
    func testBackFromWaitPhaseStillResumesAtImport() throws {
        let app = makeApp()
        app.launch()
        tap(app, "tutorialNextButton")
        tap(app, "tutorialNextButton")
        assertPhase(app, 3)

        tap(app, "tutorialBackButton")
        assertPhase(app, 2)
        tap(app, "tutorialBackButton")
        assertPhase(app, 1)

        relaunch(app)
        assertPhase(app, 4)
    }

    @MainActor
    func testSettingsTutorialResumesAtImport() throws {
        let app = makeApp()
        app.launchArguments.append("-uiTestSeed")
        app.launch()
        openSettings(app)
        tap(app, "Come esportare da Instagram")
        assertPhase(app, 1)
        tap(app, "tutorialNextButton")
        tap(app, "tutorialNextButton")
        assertPhase(app, 3)

        tap(app, "tutorialCloseButton")
        tap(app, "Come esportare da Instagram")
        assertPhase(app, 4)
    }
}

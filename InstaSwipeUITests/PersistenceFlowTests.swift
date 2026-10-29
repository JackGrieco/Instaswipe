import XCTest

final class PersistenceFlowTests: XCTestCase {
    private let waitTimeout: TimeInterval = 10

    private func makeApp() -> XCUIApplication {
        let stateDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestStateDir", stateDir, "-uiTestSeed"]
        return app
    }

    private func progress(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts["progressLabel"]
    }

    private func waitForLabel(_ element: XCUIElement, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: waitTimeout), "missing element", file: file, line: line)
        let predicate = NSPredicate(format: "label == %@", expected)
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: waitTimeout), .completed,
                       "label was '\(element.label)', expected '\(expected)'", file: file, line: line)
    }

    private func relaunch(_ app: XCUIApplication) {
        app.terminate()
        app.launch()
    }

    private func openRemovalList(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons["Da togliere"]
        XCTAssertTrue(tab.waitForExistence(timeout: waitTimeout))
        tab.tap()
    }

    private func assertTodayCounterHasOne(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let counter = app.staticTexts["todayCounter"]
        XCTAssertTrue(counter.waitForExistence(timeout: waitTimeout), file: file, line: line)
        XCTAssertTrue(counter.label.hasPrefix("Oggi: 1"), counter.label, file: file, line: line)
    }

    @MainActor
    func testDecisionsSurviveRelaunch() throws {
        let app = makeApp()
        app.launch()
        waitForLabel(progress(app), "0 / 5")

        app.buttons["removeButton"].tap()
        waitForLabel(progress(app), "1 / 5")
        app.buttons["keepButton"].tap()
        waitForLabel(progress(app), "2 / 5")

        relaunch(app)
        waitForLabel(progress(app), "2 / 5")
        waitForLabel(app.staticTexts["cardUsername"], "@test_03")

        openRemovalList(app)
        let toggle = app.buttons["doneToggle-test_01"]
        XCTAssertTrue(toggle.waitForExistence(timeout: waitTimeout))
        toggle.tap()
        assertTodayCounterHasOne(app)

        relaunch(app)
        openRemovalList(app)
        assertTodayCounterHasOne(app)
    }

    @MainActor
    func testUndoRestoresPreviousCard() throws {
        let app = makeApp()
        app.launch()
        waitForLabel(progress(app), "0 / 5")
        waitForLabel(app.staticTexts["cardUsername"], "@test_01")

        app.buttons["removeButton"].tap()
        waitForLabel(progress(app), "1 / 5")

        let undo = app.buttons["undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: waitTimeout))
        undo.tap()
        waitForLabel(progress(app), "0 / 5")
        waitForLabel(app.staticTexts["cardUsername"], "@test_01")
    }
}

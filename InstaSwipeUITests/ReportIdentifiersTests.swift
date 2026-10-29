import XCTest

final class ReportIdentifiersTests: XCTestCase {
    @MainActor
    func testDoneToggleIdentifierSurvivesAndCountsToday() throws {
        let stateDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestStateDir", stateDir, "-uiTestSeed"]
        app.launch()

        let remove = app.buttons["removeButton"]
        XCTAssertTrue(remove.waitForExistence(timeout: 10))
        remove.tap()
        app.tabBars.buttons["Da togliere"].tap()

        let toggle = app.buttons["doneToggle-test_01"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertTrue(toggle.isHittable)
        toggle.tap()

        let counter = app.staticTexts["todayCounter"]
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        XCTAssertTrue(counter.label.hasPrefix("Oggi: 1"), counter.label)
        XCTAssertEqual(app.state, .runningForeground)
    }
}

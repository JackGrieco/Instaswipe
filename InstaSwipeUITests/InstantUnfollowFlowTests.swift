import XCTest

final class InstantUnfollowFlowTests: XCTestCase {
    private static let retries = 5
    private static let settleTime: TimeInterval = 2

    @MainActor
    func testRemoveOpensTheProfileAndDoneMarksTheUnfollow() throws {
        let stateDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestStateDir", stateDir, "-uiTestSeed"]
        app.launch()

        let remove = app.buttons["removeButton"]
        XCTAssertTrue(remove.waitForExistence(timeout: 10))
        // Every tab has its own settings button; only the visible one opens the sheet.
        let settings = try XCTUnwrap(
            app.buttons.matching(identifier: "gearshape").allElementsBoundByIndex.first { $0.isHittable },
            "no visible settings button"
        )
        let toggle = app.switches["instantUnfollowToggle"]
        tap(settings, until: toggle.exists)
        tap(toggle.switches.firstMatch, until: toggle.value as? String == "1")
        tap(app.buttons["Fine"], until: !toggle.exists)

        let done = app.buttons["unfollowDoneButton"]
        tap(remove, until: done.exists)
        XCTAssertTrue(app.navigationBars["@test_01"].exists)
        add(XCTAttachment(screenshot: app.screenshot()))
        tap(done, until: !done.exists)

        let counter = app.staticTexts["todayCounter"]
        tap(app.tabBars.buttons["Da togliere"], until: counter.exists)
        XCTAssertTrue(counter.label.hasPrefix("Oggi: 1"), counter.label)
    }

    @MainActor
    func testCloseWithoutDoneBringsTheCardBack() throws {
        let stateDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestStateDir", stateDir, "-uiTestSeed"]
        app.launch()

        let remove = app.buttons["removeButton"]
        XCTAssertTrue(remove.waitForExistence(timeout: 10))
        let settings = try XCTUnwrap(
            app.buttons.matching(identifier: "gearshape").allElementsBoundByIndex.first { $0.isHittable },
            "no visible settings button"
        )
        let toggle = app.switches["instantUnfollowToggle"]
        tap(settings, until: toggle.exists)
        tap(toggle.switches.firstMatch, until: toggle.value as? String == "1")
        tap(app.buttons["Fine"], until: !toggle.exists)

        let done = app.buttons["unfollowDoneButton"]
        tap(remove, until: done.exists)
        let close = app.navigationBars["@test_01"].buttons["Chiudi"]
        tap(close, until: !done.exists)

        let username = app.staticTexts["cardUsername"]
        XCTAssertTrue(username.waitForExistence(timeout: 5))
        XCTAssertTrue(username.label.contains("test_01"), username.label)
    }

    /// Taps that land during a presentation animation are sometimes dropped: retry until `condition` holds.
    private func tap(
        _ element: XCUIElement,
        until condition: @autoclosure () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0..<Self.retries where !condition() {
            if element.waitForExistence(timeout: Self.settleTime), element.isHittable { element.tap() }
            let deadline = Date().addingTimeInterval(Self.settleTime)
            while !condition(), Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
        }
        XCTAssertTrue(condition(), "tapping \(element) never took effect", file: file, line: line)
    }
}

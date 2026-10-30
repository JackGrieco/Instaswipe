import XCTest

final class FollowersModeFlowTests: XCTestCase {
    private static let retries = 5
    private static let settleTime: TimeInterval = 2

    @MainActor
    func testSwitchToFollowersAndKeep() throws {
        let stateDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestStateDir", stateDir, "-uiTestSeed"]
        app.launch()

        let username = app.staticTexts["cardUsername"]
        XCTAssertTrue(username.waitForExistence(timeout: 10))
        let picker = app.segmentedControls["listModePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))

        tap(picker.buttons["Follower"], until: username.label.contains("fan_01"))

        tap(app.buttons["keepButton"], until: username.label.contains("fan_02"))

        tap(picker.buttons["Following"], until: username.label.contains("test_01"))
    }

    /// Taps that land during an animation are sometimes dropped: retry until `condition` holds.
    @MainActor
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

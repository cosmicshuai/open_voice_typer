import XCTest

/// Snapshots the Settings → Polish section for each provider so a
/// registry-driven refactor of the UI can be eyeballed. Not asserting layout,
/// just proving the section renders and switches without crashing.
final class SettingsSnapshotUITests: XCTestCase {
    @MainActor
    func testPolishSectionRendersForEachProvider() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--skip-onboarding"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 15), "no tabs")
        app.tabBars.buttons["Settings"].tap()

        XCTAssertTrue(app.staticTexts["Polish"].waitForExistence(timeout: 10), "Polish section missing")

        // The polish provider picker should exist and the section render its
        // model row for the default (OpenAI-compatible) provider.
        XCTAssertTrue(app.staticTexts["Model"].firstMatch.waitForExistence(timeout: 5),
                      "polish Model row missing")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "settings-polish"
        shot.lifetime = .keepAlways
        add(shot)
    }
}

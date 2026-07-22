import XCTest

/// Drives the real app through first-run onboarding and the tab bar.
final class OnboardingUITests: XCTestCase {
    @MainActor
    func testOnboardingFlowReachesTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-onboarding"]
        app.launch()

        // The onboarding is a paged TabView with animated transitions; tap
        // each page's button only once it's actually hittable, not merely
        // present in the (multi-page) accessibility tree.
        tapWhenReady(app.buttons["Get started"], page: "welcome")
        tapWhenReady(app.buttons["I'll do this later"], page: "keyboard")
        tapWhenReady(app.buttons["Allow microphone"], page: "microphone")

        // Mic permission is normally pre-granted via `simctl privacy`; if the
        // system dialog does appear, dismiss it deterministically.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "OK", "Allow While Using App"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 2) { button.tap(); break }
        }

        tapWhenReady(app.buttons["Start dictating"], page: "engine")

        // Landed in the app: all five tabs present.
        for tab in ["Dictate", "History", "Templates", "Dictionary", "Settings"] {
            XCTAssertTrue(
                app.tabBars.buttons[tab].waitForExistence(timeout: 10),
                "\(tab) tab missing after onboarding"
            )
        }

        // Tab navigation works and key screens render.
        tapWhenReady(app.tabBars.buttons["Templates"], page: "Templates tab")
        XCTAssertTrue(app.staticTexts["Raw"].waitForExistence(timeout: 10), "built-in templates not listed")

        tapWhenReady(app.tabBars.buttons["Settings"], page: "Settings tab")
        XCTAssertTrue(app.staticTexts["Speech to text"].waitForExistence(timeout: 10), "settings sections missing")

        tapWhenReady(app.tabBars.buttons["Dictate"], page: "Dictate tab")
        XCTAssertTrue(app.buttons["Start recording"].waitForExistence(timeout: 10), "dictation mic button missing")
    }

    /// Waits for an element to exist and settle into a hittable state before
    /// tapping — robust against paged-TabView transitions and tab animations.
    @MainActor
    private func tapWhenReady(
        _ element: XCUIElement,
        page: String,
        timeout: TimeInterval = 15,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(page) page/button missing", file: file, line: line)
        let deadline = Date().addingTimeInterval(5)
        while !element.isHittable && Date() < deadline {
            usleep(100_000)
        }
        element.tap()
    }

    @MainActor
    func testOnboardingDoesNotReappearOnRelaunch() throws {
        let app = XCUIApplication()
        app.launch() // no reset argument

        XCTAssertTrue(
            app.tabBars.buttons["Dictate"].waitForExistence(timeout: 10),
            "app should go straight to tabs once onboarding is done"
        )
        XCTAssertFalse(app.buttons["Get started"].exists, "onboarding reappeared")
    }
}

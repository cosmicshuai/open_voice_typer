import XCTest

/// Drives the real app through first-run onboarding and the tab bar.
final class OnboardingUITests: XCTestCase {
    @MainActor
    func testOnboardingFlowReachesTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-onboarding"]

        // Mic permission is normally pre-granted via `simctl privacy`; handle
        // the alert anyway in case it appears.
        addUIInterruptionMonitor(withDescription: "microphone permission") { alert in
            let allow = alert.buttons["Allow"].exists ? alert.buttons["Allow"] : alert.buttons["OK"]
            if allow.exists {
                allow.tap()
                return true
            }
            return false
        }

        app.launch()

        // Page 1: welcome
        let getStarted = app.buttons["Get started"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 10), "welcome page missing")
        getStarted.tap()

        // Page 2: keyboard setup — skip the Settings detour
        let later = app.buttons["I'll do this later"]
        XCTAssertTrue(later.waitForExistence(timeout: 5), "keyboard page missing")
        later.tap()

        // Page 3: microphone
        let allowMic = app.buttons["Allow microphone"]
        XCTAssertTrue(allowMic.waitForExistence(timeout: 5), "microphone page missing")
        allowMic.tap()
        app.tap() // nudge interruption monitor if the alert appeared

        // Page 4: engine choice, on-device preselected
        let start = app.buttons["Start dictating"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "engine page missing")
        start.tap()

        // Landed in the app: all five tabs present.
        for tab in ["Dictate", "History", "Templates", "Dictionary", "Settings"] {
            XCTAssertTrue(
                app.tabBars.buttons[tab].waitForExistence(timeout: 5),
                "\(tab) tab missing after onboarding"
            )
        }

        // Tab navigation works and key screens render.
        app.tabBars.buttons["Templates"].tap()
        XCTAssertTrue(app.staticTexts["Raw"].waitForExistence(timeout: 5), "built-in templates not listed")

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Speech to text"].waitForExistence(timeout: 5), "settings sections missing")

        app.tabBars.buttons["Dictate"].tap()
        // The session may have auto-started (mic pre-granted), so the card
        // shows either Start or End.
        XCTAssertTrue(app.staticTexts["Keyboard Session"].waitForExistence(timeout: 5), "session card missing")
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

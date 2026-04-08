//
//  AppSettingsUITests.swift
//  ArculatorUITests
//
//  Tests: App-wide Settings page — navigation from sidebar gear button,
//  dismissal via Back/Escape, content rows (support path, shortcut
//  recorder, about), and the pause-on-open behaviour when a session
//  is running.
//

import XCTest

final class AppSettingsUITests: ArculatorUITestCase {

    // MARK: - Helpers

    private var settingsPage: XCUIElement {
        app.otherElements["appSettingsPage"]
    }

    /// Open Settings from the idle sidebar and assert the page appears.
    private func openSettingsFromIdle() {
        _ = waitForIdle()

        let gear = app.buttons["configListAppSettingsButton"]
        XCTAssertTrue(
            gear.waitForExistence(timeout: 5),
            "Settings gear button should exist in the idle sidebar"
        )
        gear.click()

        XCTAssertTrue(
            settingsPage.waitForExistence(timeout: 5),
            "Settings page should appear after clicking the gear button"
        )
    }

    /// Wait for an element to disappear using the same NSPredicate pattern
    /// used by MutabilityGatingUITests.
    private func waitForDisappearance(
        of element: XCUIElement,
        timeout: TimeInterval = 5,
        message: String
    ) {
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: element, handler: nil)
        waitForExpectations(timeout: timeout) { error in
            if error != nil {
                XCTFail(message)
            }
        }
    }

    // MARK: - Navigation

    func testSettingsOpensFromIdleSidebar() throws {
        launchApp()
        openSettingsFromIdle()
    }

    func testSettingsClosesViaBackButton() throws {
        launchApp()
        openSettingsFromIdle()

        let back = app.buttons["appSettingsBackButton"]
        XCTAssertTrue(back.waitForExistence(timeout: 3), "Back button should exist on the settings page")
        back.click()

        waitForDisappearance(
            of: settingsPage,
            message: "Settings page should dismiss after clicking Back"
        )
    }

    func testSettingsClosesViaEscape() throws {
        launchApp()
        openSettingsFromIdle()

        // AppSettingsView uses .onExitCommand { onClose() } which maps to Escape.
        app.typeKey(.escape, modifierFlags: [])

        waitForDisappearance(
            of: settingsPage,
            message: "Settings page should dismiss when Escape is pressed"
        )
    }

    func testBackFromSettingsRestoresConfigEditor() throws {
        launchApp()
        selectFixtureConfig()

        let editor = app.otherElements["configEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))

        // Open settings — the editor should be hidden while the page is shown.
        let gear = app.buttons["configListAppSettingsButton"]
        XCTAssertTrue(gear.waitForExistence(timeout: 5))
        gear.click()

        XCTAssertTrue(settingsPage.waitForExistence(timeout: 5))

        // Back should restore the previously-shown config editor.
        app.buttons["appSettingsBackButton"].click()

        waitForDisappearance(
            of: settingsPage,
            message: "Settings page should dismiss after Back"
        )
        XCTAssertTrue(
            editor.waitForExistence(timeout: 5),
            "Config editor should be restored after dismissing settings"
        )
    }

    // MARK: - Running-state behaviour

    func testSettingsOpensFromRunningControlsAndPausesEmulation() throws {
        launchApp()
        selectFixtureConfigAndRun()
        waitForRunning(timeout: 10)
        waitForStatus("Running", timeout: 5)

        let gear = app.buttons["runningControlsAppSettingsButton"]
        XCTAssertTrue(
            gear.waitForExistence(timeout: 5),
            "Settings gear button should exist in the running-controls sidebar"
        )
        gear.click()

        XCTAssertTrue(
            settingsPage.waitForExistence(timeout: 5),
            "Settings page should appear when opened from running controls"
        )

        // navigateToAppSettings() pauses an active session as a side effect —
        // the status indicator in the running-controls sidebar should flip
        // from Running to Paused.
        waitForStatus("Paused", timeout: 5)
    }

    // MARK: - Content rendering

    func testSettingsPageShowsSupportPathRow() throws {
        launchApp()
        openSettingsFromIdle()

        let pathField = app.staticTexts["userDataLocationField"]
        XCTAssertTrue(
            pathField.waitForExistence(timeout: 3),
            "User data location path field should exist"
        )
        // The label text is the effectiveSupportPath — we don't pin it to an
        // exact value (UserDefaults state may vary across machines/runs) but
        // we can assert it's non-empty and points at something Arculator-ish.
        XCTAssertFalse(pathField.label.isEmpty, "Support path label should not be empty")
        XCTAssertTrue(
            pathField.label.contains("Arculator"),
            "Support path should contain 'Arculator' (got '\(pathField.label)')"
        )
    }

    func testSettingsPageShowsChangeAndRevealButtons() throws {
        launchApp()
        openSettingsFromIdle()

        XCTAssertTrue(
            app.buttons["chooseSupportPathButton"].waitForExistence(timeout: 3),
            "Change support path button should exist"
        )
        XCTAssertTrue(
            app.buttons["revealSupportPathButton"].exists,
            "Reveal in Finder button should exist"
        )
    }

    func testSettingsPageShowsShortcutRow() throws {
        launchApp()
        openSettingsFromIdle()

        // The shortcut recorder itself is a custom NSView and may not expose
        // itself as a standard XCUIElement. Assert instead that the labelled
        // row and its caption are both present — together they uniquely
        // identify the shortcut row.
        let label = app.staticTexts["Mouse release shortcut"]
        XCTAssertTrue(
            label.waitForExistence(timeout: 3),
            "Mouse release shortcut label should exist"
        )

        let captionPredicate = NSPredicate(
            format: "label CONTAINS 'Pressed inside the emulator window'"
        )
        let caption = app.staticTexts.element(matching: captionPredicate)
        XCTAssertTrue(
            caption.waitForExistence(timeout: 3),
            "Shortcut row caption should exist"
        )
    }

    func testSettingsPageShowsAboutSection() throws {
        launchApp()
        openSettingsFromIdle()

        let versionPill = app.staticTexts["aboutVersionPill"]
        XCTAssertTrue(
            versionPill.waitForExistence(timeout: 3),
            "About version pill should exist"
        )

        // The About row shows the app name too.
        XCTAssertTrue(
            app.staticTexts["Arculator"].exists,
            "About row should display the app name"
        )
    }

    // MARK: - Idempotence

    func testOpeningSettingsTwiceKeepsASinglePage() throws {
        launchApp()
        openSettingsFromIdle()

        // The only way to re-trigger showAppSettings while the page is up
        // would be through a menu item or keyboard shortcut — neither is
        // wired. Dismiss and re-open instead, and check the page still
        // has exactly one instance in the hierarchy each time.
        app.buttons["appSettingsBackButton"].click()
        waitForDisappearance(of: settingsPage, message: "Settings should dismiss")

        let gear = app.buttons["configListAppSettingsButton"]
        gear.click()
        XCTAssertTrue(settingsPage.waitForExistence(timeout: 5))

        let matches = app.otherElements.matching(identifier: "appSettingsPage")
        XCTAssertEqual(
            matches.count, 1,
            "There should be exactly one settings page in the hierarchy after reopening"
        )
    }
}

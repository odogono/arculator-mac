//
//  MenuToolbarSyncUITests.swift
//  ArculatorUITests
//
//  Tests: Menu items continue to function and stay in sync
//  with toolbar/sidebar state.
//

import XCTest

final class MenuToolbarSyncUITests: ArculatorUITestCase {

    func testToolbarRunEnabledWhenConfigSelected() throws {
        launchApp()
        _ = waitForIdle()

        let configRow = app.staticTexts["configRow_\(fixtureConfigName)"]
        XCTAssertTrue(configRow.waitForExistence(timeout: 5))
        configRow.click()

        let runButton = app.windows.firstMatch.toolbars.buttons["Run"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 5))
        XCTAssertTrue(runButton.isEnabled, "Run button should be enabled when a config is selected")
    }

    func testToolbarPauseDisabledWhenIdle() throws {
        launchApp()
        _ = waitForIdle()

        let pauseButton = app.windows.firstMatch.toolbars.buttons["Pause"]
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 5))
        XCTAssertFalse(pauseButton.isEnabled, "Pause button should be disabled when idle")
    }

    func testToolbarStopDisabledWhenIdle() throws {
        launchApp()
        _ = waitForIdle()

        let stopButton = app.windows.firstMatch.toolbars.buttons["Stop"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 5))
        XCTAssertFalse(stopButton.isEnabled, "Stop button should be disabled when idle")
    }

    func testMenuHardResetWorks() throws {
        launchApp()
        selectFixtureConfigAndRun()
        waitForRunning(timeout: 10)
        waitForStatus("Running", timeout: 5)

        clickMenuItem(menu: "File", item: "Hard Reset")

        // Verify still running after reset
        let runningControls = app.otherElements["runningControls"]
        XCTAssertTrue(
            runningControls.waitForExistence(timeout: 5),
            "Should remain in running state after Hard Reset"
        )
    }

    func testMenuFullscreen() throws {
        launchApp()
        _ = waitForIdle()

        let window = app.windows.firstMatch
        let initialFrame = window.frame

        clickToolbarButton("Fullscreen")

        // Wait for fullscreen animation to complete
        let expanded = NSPredicate { _, _ in window.frame.width > initialFrame.width }
        expectation(for: expanded, evaluatedWith: nil, handler: nil)
        waitForExpectations(timeout: 5, handler: nil)

        // Exit fullscreen
        window.typeKey(.delete, modifierFlags: .command)

        // Wait for windowed mode to restore
        let restored = NSPredicate { _, _ in window.frame.width <= initialFrame.width + 1 }
        expectation(for: restored, evaluatedWith: nil, handler: nil)
        waitForExpectations(timeout: 5, handler: nil)
    }
}

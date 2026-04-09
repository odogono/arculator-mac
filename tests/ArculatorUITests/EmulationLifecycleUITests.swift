//
//  EmulationLifecycleUITests.swift
//  ArculatorUITests
//
//  Tests: Run → running sidebar, Pause → settings editable,
//  Stop → return to idle shell without modal restart prompt.
//

import XCTest

final class EmulationLifecycleUITests: ArculatorUITestCase {

    func testRunTransition() throws {
        launchApp()
        selectFixtureConfigAndRun()

        waitForRunning(timeout: 10)
        waitForStatus("Running", timeout: 5)

        let configName = identifiedElement("activeConfigName")
        XCTAssertTrue(configName.exists)
        XCTAssertEqual(textValue(of: configName), fixtureConfigName)
    }

    func testPauseTransition() throws {
        launchApp()
        selectFixtureConfigAndRun()
        waitForRunning(timeout: 10)
        waitForStatus("Running", timeout: 5)

        clickToolbarButton("Pause")
        waitForStatus("Paused", timeout: 5)

        let runningControls = identifiedElement("runningControls")
        XCTAssertTrue(runningControls.exists, "Running controls should remain visible when paused")
    }

    func testResumeFromPause() throws {
        launchApp()
        selectFixtureConfigAndRun()
        waitForRunning(timeout: 10)
        waitForStatus("Running", timeout: 5)

        clickToolbarButton("Pause")
        waitForStatus("Paused", timeout: 5)

        clickToolbarButton("Run")
        waitForStatus("Running", timeout: 5)
    }

    func testStopReturnsToIdle() throws {
        launchApp()
        selectFixtureConfigAndRun()
        waitForRunning(timeout: 10)

        clickToolbarButton("Stop")

        _ = waitForIdle(timeout: 10)

        XCTAssertEqual(app.sheets.count, 0, "No modal sheets should appear after stopping")
        XCTAssertEqual(app.alerts.count, 0, "No modal alerts should appear after stopping")
    }
}

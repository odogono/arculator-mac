//
//  PreselectedConfigUITests.swift
//  ArculatorUITests
//
//  Tests: Preselected config behavior when launched with a config argv.
//

import XCTest

final class PreselectedConfigUITests: ArculatorUITestCase {

    override var preselectedConfigName: String? { fixtureConfigName }

    func testPreselectedConfigAutoRuns() throws {
        launchApp()

        waitForRunning(timeout: 15)

        let configName = app.staticTexts["activeConfigName"]
        XCTAssertTrue(configName.waitForExistence(timeout: 5))
        XCTAssertEqual(configName.label, fixtureConfigName)

        waitForStatus("Running", timeout: 5)
    }
}

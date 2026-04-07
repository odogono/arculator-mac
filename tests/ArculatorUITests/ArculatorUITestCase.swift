//
//  ArculatorUITestCase.swift
//  ArculatorUITests
//
//  Base test case for Arculator XCUITests. Creates a temporary support
//  directory with test fixtures and passes it to the app via launch args.
//

import XCTest

/// Default fixture config name used by tests.
let fixtureConfigName = "Test Machine"

class ArculatorUITestCase: XCTestCase {

    var app: XCUIApplication!
    private var tempSupportDir: URL!

    /// Override in subclass to specify a config name to preselect at launch.
    var preselectedConfigName: String? { nil }

    // MARK: - Setup / Teardown

    override func setUpWithError() throws {
        continueAfterFailure = false

        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArculatorUITest-\(UUID().uuidString)")
        tempSupportDir = tempBase

        let fixturesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures")

        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)

        let fixtureConfigs = fixturesDir.appendingPathComponent("configs")
        let destConfigs = tempBase.appendingPathComponent("configs")
        if FileManager.default.fileExists(atPath: fixtureConfigs.path) {
            try FileManager.default.copyItem(at: fixtureConfigs, to: destConfigs)
        } else {
            try FileManager.default.createDirectory(at: destConfigs, withIntermediateDirectories: true)
        }

        let fixtureGlobalCfg = fixturesDir.appendingPathComponent("arc.cfg")
        if FileManager.default.fileExists(atPath: fixtureGlobalCfg.path) {
            try FileManager.default.copyItem(
                at: fixtureGlobalCfg,
                to: tempBase.appendingPathComponent("arc.cfg")
            )
        }

        app = XCUIApplication()
        app.launchArguments += ["-ArculatorTestSupportPath", tempBase.path]

        if let configName = preselectedConfigName {
            app.launchArguments += ["-ArculatorTestConfig", configName]
        }
    }

    override func tearDownWithError() throws {
        if let dir = tempSupportDir {
            try? FileManager.default.removeItem(at: dir)
        }
        app = nil
        tempSupportDir = nil
    }

    // MARK: - Helpers

    func launchApp() {
        app.launch()
    }

    /// Wait for the sidebar to show idle content (config list or empty state).
    @discardableResult
    func waitForIdle(timeout: TimeInterval = 10) -> XCUIElement {
        // SwiftUI List renders as outline or table depending on context;
        // check all three possibilities with a single polling loop.
        let candidates = [
            app.outlines["configList"],
            app.tables["configList"],
            app.otherElements["configListEmpty"]
        ]
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if let found = candidates.first(where: { $0.exists }) {
                return found
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
        }
        XCTFail("Timed out waiting for idle state (config list or empty state)")
        return candidates[0]
    }

    @discardableResult
    func waitForRunning(timeout: TimeInterval = 10) -> XCUIElement {
        let element = app.otherElements["runningControls"]
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Running controls should appear")
        return element
    }

    func waitForStatus(_ status: String, timeout: TimeInterval = 10) {
        let statusText = app.staticTexts["emulatorStatus"]
        let predicate = NSPredicate(format: "label == %@", status)
        expectation(for: predicate, evaluatedWith: statusText, handler: nil)
        waitForExpectations(timeout: timeout, handler: nil)
    }

    @discardableResult
    func waitForIdlePlaceholder(timeout: TimeInterval = 10) -> XCUIElement {
        let element = app.otherElements["idlePlaceholder"]
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Idle placeholder should appear")
        return element
    }

    func clickToolbarButton(_ label: String) {
        let button = app.windows.firstMatch.toolbars.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Toolbar button '\(label)' should exist")
        button.click()
    }

    func clickMenuItem(menu menuTitle: String, item itemTitle: String) {
        let menuBar = app.menuBars.firstMatch
        menuBar.menuBarItems[menuTitle].click()
        menuBar.menuItems[itemTitle].click()
    }

    /// Select the fixture config and start emulation via toolbar.
    func selectFixtureConfigAndRun() {
        _ = waitForIdle()

        let configRow = app.staticTexts["configRow_\(fixtureConfigName)"]
        XCTAssertTrue(configRow.waitForExistence(timeout: 5), "Fixture config should exist")
        configRow.click()

        _ = app.otherElements["configEditor"].waitForExistence(timeout: 3)
        clickToolbarButton("Run")
    }

    var supportPath: String { tempSupportDir.path }
}

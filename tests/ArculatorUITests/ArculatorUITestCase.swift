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

        // Avoid the runner's container tmp/cache directories. RunningBoard can
        // reap the xctrunner while cache cleanup is in flight, which shows up
        // as a spurious "signal kill" during longer UI interactions.
        let testRoot = try FileManager.default
            .url(for: .applicationSupportDirectory,
                 in: .userDomainMask,
                 appropriateFor: nil,
                 create: true)
            .appendingPathComponent("ArculatorUITests", isDirectory: true)
        let tempBase = testRoot.appendingPathComponent("ArculatorUITest-\(UUID().uuidString)")
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
        let element = identifiedElement("runningControls")
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Running controls should appear")
        return element
    }

    func waitForStatus(_ status: String, timeout: TimeInterval = 10) {
        let statusText = identifiedElement("emulatorStatus")
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if textValue(of: statusText) == status {
                return
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
        }
        XCTFail("Timed out waiting for emulator status '\(status)'")
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

    func identifiedElement(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func textValue(of element: XCUIElement) -> String? {
        if let value = element.value as? String, !value.isEmpty {
            return value
        }
        let label = element.label
        return label.isEmpty ? nil : label
    }

    /// Select the fixture config and wait for the config editor to appear.
    func selectFixtureConfig() {
        _ = waitForIdle()

        let configRow = app.staticTexts["configRow_\(fixtureConfigName)"]
        XCTAssertTrue(configRow.waitForExistence(timeout: 5), "Fixture config should exist")
        configRow.click()

        let editor = app.groups["configEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "Config editor should appear")
    }

    /// Select the fixture config and start emulation via toolbar.
    func selectFixtureConfigAndRun() {
        selectFixtureConfig()
        clickToolbarButton("Run")
    }

    var supportPath: String { tempSupportDir.path }

    /// Remove all config files from the fixture configs directory.
    func removeAllFixtureConfigs() {
        let configsDir = URL(fileURLWithPath: supportPath)
            .appendingPathComponent("configs")
        if let files = try? FileManager.default.contentsOfDirectory(atPath: configsDir.path) {
            for file in files {
                try? FileManager.default.removeItem(
                    at: configsDir.appendingPathComponent(file)
                )
            }
        }
    }

    func waitForFile(atPath path: String, timeout: TimeInterval = 10) {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if FileManager.default.fileExists(atPath: path) {
                return
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
        }
        XCTFail("Timed out waiting for file at \(path)")
    }
}

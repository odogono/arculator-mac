//
//  LaunchIdleUITests.swift
//  ArculatorUITests
//
//  Tests: Launch to idle shell with config list and editor visible.
//

import XCTest

final class LaunchIdleUITests: ArculatorUITestCase {

    func testLaunchShowsConfigListAndPlaceholder() throws {
        launchApp()

        _ = waitForIdle()

        // Content area shows placeholder or editor (auto-selection may occur)
        let placeholder = app.otherElements["idlePlaceholder"]
        let editor = app.otherElements["configEditor"]
        XCTAssertTrue(
            placeholder.waitForExistence(timeout: 5) || editor.exists,
            "Content area should show idle placeholder or config editor"
        )
    }

    func testSelectConfigShowsEditor() throws {
        launchApp()
        _ = waitForIdle()

        let configRow = app.staticTexts["configRow_\(fixtureConfigName)"]
        if configRow.waitForExistence(timeout: 5) {
            configRow.click()

            let editor = app.otherElements["configEditor"]
            XCTAssertTrue(
                editor.waitForExistence(timeout: 5),
                "Config editor should appear after selecting a config"
            )
        } else {
            // Config may have been auto-selected
            let editor = app.otherElements["configEditor"]
            XCTAssertTrue(editor.exists, "Config editor should be visible")
        }
    }

    func testEmptyConfigListShowsEmptyState() throws {
        let configsDir = URL(fileURLWithPath: supportPath)
            .appendingPathComponent("configs")
        if let files = try? FileManager.default.contentsOfDirectory(atPath: configsDir.path) {
            for file in files {
                try? FileManager.default.removeItem(
                    at: configsDir.appendingPathComponent(file)
                )
            }
        }

        launchApp()

        let emptyState = app.otherElements["configListEmpty"]
        XCTAssertTrue(
            emptyState.waitForExistence(timeout: 10),
            "Empty config list state should be shown when no configs exist"
        )
    }
}

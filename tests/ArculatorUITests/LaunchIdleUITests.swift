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

    func testFirstRunWelcomeAppears() throws {
        removeAllFixtureConfigs()
        launchApp()

        let welcome = app.otherElements["firstRunWelcome"]
        XCTAssertTrue(
            welcome.waitForExistence(timeout: 10),
            "First-run welcome view should appear when no configs exist"
        )

        let createButton = app.buttons["createFirstMachineButton"]
        XCTAssertTrue(
            createButton.waitForExistence(timeout: 5),
            "Create Your First Machine button should be visible"
        )
    }

    func testFirstRunCreateConfigFromWelcome() throws {
        removeAllFixtureConfigs()
        launchApp()

        let createButton = app.buttons["createFirstMachineButton"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 10))
        createButton.click()

        let popoverCreate = app.buttons["Create"]
        XCTAssertTrue(
            popoverCreate.waitForExistence(timeout: 5),
            "New config popover should appear with Create button"
        )

        // Popover pre-fills a config name from the selected preset;
        // replace it with a known name for verification.
        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.click()
        nameField.typeKey("a", modifierFlags: .command)
        nameField.typeText("Welcome Config")

        popoverCreate.click()

        let newRow = app.staticTexts["configRow_Welcome Config"]
        XCTAssertTrue(
            newRow.waitForExistence(timeout: 5),
            "Config created from welcome should appear in the list"
        )
    }

    func testEmptyConfigListShowsEmptyState() throws {
        removeAllFixtureConfigs()
        launchApp()

        let emptyState = app.otherElements["configListEmpty"]
        XCTAssertTrue(
            emptyState.waitForExistence(timeout: 10),
            "Empty config list state should be shown when no configs exist"
        )
    }
}

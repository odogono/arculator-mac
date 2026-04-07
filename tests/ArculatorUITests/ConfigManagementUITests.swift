//
//  ConfigManagementUITests.swift
//  ArculatorUITests
//
//  Tests: Config CRUD operations — replaces macos_session1_check.applescript.
//

import XCTest

final class ConfigManagementUITests: ArculatorUITestCase {

    func testCreateConfig() throws {
        launchApp()
        _ = waitForIdle()

        let addButton = app.buttons["addConfigButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "Add config button should exist")
        addButton.click()

        let createButton = app.buttons["Create"]
        XCTAssertTrue(
            createButton.waitForExistence(timeout: 5),
            "New config popover should appear with Create button"
        )

        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.click()
        nameField.typeKey("a", modifierFlags: .command)
        nameField.typeText("My New Config")

        createButton.click()

        let newRow = app.staticTexts["configRow_My New Config"]
        XCTAssertTrue(
            newRow.waitForExistence(timeout: 5),
            "Newly created config should appear in the list"
        )
    }

    func testDeleteConfig() throws {
        launchApp()
        _ = waitForIdle()

        let configRow = app.staticTexts["configRow_\(fixtureConfigName)"]
        XCTAssertTrue(configRow.waitForExistence(timeout: 5))
        configRow.rightClick()

        let deleteItem = app.menuItems["Delete..."]
        XCTAssertTrue(
            deleteItem.waitForExistence(timeout: 3),
            "Context menu should have Delete option"
        )
        deleteItem.click()

        let deleteButton = app.buttons["Delete"]
        XCTAssertTrue(
            deleteButton.waitForExistence(timeout: 5),
            "Delete confirmation alert should appear"
        )
        deleteButton.click()

        let deletedRow = app.staticTexts["configRow_\(fixtureConfigName)"]
        XCTAssertFalse(
            deletedRow.waitForExistence(timeout: 2),
            "Deleted config should no longer appear in list"
        )
    }
}

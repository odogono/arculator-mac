//
//  ConfigManagementUITests.swift
//  ArculatorUITests
//
//  Tests: Config CRUD operations — replaces macos_session1_check.applescript.
//

import XCTest

final class ConfigManagementUITests: ArculatorUITestCase {

    // MARK: - Helpers

    private func selectContextMenuItem(_ itemTitle: String, onConfig configName: String) {
        let configRow = app.staticTexts["configRow_\(configName)"]
        XCTAssertTrue(configRow.waitForExistence(timeout: 5))
        configRow.rightClick()

        let menuItem = app.menuItems[itemTitle]
        XCTAssertTrue(
            menuItem.waitForExistence(timeout: 3),
            "Context menu should have '\(itemTitle)' option"
        )
        menuItem.click()
    }

    @discardableResult
    private func renameConfig(_ configName: String, to newName: String) -> XCUIElement {
        selectContextMenuItem("Rename...", onConfig: configName)

        let renameButton = app.buttons["Rename"]
        XCTAssertTrue(renameButton.waitForExistence(timeout: 5), "Rename alert should appear")

        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.click()
        nameField.typeKey("a", modifierFlags: .command)
        nameField.typeText(newName)
        renameButton.click()

        let renamedRow = app.staticTexts["configRow_\(newName)"]
        XCTAssertTrue(
            renamedRow.waitForExistence(timeout: 5),
            "Renamed config should appear in the list"
        )
        return renamedRow
    }

    @discardableResult
    private func duplicateConfig(_ configName: String) -> XCUIElement {
        selectContextMenuItem("Duplicate...", onConfig: configName)

        let duplicateButton = app.buttons["Duplicate"]
        XCTAssertTrue(
            duplicateButton.waitForExistence(timeout: 5),
            "Duplicate alert should appear"
        )
        duplicateButton.click()

        let copyRow = app.staticTexts["configRow_\(configName) Copy"]
        XCTAssertTrue(
            copyRow.waitForExistence(timeout: 5),
            "Duplicated config should appear in the list"
        )
        return copyRow
    }

    // MARK: - Create

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

    // MARK: - Rename

    func testRenameConfig() throws {
        launchApp()
        _ = waitForIdle()

        renameConfig(fixtureConfigName, to: "Renamed Machine")

        let oldRow = app.staticTexts["configRow_\(fixtureConfigName)"]
        XCTAssertFalse(
            oldRow.waitForExistence(timeout: 2),
            "Original config name should no longer appear"
        )
    }

    func testRenameConfigPersistsAcrossRelaunch() throws {
        launchApp()
        _ = waitForIdle()

        renameConfig(fixtureConfigName, to: "Persistent Rename")

        app.terminate()
        launchApp()
        _ = waitForIdle()

        let survivedRow = app.staticTexts["configRow_Persistent Rename"]
        XCTAssertTrue(
            survivedRow.waitForExistence(timeout: 10),
            "Renamed config should persist across relaunch"
        )
    }

    // MARK: - Duplicate

    func testDuplicateConfig() throws {
        launchApp()
        _ = waitForIdle()

        duplicateConfig(fixtureConfigName)

        let originalRow = app.staticTexts["configRow_\(fixtureConfigName)"]
        XCTAssertTrue(originalRow.exists, "Original config should still exist")
    }

    func testDuplicateConfigPersistsAcrossRelaunch() throws {
        launchApp()
        _ = waitForIdle()

        duplicateConfig(fixtureConfigName)

        app.terminate()
        launchApp()
        _ = waitForIdle()

        let survivedCopy = app.staticTexts["configRow_\(fixtureConfigName) Copy"]
        XCTAssertTrue(
            survivedCopy.waitForExistence(timeout: 10),
            "Duplicated config should persist across relaunch"
        )

        let survivedOriginal = app.staticTexts["configRow_\(fixtureConfigName)"]
        XCTAssertTrue(
            survivedOriginal.waitForExistence(timeout: 5),
            "Original config should still exist after relaunch"
        )
    }

    // MARK: - Delete

    func testDeleteConfig() throws {
        launchApp()
        _ = waitForIdle()

        selectContextMenuItem("Delete...", onConfig: fixtureConfigName)

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

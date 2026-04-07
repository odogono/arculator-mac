//
//  ConfigEditorTabUITests.swift
//  ArculatorUITests
//
//  Tests: Config editor category tab navigation (General, Storage,
//  Peripherals, Display) selection and content switching.
//

import XCTest

final class ConfigEditorTabUITests: ArculatorUITestCase {

    private let allCategories = ["General", "Storage", "Peripherals", "Display"]

    // MARK: - Helpers

    private func openConfigEditor() {
        launchApp()
        selectFixtureConfig()
    }

    private func switchToTabAndVerify(_ category: String) {
        let tab = app.staticTexts["categoryTab_\(category)"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "\(category) tab should exist")
        tab.click()

        let detail = app.scrollViews["settingsDetail_\(category)"]
        XCTAssertTrue(
            detail.waitForExistence(timeout: 5),
            "\(category) detail content should appear after clicking \(category) tab"
        )
    }

    // MARK: - Tests

    func testGeneralSelectedByDefault() throws {
        openConfigEditor()

        let generalDetail = app.scrollViews["settingsDetail_General"]
        XCTAssertTrue(
            generalDetail.waitForExistence(timeout: 5),
            "General settings should be visible by default"
        )
    }

    func testSwitchToStorageTab() throws {
        openConfigEditor()
        switchToTabAndVerify("Storage")
    }

    func testSwitchToPeripheralsTab() throws {
        openConfigEditor()
        switchToTabAndVerify("Peripherals")
    }

    func testSwitchToDisplayTab() throws {
        openConfigEditor()
        switchToTabAndVerify("Display")
    }

    func testSwitchBackToGeneralTab() throws {
        openConfigEditor()
        switchToTabAndVerify("Storage")
        switchToTabAndVerify("General")
    }
}

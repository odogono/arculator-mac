//
//  MutabilityGatingUITests.swift
//  ArculatorUITests
//
//  Tests: Mutability gating while emulation is active, and the
//  pending-reset banner with "Apply and Reset" flow.
//

import XCTest

final class MutabilityGatingUITests: ArculatorUITestCase {

    // MARK: - Helpers

    /// Opens the config editor while emulation is active, changes the CPU
    /// picker to trigger a pending-reset banner, and returns the banner element.
    private func triggerPendingResetBanner() -> XCUIElement {
        selectFixtureConfigAndRun()
        _ = waitForRunning()

        clickMenuItem(menu: "Settings", item: "Configure Machine...")

        let editor = app.otherElements["configEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "Config editor should appear")

        let cpuPicker = app.popUpButtons["CPU"]
        XCTAssertTrue(cpuPicker.waitForExistence(timeout: 5), "CPU picker should be visible")
        XCTAssertTrue(cpuPicker.isEnabled, "CPU picker should be enabled (reset mutability)")

        cpuPicker.click()
        let menuItem = app.menuItems.element(boundBy: 1)
        if menuItem.waitForExistence(timeout: 3) {
            menuItem.click()
        }

        return app.otherElements["pendingResetBanner"]
    }

    // MARK: - Gating State

    func testStopMutabilitySettingDisabledWhileRunning() throws {
        launchApp()
        selectFixtureConfigAndRun()
        _ = waitForRunning()

        clickMenuItem(menu: "Settings", item: "Configure Machine...")

        let editor = app.otherElements["configEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "Config editor should appear")

        // Preset has .stop mutability — disabled while active.
        let presetPicker = app.popUpButtons["Preset"]
        XCTAssertTrue(
            presetPicker.waitForExistence(timeout: 5),
            "Preset picker should be visible in editor"
        )
        XCTAssertFalse(presetPicker.isEnabled, "Preset picker should be disabled while running")

        let hints = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'mutabilityHint_'"))
        XCTAssertGreaterThan(hints.count, 0, "Mutability hint should appear for disabled setting")
    }

    func testStopMutabilitySettingEnabledWhenIdle() throws {
        launchApp()
        _ = waitForIdle()

        let configRow = app.staticTexts["configRow_\(fixtureConfigName)"]
        XCTAssertTrue(configRow.waitForExistence(timeout: 5))
        configRow.click()

        let editor = app.otherElements["configEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))

        let presetPicker = app.popUpButtons["Preset"]
        XCTAssertTrue(
            presetPicker.waitForExistence(timeout: 5),
            "Preset picker should be visible"
        )
        XCTAssertTrue(presetPicker.isEnabled, "Preset picker should be enabled when idle")
    }

    // MARK: - Pending Reset Banner

    func testPendingResetBannerAppearsOnChange() throws {
        launchApp()
        let banner = triggerPendingResetBanner()
        XCTAssertTrue(
            banner.waitForExistence(timeout: 5),
            "Pending reset banner should appear after changing a reset-requiring setting"
        )
    }

    func testApplyAndResetDismissesBanner() throws {
        launchApp()
        let banner = triggerPendingResetBanner()
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "Banner should appear")

        let applyButton = app.buttons["applyAndResetButton"]
        XCTAssertTrue(
            applyButton.waitForExistence(timeout: 3),
            "Apply and Reset button should exist"
        )
        applyButton.click()

        let bannerGone = NSPredicate(format: "exists == false")
        expectation(for: bannerGone, evaluatedWith: banner, handler: nil)
        waitForExpectations(timeout: 5, handler: nil)
    }
}

//
//  DiscSlotUITests.swift
//  ArculatorUITests
//
//  Tests: Disc slot visibility and eject button state while running.
//  File-picker-based attach and drag-and-drop are not tested here
//  because XCUITest cannot reliably interact with NSOpenPanel.
//

import XCTest

final class DiscSlotUITests: ArculatorUITestCase {

    func testDiscSlotsVisibleWhileRunning() throws {
        launchApp()
        selectFixtureConfigAndRun()
        _ = waitForRunning()

        let slot0 = app.otherElements["discSlot_0"]
        let slot1 = app.otherElements["discSlot_1"]

        XCTAssertTrue(
            slot0.waitForExistence(timeout: 5),
            "Drive 0 disc slot should be visible while running"
        )
        XCTAssertTrue(
            slot1.waitForExistence(timeout: 5),
            "Drive 1 disc slot should be visible while running"
        )
    }

    func testEjectButtonDisabledWhenEmpty() throws {
        launchApp()
        selectFixtureConfigAndRun()
        _ = waitForRunning()

        let ejectButton = app.buttons["discEjectButton_0"]
        XCTAssertTrue(
            ejectButton.waitForExistence(timeout: 5),
            "Eject button should exist for drive 0"
        )
        XCTAssertFalse(
            ejectButton.isEnabled,
            "Eject button should be disabled when no disc is loaded"
        )
    }
}

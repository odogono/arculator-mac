//
//  SnapshotMenuUITests.swift
//  ArculatorUITests
//
//  Tests: File menu gating for the Save Snapshot… and Load Snapshot…
//  items across the three session states the UI cares about.
//
//  Gating rules (see shell_update_menu_state in src/macos/app_macos.mm):
//    - Idle    → Save disabled, Load enabled
//    - Running → Save disabled (must be paused), Load disabled
//    - Paused  → Save enabled (if snapshot_can_save OKs it), Load disabled
//

import XCTest

final class SnapshotMenuUITests: ArculatorUITestCase {

    // MARK: - Helpers

    /// Reach into the File menu and return the menu items for Save
    /// Snapshot… and Load Snapshot… without actually clicking them.
    /// Opens the menu, captures state, then dismisses the menu.
    private func snapshotMenuState() -> (saveEnabled: Bool, loadEnabled: Bool) {
        let menuBar = app.menuBars.firstMatch
        let fileMenu = menuBar.menuBarItems["File"]
        XCTAssertTrue(fileMenu.waitForExistence(timeout: 5), "File menu should exist")
        fileMenu.click()

        // Menu item titles use a horizontal-ellipsis character — match on
        // "Save Snapshot" / "Load Snapshot" prefixes via predicate so the
        // test is robust to the exact punctuation.
        let savePredicate = NSPredicate(format: "title BEGINSWITH 'Save Snapshot'")
        let loadPredicate = NSPredicate(format: "title BEGINSWITH 'Load Snapshot'")

        let saveItem = menuBar.menuItems.element(matching: savePredicate)
        let loadItem = menuBar.menuItems.element(matching: loadPredicate)

        XCTAssertTrue(saveItem.waitForExistence(timeout: 3), "Save Snapshot menu item should exist")
        XCTAssertTrue(loadItem.waitForExistence(timeout: 3), "Load Snapshot menu item should exist")

        let saveEnabled = saveItem.isEnabled
        let loadEnabled = loadItem.isEnabled

        // Dismiss the menu so subsequent interactions aren't blocked.
        app.typeKey(.escape, modifierFlags: [])

        return (saveEnabled, loadEnabled)
    }

    // MARK: - Tests

    func testIdleSessionAllowsLoadBlocksSave() throws {
        launchApp()
        _ = waitForIdle()

        let state = snapshotMenuState()
        XCTAssertFalse(
            state.saveEnabled,
            "Save Snapshot should be disabled with no running session"
        )
        XCTAssertTrue(
            state.loadEnabled,
            "Load Snapshot should be enabled when the session is idle"
        )
    }

    func testRunningSessionBlocksBothSnapshotItems() throws {
        launchApp()
        selectFixtureConfigAndRun()
        waitForRunning(timeout: 10)
        waitForStatus("Running", timeout: 5)

        let state = snapshotMenuState()
        XCTAssertFalse(
            state.saveEnabled,
            "Save Snapshot should be disabled while the emulation is running (pause required)"
        )
        XCTAssertFalse(
            state.loadEnabled,
            "Load Snapshot should be disabled while a session is active"
        )
    }

    func testPausedSessionAllowsSaveBlocksLoad() throws {
        launchApp()
        selectFixtureConfigAndRun()
        waitForRunning(timeout: 10)
        waitForStatus("Running", timeout: 5)

        clickToolbarButton("Pause")
        waitForStatus("Paused", timeout: 5)

        let state = snapshotMenuState()
        XCTAssertTrue(
            state.saveEnabled,
            "Save Snapshot should be enabled once the session is paused on a floppy-only config"
        )
        XCTAssertFalse(
            state.loadEnabled,
            "Load Snapshot should remain disabled while a session is active"
        )
    }
}

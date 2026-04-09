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

    private func clickFileMenuItem(prefix: String) {
        let menuBar = app.menuBars.firstMatch
        let fileMenu = menuBar.menuBarItems["File"]
        XCTAssertTrue(fileMenu.waitForExistence(timeout: 5), "File menu should exist")
        fileMenu.click()

        let predicate = NSPredicate(format: "title BEGINSWITH %@", prefix)
        let item = menuBar.menuItems.element(matching: predicate)
        XCTAssertTrue(item.waitForExistence(timeout: 3), "File menu item '\(prefix)' should exist")
        item.click()
    }

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

    private func waitForSaveSnapshotEnabled(timeout: TimeInterval = 15) {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if snapshotMenuState().saveEnabled {
                return
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
        }
        XCTFail("Timed out waiting for Save Snapshot to become enabled")
    }

    private func openRecentSnapshotsMenu() {
        let menuBar = app.menuBars.firstMatch
        let fileMenu = menuBar.menuBarItems["File"]
        XCTAssertTrue(fileMenu.waitForExistence(timeout: 5), "File menu should exist")
        fileMenu.click()

        let recentItem = menuBar.menuItems["Open Recent Snapshot"]
        XCTAssertTrue(
            recentItem.waitForExistence(timeout: 3),
            "Open Recent Snapshot submenu should exist"
        )
        recentItem.click()
    }

    private func waitForRecentSnapshotMenuItem(
        titled title: String,
        timeout: TimeInterval = 5
    ) -> Bool {
        let debugValue = identifiedElement("recentSnapshotsDebugValue")
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            let value = textValue(of: debugValue) ?? ""
            if value
                .split(separator: "\n")
                .contains(where: { URL(fileURLWithPath: String($0)).lastPathComponent == title }) {
                return true
            }

            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
        }
        return false
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

    func testPausedSaveShowsSnapshotInBrowserAndRecentMenuOnceIdle() throws {
        let snapshotPath = URL(fileURLWithPath: supportPath)
            .appendingPathComponent("snapshots")
            .appendingPathComponent("paused-save-ui-test.arcsnap")

        app.launchArguments += ["-ArculatorTestSaveSnapshotPath", snapshotPath.path]
        launchApp()
        selectFixtureConfigAndRun()
        waitForRunning(timeout: 10)
        waitForStatus("Running", timeout: 5)

        clickToolbarButton("Pause")
        waitForStatus("Paused", timeout: 5)
        waitForSaveSnapshotEnabled()

        clickFileMenuItem(prefix: "Save Snapshot")
        waitForFile(atPath: snapshotPath.path, timeout: 15)

        clickToolbarButton("Stop")
        _ = waitForIdle(timeout: 10)

        clickFileMenuItem(prefix: "Load Snapshot")
        let browser = identifiedElement("snapshotBrowserPage")
        XCTAssertTrue(
            browser.waitForExistence(timeout: 5),
            "Load Snapshot should open the snapshot browser after returning to idle"
        )
        let snapshotRow = identifiedElement("snapshotBrowserRow")
        XCTAssertTrue(
            snapshotRow.waitForExistence(timeout: 5),
            "The saved snapshot should appear in the snapshot browser"
        )
        app.typeKey(.escape, modifierFlags: [])

        openRecentSnapshotsMenu()
        XCTAssertTrue(
            waitForRecentSnapshotMenuItem(titled: snapshotPath.lastPathComponent),
            "The saved snapshot should appear in Open Recent Snapshot"
        )
        app.typeKey(.escape, modifierFlags: [])
    }
}

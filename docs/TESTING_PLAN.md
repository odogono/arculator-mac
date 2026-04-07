# Testing Plan for Arculator macOS UI Redesign

Last updated: 2026-04-05

## Summary

The previous version of this plan is now partly obsolete.

Roughly half of it is outdated for the UI redesign track:

- the macOS keyboard `KEY_A == 0` regression has already been fixed
- app-side UI test launch hooks already exist
- repo-owned UI fixtures already exist
- several XCUITests for the redesigned shell already exist

What is still relevant:

- keep UI-shell testing separate from future headless core testing
- use temporary support directories and repo-owned fixtures for tests
- retire AppleScript only after XCUITest coverage is reliable
- add deterministic core seams before attempting golden/reference tests

The main correction is that the immediate problem is no longer "design a UI test strategy from scratch". The immediate problem is "finish and wire up the UI tests that already exist, then decide how much core-level coverage is still needed for redesign sign-off".

## Current State

### Implemented now

- The redesigned macOS shell is in place under [`src/macos`](/Users/alex/work/arculator-mac/src/macos).
- Existing XCUITest sources live under [`tests/ArculatorUITests`](/Users/alex/work/arculator-mac/tests/ArculatorUITests).
- Existing repo fixtures live under [`tests/fixtures`](/Users/alex/work/arculator-mac/tests/fixtures).
- The app accepts debug-only UI test launch arguments in [`src/macos/app_macos.mm`](/Users/alex/work/arculator-mac/src/macos/app_macos.mm):
  - `-ArculatorTestSupportPath`
  - `-ArculatorTestConfig`
- The macOS keycode bias fix is already present in [`src/keyboard_macos.h`](/Users/alex/work/arculator-mac/src/keyboard_macos.h) and [`src/macos/input_macos.m`](/Users/alex/work/arculator-mac/src/macos/input_macos.m).
- The Xcode project generator already contains UI test target generation in [`macos/generate_xcodeproj.rb`](/Users/alex/work/arculator-mac/macos/generate_xcodeproj.rb).

### Existing UI coverage

The current XCUITests already cover:

- idle launch and config selection
- launch with a preselected config
- run, pause, resume, and stop flows
- menu and toolbar state basics
- fullscreen entry and exit
- create and delete config flows

Current files:

- [`tests/ArculatorUITests/LaunchIdleUITests.swift`](/Users/alex/work/arculator-mac/tests/ArculatorUITests/LaunchIdleUITests.swift)
- [`tests/ArculatorUITests/PreselectedConfigUITests.swift`](/Users/alex/work/arculator-mac/tests/ArculatorUITests/PreselectedConfigUITests.swift)
- [`tests/ArculatorUITests/MenuToolbarSyncUITests.swift`](/Users/alex/work/arculator-mac/tests/ArculatorUITests/MenuToolbarSyncUITests.swift)
- [`tests/ArculatorUITests/ConfigManagementUITests.swift`](/Users/alex/work/arculator-mac/tests/ArculatorUITests/ConfigManagementUITests.swift)
- [`tests/ArculatorUITests/EmulationLifecycleUITests.swift`](/Users/alex/work/arculator-mac/tests/ArculatorUITests/EmulationLifecycleUITests.swift)

### Still missing now

- The checked-in [`Arculator.xcodeproj/project.pbxproj`](/Users/alex/work/arculator-mac/Arculator.xcodeproj/project.pbxproj) does not currently expose an `ArculatorUITests` target or scheme, even though the generator script knows how to create one.
- `xcodebuild -list -project Arculator.xcodeproj` currently shows only target/scheme `Arculator`.
- `xcodebuild test -project Arculator.xcodeproj -scheme ArculatorUITests ...` currently fails because that scheme does not exist in the checked-in project.
- VIDC inspection seams (`vidc_get_palette(...)`, `vidc_get_control_register()`) are deferred to later core-test priorities.
- No test-only capture backends exist under `src/test/`.
- Frame/audio golden tests and deeper boot-state checkpoints remain as later core-test priorities.

## What Is Outdated

These parts of the previous plan should no longer be treated as pending redesign work:

### 1. The keyboard `'a'` regression as an open fix item

This is already addressed by the keycode bias layer.

Keep it as a regression to cover in future tests if desired, but it should not remain listed as an active redesign blocker.

### 2. "Replace AppleScript smoke tests with XCUITest" as a greenfield task

This has already started. The correct remaining work is:

- make the existing XCUITests runnable from the checked-in project and CI
- close the remaining coverage gaps
- then remove the AppleScript scripts

### 3. The UI test file creation list

The old plan lists several UI test files as if they do not exist yet. They already exist, although some coverage is still incomplete.

### 4. The assumption that app-side test launch plumbing is missing

Support-path and preselected-config launch hooks already exist in the app. The plan should build on those hooks rather than re-propose them.

### 5. The verification commands as written

The old commands assume an `ArculatorUITests` scheme is already available. That is not true in the current checked-in project state.

## What Is Still Relevant

### 1. Separate UI-shell tests from future core tests

This is still the right split:

- XCUITest for shell behavior, menus, lifecycle, persistence, and redesigned window flow
- headless XCTest for config loading, CMOS, monitor state, keyboard mapping, and deterministic emulator assertions

### 2. Use temporary support roots and repo fixtures

This remains correct and is already the pattern used by the current UI test base class.

### 3. Retire AppleScript only after parity exists

This is still the right exit criterion. The AppleScript coverage should be treated as temporary fallback, not extended further.

### 4. Core seams before golden tests

Still correct. Golden/reference tests remain premature until the runtime is deterministic and observable.

### 5. Config/CMOS/monitor-state assertions are still useful

The old "boots to CLI" and "mono desktop" hypotheses should no longer anchor the redesign plan, but they are still valid candidates for later core tests if those regressions still reproduce.

## Updated Plan

## Phase 1: Make Existing XCUITests Runnable ✅

This is the immediate blocker.

### Goals

- sync the checked-in Xcode project with the generator
- expose UI tests through a shared scheme
- make `xcodebuild test` usable locally and in CI

### Required work

- Regenerate or update [`Arculator.xcodeproj/project.pbxproj`](/Users/alex/work/arculator-mac/Arculator.xcodeproj/project.pbxproj) so it actually contains the UI test target described in [`macos/generate_xcodeproj.rb`](/Users/alex/work/arculator-mac/macos/generate_xcodeproj.rb).
- Ensure at least one shared scheme runs the UI tests:
  - either a dedicated `ArculatorUITests` scheme
  - or the main `Arculator` scheme with UI tests in its test action
- Document the canonical command for running UI tests once this is wired correctly.

### Exit criteria

- `xcodebuild -list -project Arculator.xcodeproj` shows a runnable UI test path
- UI tests can be run without opening Xcode manually

## Phase 2: Finish Redesign UI Coverage ✅

Build on the tests that already exist instead of replacing them.

### Coverage already present

- launch to idle shell
- select config and show editor
- preselected config auto-run
- run, pause, resume, stop
- hard reset
- fullscreen
- create config
- delete config

### Highest-priority gaps

- Rename config flow.
- Duplicate config flow.
- Persistence across relaunch for renamed or duplicated configs.
- First-run welcome state and "Create Your First Machine" path.
- Mutability-gating behavior while running or paused.
- Pending-reset banner and "Apply and Reset" flow.
- Disc-slot attach/eject flows in the running sidebar, if redesign completion still includes those interactions.

### Notes

- Some of these tests will need more stable accessibility identifiers on editor controls and banners.
- Prefer expanding the current Swift XCUITests, not adding more AppleScript.

### Exit criteria

- The redesign-specific behaviors called out in [`docs/UI_REDESIGN_PLAN.md`](/Users/alex/work/arculator-mac/docs/UI_REDESIGN_PLAN.md) are covered by XCUITest at the shell level.

## Phase 3: Remove Legacy AppleScript Coverage ✅

All four legacy AppleScript files have been removed:

- `tests/run_macos_gui_smoke_test.sh`
- `tests/macos_gui_smoke_test.applescript`
- `tests/run_macos_session1_check.sh`
- `tests/macos_session1_check.applescript`

Preconditions were met: XCUITest coverage is equivalent and reliable.

## Phase 4: Add Headless Core Tests as a Follow-On Track ✅ (first priorities)

The first core-test priorities are implemented as a host-less XCTest unit bundle (`ArculatorCoreTests`).

### Implemented

- `ArculatorCoreTests` target in the Xcode project (host-less unit test bundle)
- Test seams: `platform_paths_init_test()`, `platform_paths_reset()`, `cmos_get_ram_ptr()`
- CMOS fixture at `tests/fixtures/cmos/`
- Linker stubs in `tests/ArculatorCoreTests/core_test_stubs.c`

### First core priorities — covered

- config load path correctness (`ConfigLoadTests.m` — 7 tests)
- CMOS file resolution correctness (`CMOSLoadTests.m` — 3 tests)
- monitor type loaded from config (covered by `ConfigLoadTests`)
- keyboard mapping assertions for macOS keycodes (`KeyboardMappingTests.m` — 6 tests)
- platform path API (`PlatformPathTests.m` — 6 tests)

### Later core priorities — still future work

- VIDC inspection seams (`vidc_get_palette(...)`, `vidc_get_control_register()`)
- deterministic RTC override
- frame or audio golden tests
- deeper boot-state checkpoints

## Planned Files

### Still future work

- `src/test/video_capture.c`
- `src/test/sound_capture.c`
- `src/test/input_null.c`
- `src/test/test_capture.h`
- Additional core tests as needed for later priorities

## Verification

### Current reality

As of 2026-04-05:

- `xcodebuild -list -project Arculator.xcodeproj` exposes `Arculator`, `ArculatorUITests`, and `ArculatorCoreTests`
- The shared `Arculator` scheme includes both test targets in its test action

### Target verification after Phase 1

Run whichever command matches the shared scheme that is actually created, for example:

```sh
xcodebuild test \
  -project Arculator.xcodeproj \
  -scheme Arculator \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

or:

```sh
xcodebuild test \
  -project Arculator.xcodeproj \
  -scheme ArculatorUITests \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

### Target verification after Phase 4

Core tests only:

```sh
xcodebuild test \
  -project Arculator.xcodeproj \
  -scheme Arculator \
  -only-testing ArculatorCoreTests \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

## Definition of Done for the Redesign Testing Track

The redesign testing work should be considered complete when:

- existing XCUITests are runnable from the checked-in project and CI ✅
- redesign-critical shell flows are covered by XCUITest ✅
- AppleScript smoke scripts are removed ✅
- any remaining core-test work is explicitly tracked as emulator regression coverage, not hidden inside the UI redesign milestone ✅

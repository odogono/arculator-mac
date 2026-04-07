# XCTest and XCUITest Plan for Arculator macOS

## Context

The native macOS port is functionally complete, but there are three known regressions that need to be confirmed, fixed, and kept fixed:

1. **'a' key dead**: `KEY_A` is `0x00` in `keyboard_macos.h`, but shared keyboard logic treats keycodes as 1-based in two places:
   - `keyboard_init()` writes `keytable[keys[c][0] - 1]`
   - `keyboard_poll()` scans `key[1..511]`
2. **Boots to CLI instead of desktop**: likely the wrong CMOS file, wrong support path, or wrong machine config is being loaded.
3. **Mono desktop, color cursor**: likely the wrong `monitor_type` is being loaded from config, or a config/path mismatch is causing a mono fallback.

Goal: build an all-Xcode test strategy that can confirm these regressions programmatically, support debugging them with deterministic fixtures, and prevent regressions in both the emulator core and the macOS app shell.

## Test Strategy

Use two test targets, with clear ownership:

### `ArculatorCoreTests`

Headless XCTest bundle for emulator-state validation.

- Runs without Metal, Core Audio, or AppKit windows.
- Links the emulator core plus test capture/null backends.
- Owns path resolution, CMOS loading, keyboard mapping, monitor/config state, and deterministic boot inspection.

### `ArculatorUITests`

Hosted XCUITest target for app-shell validation.

- Launches the actual macOS app.
- Replaces the current AppleScript-based GUI smoke coverage.
- Owns launch, menus, dialogs, config persistence, and shutdown flows.

This split matters: emulator-state regressions should be debugged with small, deterministic headless tests; app-shell regressions should be covered with XCUITest, not shell scripts or AppleScript.

## Phase 0: Determinism and Test Seams

Before adding long-running boot or golden-reference tests, make the runtime deterministic and observable.

### Required seams

**`src/platform_paths.h` / `src/platform_paths.c`**

Add test-only initialization/reset hooks:

- `platform_paths_init_test(const char *resources_root, const char *support_root)`
- `platform_paths_reset()`

`platform_paths_reset()` must also clear any cached ROM-root state, not just the initialized flag.

**`src/cmos.h` / `src/cmos.c`**

Add:

- `const uint8_t *cmos_get_ram_ptr(void)`

Also add a deterministic RTC override for tests, either via:

- a small setter API, or
- a test-only environment variable checked by CMOS init/load code

Without fixed RTC values, boot-state and golden-reference tests will drift.

**`src/vidc.h` / `src/vidc.c`**

Add minimal read accessors used only for assertions:

- `uint32_t vidc_get_palette(int index)`
- `uint32_t vidc_get_control_register(void)`

### Optional but useful seam

For keyboard tests, add a narrow observability hook instead of relying on indirect side effects from `keyboard_poll()`. For example:

- expose the translated row/column for a host keycode, or
- add a tiny test callback/log for dispatched keyboard events

This keeps keyboard tests simple and avoids depending on unrelated emulator state.

## Phase 1: Headless Capture Backends

Create a small test-only backend layer under `src/test/`.

### `src/test/video_capture.c`

Implements `plat_video.h`.

- `video_renderer_init()` / `video_renderer_reinit()` / `video_renderer_close()` are no-ops.
- `video_renderer_update()` hashes the dirty pixel region.
- `video_renderer_present()` records a frame checksum into a ring buffer.

### `src/test/sound_capture.c`

Implements `plat_sound.h`.

- `sound_dev_init()` / `sound_dev_close()` are no-ops.
- `sound_givebuffer()` and `sound_givebufferdd()` hash emitted buffers into a ring buffer.

### `src/test/input_null.c`

Implements `plat_input.h` entry points needed by the core test target.

- No-op host snapshot capture/apply.
- Stable zeroed keyboard/mouse state for unattended boot tests.

### `src/test/test_capture.h`

Declares read APIs used by tests, for example:

- frame count
- frame checksum by index
- audio buffer count
- audio checksum by index
- reset helpers

## Phase 2: Shared Core Build for Tests

Do not maintain a hand-curated, drifting “test-only source list” if it can be avoided.

Preferred approach:

- build a reusable `ArculatorCore` static library or shared source grouping in Xcode
- have both the app target and `ArculatorCoreTests` consume it
- swap only the platform backends for the headless test target

If the project cannot be restructured that far yet, the plan must at least document the exact non-UI dependencies still required by `arc_init()`, since startup does more than video/input/audio initialization.

## Phase 3: `ArculatorCoreTests`

Add a native XCTest bundle target:

- product type: unit test bundle
- no UI host application required
- links emulator core plus `src/test/*.c`
- excludes AppKit/Metal/CoreAudio frontend sources

### Fixture model

Use repo-owned fixtures under `tests/fixtures/`, not files copied from a developer machine.

Fixtures should include:

- `arc.cfg`
- `configs/test-machine.cfg`
- `cmos/test-machine.<romset>.cmos.bin`

These fixtures should be intentionally minimal and documented. ROM images remain external and are located via `ARCULATOR_TEST_ROM_PATH` or a known default path.

### Test setup

Each test case should:

1. Create a temporary support directory.
2. Copy fixture config/CMOS files into it.
3. Resolve ROMs from `ARCULATOR_TEST_ROM_PATH`, else a standard local default.
4. Skip cleanly if ROMs are unavailable.
5. Call `platform_paths_init_test(...)`.
6. Set `machine_config_name` and `machine_config_file`.
7. Apply deterministic RTC/test overrides.

Each teardown should:

1. call `arc_close()` if startup completed
2. call `platform_paths_reset()`
3. remove the temporary directory

### Initial core tests

#### `BootInspectTests`

State-based tests should come first.

**`testCMOSLoadedCorrectly`**

- Start the emulator.
- Read `cmos_get_ram_ptr()`.
- Assert key bytes match the fixture CMOS image.

This should confirm or disprove the CMOS/path hypothesis directly.

**`testMonitorTypeLoadedFromConfig`**

- Start the emulator.
- Assert `monitor_type` matches the fixture config expectation.

This is the fastest way to confirm whether the mono display issue is a config-load problem.

**`testVIDCEntersColorMode`**

- Run enough frames to reach normal video initialization.
- Assert control register and palette state are compatible with a color desktop.

This should be secondary to `monitor_type`, not the first line of diagnosis.

#### `KeyboardMappingTests`

Keep these narrow and deterministic.

**`testMacOSKeycodesAreSafeForSharedKeyboardLogic`**

- Validate that all macOS keycodes used by the input backend are valid for the shared keyboard tables and polling logic.
- Explicitly catch the `KEY_A == 0` case.

**`testKeyAProducesExpectedMapping`**

- Assert that the 'A' key is not dropped by the host-keycode to emulated-key mapping path.
- Prefer a direct mapping/assertion seam over a fully booted emulator test.

## Phase 4: Fix the Known Regressions

### Fix #1: Keyboard 'a' key

The current diagnosis is sound:

- `keyboard_init()` writes `keytable[keycode - 1]`
- `keyboard_poll()` iterates `key[1..511]`

For macOS keycodes, `0x00` is therefore invalid in shared logic.

Recommended fix:

- add `KEYCODE_MACOS_BIAS 1` in `src/keyboard_macos.h`
- bias all macOS `KEY_*` definitions that participate in the shared key arrays
- update `src/macos/input_macos.m` to translate back to the raw macOS virtual key code before calling `CGEventSourceKeyState`

This keeps the shared keyboard code untouched and limits the platform-specific adaptation to the macOS layer.

### Fix #2: CLI boot instead of desktop

Investigate only after `testCMOSLoadedCorrectly` is in place.

Likely causes:

- wrong support root
- wrong machine config path
- wrong CMOS filename or naming convention
- fallback CMOS resource unexpectedly used

The test should be designed to identify which file was loaded, not just that boot output differed.

### Fix #3: Mono desktop

Investigate only after the config/path tests are in place.

Likely causes:

- wrong `monitor_type` loaded from machine config
- config not loaded at all
- config from an unexpected location

Start with `monitor_type` assertions before adding video-hash comparisons.

## Phase 5: Golden Reference Tests

Only add golden/reference tests after:

- deterministic RTC behavior exists
- CMOS/config-path tests are stable
- keyboard bug is fixed
- color/monitor-state tests are stable

### Scope

Golden tests should compare a small number of deliberate checkpoints, for example:

- selected frame checksums
- selected audio checksums
- selected palette values
- final monitor/config state

### Generation

Golden generation must be explicit, never implicit.

Use either:

- a dedicated script, or
- an explicit env flag such as `ARCULATOR_GENERATE_GOLDENS=1`

`xcodebuild test` should fail on mismatch, not silently rewrite fixtures.

## Phase 6: `ArculatorUITests`

Replace the AppleScript smoke tests with hosted XCUITests.

Add a UI test target that launches the real app and uses launch arguments/environment to point the app at a temporary support directory and known test config.

### Required app-side support

The app should accept test launch configuration such as:

- support root override
- resources/ROM override if needed
- initial machine config selection
- optional flags that disable nonessential prompts or audio for UI tests

This is better than mutating the real `~/Library/Application Support/Arculator` directory during UI automation.

### Initial UI test coverage

`LaunchAndMenusUITests`

- launch app with a known config
- wait for the main window
- open “Configure Machine...”
- cancel and verify the window closes
- invoke “Hard Reset”
- exit cleanly

`ConfigPersistenceUITests`

- create a config
- rename it
- copy/delete as needed
- relaunch the app
- verify the persisted config state is visible and correct

These tests replace the current GUI smoke intent, but with first-party Xcode automation instead of AppleScript.

## Files to Create

| File | Purpose |
|------|---------|
| `src/test/video_capture.c` | Headless video capture backend |
| `src/test/sound_capture.c` | Headless sound capture backend |
| `src/test/input_null.c` | Null input backend for unattended tests |
| `src/test/test_capture.h` | Capture/test query API |
| `tests/ArculatorCoreTests/BootInspectTests.m` | Headless startup/state tests |
| `tests/ArculatorCoreTests/KeyboardMappingTests.m` | Keyboard mapping regression tests |
| `tests/ArculatorCoreTests/GoldenReferenceTests.m` | Deterministic golden/reference tests |
| `tests/ArculatorUITests/LaunchAndMenusUITests.m` | XCUITest launch/menu flows |
| `tests/ArculatorUITests/ConfigPersistenceUITests.m` | XCUITest config persistence flows |
| `tests/fixtures/arc.cfg` | Global config fixture |
| `tests/fixtures/configs/test-machine.cfg` | Machine config fixture |
| `tests/fixtures/cmos/` | CMOS fixtures |

## Files to Modify

| File | Change |
|------|--------|
| `src/platform_paths.h` | Declare test init/reset APIs |
| `src/platform_paths.c` | Implement test init/reset and clear caches |
| `src/cmos.h` | Declare CMOS accessor and deterministic test hook as needed |
| `src/cmos.c` | Implement CMOS accessor and deterministic RTC override |
| `src/vidc.h` | Declare minimal inspection accessors |
| `src/vidc.c` | Implement palette/control-register accessors |
| `src/keyboard_macos.h` | Add keycode bias and update `KEY_*` definitions |
| `src/macos/input_macos.m` | Translate biased test/runtime keycodes back to raw macOS virtual keycodes |
| `Arculator.xcodeproj/project.pbxproj` | Add core/unit/UI test targets |

## Verification

### Core tests

Run:

```sh
xcodebuild test \
  -project Arculator.xcodeproj \
  -scheme ArculatorCoreTests \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

Expected flow:

1. state-based tests fail first and confirm the current regressions
2. fixes land
3. state-based tests pass
4. deterministic golden tests are added and remain stable

### UI tests

Run:

```sh
xcodebuild test \
  -project Arculator.xcodeproj \
  -scheme ArculatorUITests \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

Expected flow:

1. AppleScript GUI smoke coverage is retired
2. XCUITest covers launch/menu/config flows
3. UI regressions are caught inside Xcode and CI without external scripting

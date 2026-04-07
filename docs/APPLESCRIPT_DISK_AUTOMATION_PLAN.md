# AppleScript Plan For Ready Hard-Disc Support

## Summary

The AppleScript work should support two distinct goals:

1. Fix the runtime scripting surface so it is actually callable from `osascript`.
2. Extend the scripting API enough to automate creation of a known-good formatted hard-disc template once, then let the product use native template cloning at startup.

AppleScript should not become the product mechanism for making hard discs appear ready. It should be used for:

- one-time developer tooling to manufacture template HDFs
- end-to-end smoke coverage for the scripting surface
- optional power-user automation

The shipped user experience should still be native: create or detect a blank image, clone a bundled formatted template, and boot with the drive already mountable.

---

## Current State

### What already exists

- Lifecycle scripting exists: `start emulation`, `stop emulation`, `pause emulation`, `resume emulation`, `reset emulation`, `start config`.
- Config scripting exists for configs and floppy discs.
- Input scripting exists for key up/down, `type text`, relative mouse move, and mouse button injection.
- The command implementations compile and pass unit tests.

### What is currently broken

- The built app reports `The application has a corrupted dictionary. (-2705)` when queried from `osascript`.
- The scripting API has no first-class concept of internal hard drives.
- Mouse injection is relative only, which is fragile for guest UI automation.
- There is no scriptable way to wait for or observe guest milestones beyond coarse host state such as `emulation state`.

### Consequence

The current API is not sufficient to manufacture a formatted HDF reliably, and the dictionary failure means it is not usable from real AppleScript clients at all.

---

## Design Decision

### Product path

Use native template cloning in the app for ready-to-use hard discs.

### Scripting path

Use AppleScript to:

- create and attach blank internal hard-disc images for developer workflows
- drive one-time guest formatting to produce template artifacts
- verify automation and lifecycle behavior in smoke tests

This keeps the product robust while still making the template-authoring workflow repeatable.

---

## Phase 0: Make The Dictionary Usable  [COMPLETE]

### Goal

Get a built `Arculator.app` working with real `osascript` calls.

### Work

- Add a runtime smoke script outside the unit-test bundle that exercises the built app through `osascript`.
- Bisect the dictionary until the minimal valid surface is known to work.
- Fix the `.sdef` or scripting object model so the app no longer reports a corrupted dictionary.
- Keep the validation loop external:
  - `sdef <app>`
  - `osascript 'using terms from application ...'`
  - simple reads such as `name`, `emulation state`, `config names`

### Likely implementation approach

- Start from a minimal dictionary containing only a single custom property or command and reintroduce terms incrementally.
- Treat the current `Arculator.sdef` as suspect until `osascript` resolves it successfully against the built app.
- Add a regression test script under `tests/` that fails the build if the dictionary cannot be loaded by `osascript`.

### Exit criteria

- `osascript` can query `name`, `emulation state`, and `config names` from the built app.
- `osascript` can execute `start config` and `stop emulation`.
- The smoke script passes against the debug app bundle.

### Implementation notes

Three root causes were identified and fixed:

1. **Invalid quit command code**: The `quit` command in `Arculator.sdef` had a 9-character code (`aaborquit`) instead of the required 8-character code. Fixed to `aevtquit`.
2. **Scripting source files not compiled into the app**: The six scripting `.mm` files (`ScriptingCommandSupport`, `LifecycleScriptingCommands`, `ConfigScriptingCommands`, `InputScriptingCommands`, `NSApplication+Scripting`, `InputInjectionBridge`) were only compiled into the test bundle, not the app target. Added them to `SOURCE_FILES` in `generate_xcodeproj.rb`.
3. **sdef not bundled as a resource**: The `Arculator.sdef` file was not included in `RESOURCE_FILES`, so macOS could not find it in the app bundle. Added it to the resource list.

Additionally fixed the core test target to pick up `.mm` test files (glob was `*.m` only).

Smoke test script added at `tests/applescript_smoke_test.sh`.

---

## Phase 1: Add First-Class Internal Hard-Drive Scripting  [COMPLETE]

### Goal

Make internal hard drives scriptable without editing config files indirectly or driving the settings UI.

### New concepts

- internal drive slot `4` or `5`
- controller kind: `ide` or `st506`
- geometry: `cylinders`, `heads`, `sectors`
- image state: `blank raw`, `initialized`, `unknown`

### API additions

Add scriptable properties and commands for the loaded config while emulation is idle:

- `internal drive info`
  - Returns path, geometry, controller kind, and image state for drives 4 and 5.
- `set internal drive`
  - Parameters: `drive`, `path`, `cylinders`, `heads`, `sectors`
  - Allowed only while idle.
- `eject internal drive`
  - Removes the configured HDF from drive 4 or 5 while idle.
- `create hard disc image`
  - Parameters:
    - destination path
    - controller kind or preset geometry
    - initialization mode: `blank` or `ready`
  - Returns the created path and geometry.

### Bridge work

- Extend `ConfigBridge` with read/write methods for `hd4_fn`, `hd5_fn`, `hd4_sectors`, `hd4_heads`, `hd4_cylinders`, `hd5_*`.
- Reuse the existing internal-image classifier already added in the macOS layer.
- Surface script errors for invalid drive numbers, bad geometry, and illegal state transitions.

### Exit criteria

- A script can create an internal HDF, attach it to drive 4, and confirm its state without touching the UI.
- A script can distinguish blank and initialized images.

### Implementation notes

New files:
- `src/macos/InternalDriveScriptingCommands.mm` — four new command classes: `InternalDriveInfoCommand`, `SetInternalDriveCommand`, `EjectInternalDriveCommand`, `CreateHardDiscImageCommand`.

ConfigBridge extensions:
- `+internalDriveInfoForIndex:` — reads `hd_fn[]`, geometry, controller kind, and runs the image state classifier. Returns an NSDictionary record.
- `+setInternalDriveIndex:path:cylinders:heads:sectors:` — writes HD globals and calls `saveconfig()`.
- `+ejectInternalDriveIndex:` — clears HD globals and calls `saveconfig()`.
- `+createBlankHDFAtPath:cylinders:heads:sectors:isST506:` — writes a zero-filled file of the correct size.

sdef additions: four new commands under the Arculator Suite with proper four-char codes (ARCuHDIF, ARCuHDST, ARCuHDEJ, ARCuHDCR).

All 46 unit tests pass including new internal drive command tests.

---

## Phase 2: Add Deterministic Guest Automation Primitives  [COMPLETE]

### Goal

Reduce the amount of brittle UI guessing needed to run the guest formatter once.

### Required additions

- Absolute guest mouse positioning
  - Add `move guest mouse to x ... y ...`
  - Relative motion alone is too sensitive to pointer drift.
- Input reset
  - Add `clear injected input` to force-release keys and mouse state between steps.
- Optional guest snapshot support
  - Add `capture emulation screenshot to <path>`
  - Useful for debugging and for manual review of the authoring flow.

### Nice-to-have additions

- `wait until emulation state is ... timeout ...`
  - Mainly a convenience wrapper over polling.
- `guest boot delay preset`
  - Lets scripts use named waits such as `short`, `desktop`, `apps-loaded` rather than hard-coded sleeps.

### Why this is enough

Template generation is a one-time developer workflow. We do not need full semantic introspection of the RISC OS desktop if we have:

- reliable start/stop/reset
- deterministic drive attachment
- keyboard text entry
- absolute mouse placement
- screenshot capture for debugging

### Exit criteria

- A single script can boot a known config, open the formatter path, perform the required input sequence, and stop emulation without host accessibility hacks.

### Implementation notes

New C layer support:
- Added `input_inject_mouse_abs(int x, int y)` through the full stack: `input_snapshot.h/.c` (new struct fields + `inject_mouse_abs` function), `plat_input.h`, `input_macos.m`.
- Absolute positioning overrides accumulated deltas in `input_snapshot_apply()` when a pending absolute position is set, then clears itself.

New bridge methods:
- `InputInjectionBridge +injectMouseAbsX:y:` — wraps `input_inject_mouse_abs()`.
- `InputInjectionBridge +clearAllInjectedInput` — clears both keys and mouse in one call.
- `EmulatorBridge +captureScreenshotToPath:` — captures the Metal view via `CGWindowListCreateImage` and writes PNG.

New sdef commands:
- `move guest mouse to x ... y ...` (ARCuMGMT)
- `clear injected input` (ARCuCLIN)
- `capture emulation screenshot` (ARCuSSHT)

New file: `src/macos/AutomationScriptingCommands.mm` — three command classes.

All 49 unit tests pass.

---

## Phase 3: Add Native Ready-Image Creation And Mirror It In AppleScript  [COMPLETE]

### Goal

Make the product feature native, while exposing the same operation to scripts for tooling and tests.

### Native behavior

- `New hard disc` should support `blank` and `ready` creation modes.
- If the image matches a supported geometry, `ready` clones a bundled formatted template.
- On startup, if an attached image is blank raw and the geometry is supported, prompt once to initialize by cloning the template.

### Matching scripting command

Add:

- `create hard disc image ... initialization mode ready`

This command should call the same native path as the UI, not a separate implementation.

### Why this matters

Once the template exists, the product goal no longer depends on guest automation. AppleScript remains useful for generating or verifying templates, but end users get a native ready-on-boot flow.

### Exit criteria

- UI creation and AppleScript creation both produce identical initialized HDFs for supported default geometries.
- Startup initialization offer uses the same clone path.

### Implementation notes

Shared native code path (ConfigBridge):
- `+templatePathForCylinders:heads:sectors:isST506:` — resolves bundled templates at `Resources/templates/{kind}_{C}x{H}x{S}.hdf.zlib` first, then falls back to uncompressed `.hdf`.
- `+hasTemplateForCylinders:heads:sectors:isST506:` — checks if a template exists.
- `+createReadyHDFAtPath:...` — inflates compressed templates to the destination HDF, or clones uncompressed templates via `NSFileManager copyItemAtPath:toPath:`.

Both UI and scripting use the same ConfigBridge methods:
- The `create hard disc image` AppleScript command now accepts an `initialization` parameter (`blank` or `ready`). When `ready`, it calls `+createReadyHDFAtPath:` instead of `+createBlankHDFAtPath:`.
- The native `New hard disc` dialog now has a "Pre-formatted (ready to use)" checkbox. When checked, `confirm:` calls `+createReadyHDFAtPath:` instead of writing zeroes.
- `showStartupWarningsForLoadedConfigIfNeeded` now checks for available templates: if one exists for the blank image's geometry, it prompts the user to initialize via `arc_confirm` and clones the template on acceptance. Otherwise it falls back to the original informational warning.

Template naming convention: `{ide|st506}_{C}x{H}x{S}.hdf.zlib` or `{ide|st506}_{C}x{H}x{S}.hdf` in `Resources/templates/`. Default geometries are IDE `101x16x63` and ST-506 `615x8x32`. The IDE template is now seeded from the externally supplied formatted `HD4.HDF` artifact and bundled compressed; ST-506 remains unresolved (Phase 4).

All 50 unit tests pass.

---

## Phase 4: One-Time Template Authoring Workflow

### Goal

Use a validated seed artifact for the IDE template and the repaired scripting API only for the remaining ST-506 template workflow.

### Recommended workflow

1. Preserve the externally supplied `HD4.HDF` byte-for-byte after decompression from `macos/templates/ide_101x16x63.hdf.zlib`.
2. Validate that it boots as an empty formatted IDE hard disc with geometry `101/16/63`.
3. For ST-506 only, create a blank default-geometry HDF, attach it as internal drive 4, boot the config, format in the guest, shut down cleanly, validate on reboot, and store the HDF as a bundled template resource.

### Scope

- IDE default template:
  - `63/16/101`
- ST-506 default template:
  - `32/8/615`

### Recommended authoring configs

- IDE template config:
  - Name: `Template IDE`
  - Base machine: `A3010`
  - Why: New I/O preset with IDE support and a RISC OS 3.1 environment.
- ST-506 template config:
  - Name: `Template ST506`
  - Base machine: `Archimedes 440/1`
  - Why: Old I/O + ST-506 preset, so the controller family is unambiguous.

These configs should be created once in the UI, saved with no internal hard disc attached, and then reused by the authoring script.

### Current implementation status

Phase 4 now has a checked-in host-side workflow:

- `macos/templates/ide_101x16x63.hdf.zlib`
  - compressed from the externally supplied formatted `HD4.HDF`
  - decompresses to a byte-for-byte copy of the seed
  - preserves the legacy/RPCEmu-style layout with the FileCore disc record at `0xFC0`
  - matches Arculator's existing IDE `skip512` compatibility path
- `scripts/author_ready_hdf_templates.sh`
  - keeps the existing IDE seed template unless `--force` is used
  - creates blank candidate HDFs for workflows that still need in-guest formatting
  - attaches them through AppleScript
  - boots the selected config
  - captures screenshots before and after formatting
  - verifies the host-side image classifier returns `initialized`
  - moves the finished HDFs into `macos/templates/`
- `scripts/automate_ide_template_guest.sh`
  - IDE-first guest automation helper
  - opens the RISC OS command line with `F12`
  - optionally types a configurable formatter launch command
  - optionally performs configured absolute guest clicks
  - captures screenshots for calibration
- `tests/applescript_internal_drive_smoke_test.sh`
  - validates the real `osascript` path for create/attach/query on internal drive 4

The remaining manual step is producing the ST-506 template. The IDE path no longer depends on AppleScript guest formatting because the formatted seed is bundled directly.

### Validation

- Reboot into a clean config with the produced image attached.
- Confirm the disc mounts on first desktop load.
- Confirm the internal-image classifier reports `initialized`, not `blank raw`.

---

## Testing Plan

### Unit tests

- Scripting command validation for all new internal-drive commands.
- Input injection tests for absolute mouse positioning and input clearing.
- Config bridge tests for internal-drive read/write helpers.
- Ready-image creation tests:
  - blank mode creates zero-filled raw image
  - ready mode clones template
  - invalid geometry or missing template returns a script error

### Integration tests

- `osascript` dictionary smoke test against the built app.
- `osascript` lifecycle smoke test:
  - `start config`
  - `emulation state`
  - `stop emulation`
- `osascript` internal-drive smoke test:
  - create HDF
  - attach HDF
  - query image state

### Manual verification

- Run the template-authoring script once to generate a formatted IDE template.
- Use the product UI to create a new ready IDE hard disc and verify the icon appears at first desktop boot.
- Attach an old blank raw HDF and verify the one-shot initialization offer appears.

---

## Risks And Mitigations

### Dictionary remains fragile

Mitigation:

- Add a real `osascript` smoke test and treat it as required coverage.
- Keep the dictionary surface small and explicit.

### Guest automation is timing-sensitive

Mitigation:

- Restrict guest automation to one-time template authoring.
- Add absolute mouse positioning and screenshot capture.
- Avoid relying on the settings window or host accessibility tree.

### Divergence between UI and scripting behavior

Mitigation:

- Route both through shared native creation and template-cloning code.
- Do not implement separate script-only creation logic.

### Template images become opaque artifacts

Mitigation:

- Check in the authoring script alongside the templates.
- Document the exact config, geometry, and authoring flow used to regenerate them.

---

## Suggested File Changes

### New or expanded scripting surface

- `macos/Arculator.sdef`
- `src/macos/NSApplication+Scripting.mm`
- `src/macos/ConfigScriptingCommands.mm`
- `src/macos/InputScriptingCommands.mm`
- `src/macos/InputInjectionBridge.h`
- `src/macos/InputInjectionBridge.mm`

### Native shared functionality

- `src/macos/ConfigBridge.h`
- `src/macos/ConfigBridge.mm`
- `src/macos/StorageSettingsView.swift`
- `src/macos/hd_macos.mm`

### Tests and tooling

- new `tests/` AppleScript smoke script for runtime dictionary validation
- new core tests for internal-drive scripting commands
- new developer script for template authoring

---

## Recommended Delivery Order

1. Fix the runtime dictionary and add the `osascript` smoke test.
2. Add internal hard-drive scripting commands and queries.
3. Add absolute mouse positioning and input reset.
4. Add native ready-image creation and expose the same path to AppleScript.
5. Use the scripting API once to generate the IDE and ST-506 template images.
6. Wire those templates into the user-facing startup and `New hard disc` flows.

This order keeps the risk low: first make scripting real, then make it useful, then stop relying on it for the end-user path.

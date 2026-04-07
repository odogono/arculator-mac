# Port Arculator to Native macOS UI

## Summary

Arculator already runs on macOS, but the current macOS build is still a wxWidgets + SDL2 port. It works, but the app shell, dialogs, rendering, input, audio, and threading model are all shaped by cross-platform constraints rather than native macOS behavior.

The goal of this project is to replace the macOS-specific wxWidgets + SDL2 layer with native macOS frameworks while preserving emulator behavior and file compatibility.

The important correction to the previous version of this plan is that the codebase is not yet cleanly separated into "untouched core" and "replaceable platform shell". The emulator logic can stay intact, but some platform-facing headers, lifecycle functions, file-path assumptions, and thread ownership rules must be refactored first.

## Goals

- Replace the macOS UI shell with AppKit.
- Replace SDL video with Metal.
- Replace SDL audio with Core Audio.
- Replace SDL input with native keyboard/mouse handling.
- Replace SDL joystick support with Game Controller.
- Preserve machine configs, ROM loading behavior, podule loading, and emulator behavior.
- Produce a real `.app` bundle suitable for code signing and distribution.

## Non-Goals

- Rewriting emulator logic or machine emulation algorithms.
- Changing config file formats.
- Removing the autotools build used by Linux and other existing ports.
- Converting the UI to SwiftUI.

## Current State

The current macOS port is spread across several layers:

- Platform backends:
  - `src/video_sdl2.c`
  - `src/sound_sdl2.c`
  - `src/input_sdl2.c`
  - `src/wx-sdl2-joystick.c`
- App shell and lifecycle:
  - `src/wx-app.cc`
  - `src/wx-main.cc`
  - `src/wx-sdl2.c`
- Dialogs and dynamic config UI:
  - `src/wx-config.cc`
  - `src/wx-config_sel.cc`
  - `src/wx-podule-config.cc`
  - `src/wx-hd_new.cc`
  - `src/wx-hd_conf.cc`
  - `src/wx-joystick-config.cc`
  - `src/wx-console.cc`

There are already platform abstraction headers:

- `src/plat_video.h`
- `src/plat_input.h`
- `src/plat_sound.h`
- `src/plat_joystick.h`

But the separation is incomplete:

- `src/main.c` still includes `video_sdl2.h`.
- `src/arc.h` exposes app-shell lifecycle and UI-driven control functions.
- `src/wx-sdl2.c` owns thread control, resizing, fullscreen, menu-triggered machine mutation, and shutdown behavior.
- File and resource loading assumes repo-relative paths rooted at `exname`.

## Technology Choices

| Layer | Current | Replacement | Reason |
|-------|---------|-------------|--------|
| App shell | wxWidgets | AppKit (Objective-C) | Native menus, windows, dialogs, fullscreen, responder chain |
| Rendering | SDL2 Renderer | Metal via `MTKView` | Native, supported GPU path on macOS |
| Audio | SDL2 Audio | Core Audio | Lower-level control and no SDL dependency |
| Keyboard/mouse | SDL events/state | `NSEvent` + Core Graphics | Native event handling and mouse capture behavior |
| Game controllers | SDL_Joystick | Game Controller | Native controller discovery and mapping |
| Build | Autotools | Xcode project for macOS only | Required for app bundle, signing, Metal shaders |

## Public Interface Changes

The emulator core should remain behaviorally stable, but these platform-facing interfaces will be cleaned up:

- `src/plat_input.h`
  - Conditionally include `keyboard_macos.h` on macOS instead of `keyboard_sdl.h`.
- `src/arc.h`
  - Remove app-shell-specific declarations into a dedicated shell header, for example `platform_shell.h`.
  - Keep emulator-facing functions in `arc.h`.
- `src/main.c`
  - Remove direct inclusion of `video_sdl2.h`.

No config file format changes are planned.

## Source Tree Policy

macOS-specific implementation files should live under a dedicated `src/macos/` subtree rather than being mixed into shared cross-platform sources.

Rules:

- New macOS-only app shell, backend, dialog, and helper sources live under `src/macos/`.
- Existing macOS-specific implementation sources should be moved under `src/macos/` as part of the migration where practical.
- Shared emulator code and cross-platform abstractions remain under `src/`.
- Shared podule code remains in existing shared directories unless the implementation is macOS-only.
- macOS-only podule helper implementations should also live under a `src/macos/` path, not directly beside shared SDL helpers.

## Filesystem and Bundle Layout

This must be designed before implementation. The current repo-relative layout is not valid for a bundled macOS app.

### Bundled read-only resources

These ship inside `Arculator.app/Contents/Resources/`:

- App icon and bundle metadata
- Built-in UI assets
- Bundled helper resources that are currently read via `exname`
- Optional bundled internal podule ROM assets if they are distributed with the app

### User-writable data

These move to `~/Library/Application Support/Arculator/`:

- `arc.cfg`
- machine configs under `configs/`
- CMOS files
- logs
- generated hard-disc images if created through the app, unless the user explicitly chooses another path

### External content

These stay user-managed:

- ROM sets
- external podule `.dylib` bundles
- imported disc images and hard-disc images

### Path API requirement

Add a small path service for macOS rather than continuing to concatenate against `exname`:

- app resources root
- application support root
- configs root
- podules root
- ROM search roots

The implementation must stop depending on the executable directory as the writable data root.

## Threading Contract

This must be explicit before any backend replacement.

### Main thread responsibilities

- `NSApplication` run loop
- AppKit windows, menus, dialogs
- `MTKView` draw callback
- Native event collection
- Display-state changes such as fullscreen, resize, title updates

### Emulation thread responsibilities

- `arc_init()`
- repeated `arc_run()`
- `arc_close()`
- machine reset and media changes after marshaling through the emulation control layer

### Synchronization model

Use two mechanisms, not one generic lock for everything:

- Command queue from UI thread to emulation thread for:
  - stop
  - reset
  - disc change/eject
  - display mode changes
  - renderer reset requests
- Input snapshot shared from main thread to emulation thread for:
  - key state
  - mouse button state
  - mouse relative delta
  - controller state

The emulation thread consumes a snapshot once per `arc_run()` tick. UI code must not directly mutate emulator state structures outside the control queue.

### Video contract

- The emulator produces pixel updates into a CPU-visible staging buffer.
- The main thread uploads staged regions to a Metal texture.
- `video_renderer_present()` becomes a publish/schedule call, not a direct present-to-screen operation.

## New macOS Files

| New file | Replaces | Purpose |
|----------|----------|---------|
| `src/macos/video_metal.m` + `src/macos/Shaders.metal` | `video_sdl2.c` | Metal renderer backend |
| `src/macos/sound_coreaudio.m` | `sound_sdl2.c` | Core Audio backend |
| `src/macos/input_macos.m` + `src/macos/keyboard_macos.h` | `input_sdl2.c` + `keyboard_sdl.h` | Native key and mouse state |
| `src/macos/joystick_gc.m` | `wx-sdl2-joystick.c` | Native controller backend |
| `src/macos/app_macos.m` | `wx-app.cc` + `wx-main.cc` + `wx-sdl2.c` | NSApplication, NSWindow, menus, lifecycle, event routing |
| `src/macos/config_macos.m` | `wx-config.cc` | Machine configuration dialog |
| `src/macos/config_sel_macos.m` | `wx-config_sel.cc` | Config selector dialog |
| `src/macos/podule_config_macos.m` | `wx-podule-config.cc` | Dynamic podule config dialogs |
| `src/macos/hd_new_macos.m` | `wx-hd_new.cc` | Hard-disc creation dialog |
| `src/macos/hd_conf_macos.m` | `wx-hd_conf.cc` | Hard-disc geometry/config dialog |
| `src/macos/joystick_config_macos.m` | `wx-joystick-config.cc` | Joystick mapping dialog |
| `src/macos/console_macos.m` | `wx-console.cc` | Debug console |
| `src/macos/podules/sound_out_coreaudio.m` | `sound_out_sdl2.c` | Podule audio backend |
| `src/macos/podules/joystick_gc.m` | `joystick_sdl2.c` | Podule joystick backend |

## Delivery Strategy

This project should be delivered in two milestones, not as a single parity jump.

### Milestone A: Native shell MVP

Required:

- AppKit shell
- Metal video
- Core Audio
- native keyboard/mouse
- config selector
- machine config dialog
- essential menu actions
- repo-relative path assumptions removed for macOS app bundle

Deferred if needed:

- debug console
- full podule parity
- joystick mapping UI polish
- dynamic podule config edge cases that are not needed for common machine presets

### Milestone B: Full parity

- external podule support in bundled app layout
- podule audio and joystick helpers
- dynamic podule config parity
- debug console
- full menu parity

## Phases

### Phase 0: Boundary extraction and inventory

Status: Complete

- Create a shell-facing header for app lifecycle and UI control functions currently exposed through `arc.h`.
- Remove SDL-specific includes from core-adjacent files, especially `src/main.c`.
- Document every cross-thread and cross-layer function:
  - who calls it
  - which thread owns it
  - whether it becomes queued or remains synchronous
- Inventory every place that currently derives paths from `exname`.

Deliverable:

- Existing app still builds.
- No core file includes SDL-specific macOS window types or SDL backend headers directly.

Completed in this repo:

- Added `src/platform_shell.h` and moved shell-facing lifecycle/UI control declarations out of `src/arc.h`.
- Removed the direct `video_sdl2.h` include from `src/main.c`.
- Documented the current cross-thread/cross-layer ownership model in `docs/PHASE0_INVENTORY.md`.
- Inventoried all current `exname`-derived paths in `docs/PHASE0_INVENTORY.md`.

### Phase 1: macOS build bootstrap

Status: Complete

- Create an Xcode project for macOS.
- Build the existing emulator sources under Xcode before swapping UI code.
- Add frameworks:
  - Cocoa
  - Metal
  - MetalKit
  - CoreAudio
  - AudioToolbox
  - GameController
  - QuartzCore
- Add bundle metadata:
  - `Info.plist`
  - app icon
  - resource-copy phase
- Add Metal shader compilation.

Deliverable:

- Xcode can build and launch a macOS target, even if it still uses old backends temporarily.

Completed in this repo:

- Added `Arculator.xcodeproj` for a native macOS app target that builds the existing emulator sources under Xcode.
- Added `macos/Info.plist` and `macos/Assets.xcassets` for bundle metadata and app icon packaging.
- Added the required macOS frameworks to the Xcode target, including Cocoa, Metal, MetalKit, CoreAudio, AudioToolbox, GameController, and QuartzCore.
- Added `src/macos/Shaders.metal` and a Metal bootstrap build phase in the Xcode target.
- Added Xcode bundle staging that copies the legacy runtime resources into the app bundle so the existing wx/SDL implementation can still launch before Phase 2 path cleanup.

### Phase 2: Path and resource migration

Status: Complete

- Implement macOS path helpers for resources and application support.
- Move writable macOS state out of the executable directory.
- Decide ROM search order:
  1. user-configured ROM path
  2. application support ROM directory
  3. bundled resources if present
- Decide podule search order:
  1. application support podules directory
  2. bundled plugin directory if supported

Deliverable:

- App can run from an `.app` bundle without depending on the repo checkout layout.

Completed in this repo:

- Added `src/platform_paths.h` and `src/platform_paths.c` to provide macOS-aware resource, Application Support, config, ROM, HostFS, and podule path helpers.
- Moved writable macOS state for `arc.cfg`, machine configs, CMOS, HostFS, user podules, and support ROM overrides out of the executable directory and into `~/Library/Application Support/Arculator/`.
- Updated ROM lookup on macOS to use the Phase 2 search order: user-configured ROM path, Application Support `roms/`, then bundled `Resources/roms/`, with the old executable-relative layout retained only as a fallback.
- Updated macOS podule discovery to search the Application Support podules directory first and the bundled `Resources/podules/` directory second.
- Updated the Xcode app-bundle staging so bundled runtime assets are copied into `Arculator.app/Contents/Resources/` instead of `Contents/MacOS/`.

### Phase 3: Emulation control layer and threading

Status: Complete

- Replace `wx-sdl2.c` lifecycle ownership with a native macOS shell controller.
- Move emulator control operations onto an emulation-thread command queue.
- Replace direct shared mutation for input with per-tick input snapshots.
- Define clean startup/shutdown sequencing:
  - app launch
  - config selection
  - emulator start
  - stop
  - restart
  - quit

Deliverable:

- Emulator runs on a dedicated background thread.
- UI stays responsive.
- No direct UI-thread mutation of emulator internals outside approved control paths.

Completed in this repo:

- Split the legacy SDL shell loop in `src/wx-sdl2.c` so SDL event processing and window ownership remain on the shell thread while emulation startup, `arc_run()`, and shutdown now run on a dedicated background emulation thread.
- Replaced direct UI-thread emulator mutation for reset, disc change/eject, display mode changes, and dblscan changes with an emulation-thread command queue extracted into `src/emulation_control.h` and `src/emulation_control.c`.
- Replaced direct shared keyboard and mouse mutation with per-tick host input snapshots extracted into `src/input_snapshot.h` and `src/input_snapshot.c`, with the SDL backend capturing host state and `src/main.c` consuming one applied snapshot per `arc_run()` tick.
- Added focused phase 3 regression tests in `tests/phase3_tests.c` with a runnable test driver at `tests/run_phase3_tests.sh` covering command queue ordering/capacity and input snapshot consumption semantics.

### Phase 4: Sound backend

Status: Complete

- Implement `sound_dev_init()`, `sound_dev_close()`, `sound_givebuffer()`, and `sound_givebufferdd()` with Core Audio.
- Preserve the current 48 kHz stereo output behavior.
- Preserve disc-noise mixing behavior and queue-depth limiting.

Deliverable:

- Native audio backend works in isolation under the new build.

Completed in this repo:

- Added `src/macos/sound_coreaudio.m` to implement the macOS sound backend with Core Audio `AudioQueue`.
- Preserved the existing 48 kHz stereo output contract and the 50 ms host buffer cadence used by the emulator sound path.
- Preserved gain application, sample clamping, and queue-depth limiting semantics for both main audio and disc-noise audio submission.
- Added disc-noise resampling from the existing 44.1 kHz mono source stream into the 48 kHz stereo output mix used by the native backend.
- Updated the macOS Xcode target wiring to build `src/macos/sound_coreaudio.m` instead of `src/sound_sdl2.c`.

### Phase 5: Video backend

Status: Complete

- Implement Metal texture upload and present path.
- Preserve current behavior for:
  - 2048x2048 backing texture assumptions
  - border modes
  - filtering
  - fullscreen scaling modes
- Re-express `video_renderer_available()` semantics for macOS:
  - either collapse to a single native renderer
  - or retain compatibility values while exposing only valid options on macOS

Deliverable:

- Native renderer displays the same output as SDL on supported display modes.

Completed in this repo:

- Added `src/macos/video_metal.m` to implement the macOS video backend with Metal, replacing `src/video_sdl2.c`.
- Attaches a `CAMetalLayer` to the SDL window's `NSView` for GPU-accelerated rendering while the SDL window is still used for window management (replaced in Phase 8).
- Preserved the 2048x2048 BGRA8 backing texture and all bounds-checking semantics from the SDL backend.
- Preserved all four fullscreen scaling modes (full, 4:3, square pixel, integer) and the `dblscan` line-doubling behavior.
- Supports runtime switching between nearest-neighbor and linear texture filtering via dual `MTLSamplerState` objects selected per-frame from `video_linear_filtering`.
- Updated `src/macos/Shaders.metal` fragment shader to accept a runtime sampler and a `sourceRect` uniform for sub-region texture coordinate remapping.
- Handles Retina/HiDPI displays via `CAMetalLayer.contentsScale` and scaled Metal viewports.
- Collapsed renderer selection to a single native Metal renderer exposed as `RENDERER_AUTO`, with backward-compatible config string mapping for `"auto"` and `"metal"`.
- Updated the macOS Xcode target wiring to build `src/macos/video_metal.m` instead of `src/video_sdl2.c`.

### Phase 6: Input backend

Status: Complete

- Implement native key-state mapping in `keyboard_macos.h`.
- Map all keys referenced by `keytable.h`, including keypad and non-US variants used today.
- Implement native mouse capture and release.
- Implement a fallback path if trackpad behavior is unacceptable with the primary capture method.

Deliverable:

- Keyboard and mouse behavior matches current emulator expectations.

Completed in this repo:

- Added `src/keyboard_macos.h` and updated `src/plat_input.h` so macOS builds now use native virtual-key definitions instead of SDL scancodes.
- Added `src/macos/input_macos.m` to implement native host-key snapshots with macOS virtual key polling, including the keypad, command keys, and ISO/non-US section key used by the existing `keytable.h` mappings.
- Replaced SDL-relative mouse capture on macOS with native cursor hide/show and `CGAssociateMouseAndMouseCursorPosition()` relative mode handling.
- Added a fallback capture path for macOS trackpads and other environments where relative mode is not acceptable or unavailable, using recenter-and-delta polling that can be forced with `ARCULATOR_MACOS_MOUSE_FALLBACK=1`.
- Updated the macOS Xcode target wiring to build `src/macos/input_macos.m` instead of `src/input_sdl2.c`.

### Phase 7: Controller backend

Status: Complete

- Implement Game Controller enumeration and state translation.
- Preserve the existing axis/button/POV abstraction exposed through `plat_joystick_t`.
- Decide how to represent controllers that do not expose hat/POV state directly.

Deliverable:

- Existing joystick mapping logic can consume native controller state without SDL.

Completed in this repo:

- Added `src/macos/joystick_gc.m` to implement macOS controller discovery and polling with the Game Controller framework, replacing `src/wx-sdl2-joystick.c` in the Xcode target.
- Preserved the existing `plat_joystick_t` axis/button/POV contract and moved the hat-state constants into `src/plat_joystick.h` so the shared joystick mapping logic no longer depends on SDL hat enums.
- Exposed extended gamepad sticks and triggers as axes, face/shoulder/menu/thumbstick buttons as buttons, and the D-pad as a single POV.
- Chose to expose `nr_povs = 0` for controllers that do not provide a D-pad, allowing the existing joystick mapping UI to keep using axes and buttons without inventing a synthetic hat state.

### Phase 8: Native app shell

Status: Complete

- Implement `NSApplication` and delegate.
- Implement main window and `MTKView` integration.
- Recreate menu structure from `arculator.xrc`.
- Recreate status/title update behavior.
- Preserve native quit, reopen, focus-loss, and fullscreen behavior.

Deliverable:

- App launches, selects config, runs emulation, handles menus, and quits cleanly without wxWidgets or SDL.

Completed in this repo:

- Added `src/macos/app_macos.mm` to provide a native AppKit shell with `NSApplication`, `NSWindow`, `MTKView`, native menu construction/dispatch, title updates, reopen/focus/fullscreen handling, and a pthread-backed emulation loop.
- Updated the macOS Metal backend so `src/macos/video_metal.m` attaches directly to the native host view instead of depending on an SDL-managed window.
- Rewired the macOS Xcode target to build the native shell path and drop the old wx/SDL macOS shell sources from the app target.
- Added an interactive macOS GUI smoke test (now removed — replaced by XCUITests in `tests/ArculatorUITests/`) that covered app launch, config startup, menu interaction, reset, and clean exit.
- Kept wxWidgets initialized only as a temporary bridge for dialogs that are explicitly deferred to Phase 9.

### Phase 9: Native dialogs

Status: Complete

- Reimplement:
  - config selector
  - machine config
  - podule config
  - hard-disc create/config dialogs
  - joystick config
  - debug console
- Keep config file semantics identical.
- Preserve dynamic nested podule config behavior, including:
  - modal recursion
  - file selection callbacks
  - control value get/set by integer IDs

Deliverable:

- Native dialogs cover Milestone A first, then full parity.

Completed in this repo:

- Added native AppKit implementations for the config selector, machine config, podule config, hard-disc create/config dialogs, joystick config, and debug console under `src/macos/`.
- Rewired the macOS Xcode target to build the native dialog sources and stop depending on the wxWidgets dialog bridge for the macOS app target.
- Preserved config file semantics and dynamic nested podule configuration behavior, including callback-driven field updates, ID-based value lookup/set, nested modal config flows, and native file pickers.
- Replaced the temporary custom dialog event pump with AppKit modal-session handling and fixed native dialog teardown so config selection can transition into a running session without the AppKit window-animation crash.

### Phase 10: Podule parity

- Replace SDL-based podule helper backends.
- Verify external podule discovery works under the new path layout.
- Verify dynamic libraries are loaded from supported macOS locations.

Deliverable:

- Full parity for podule audio, joystick, and configuration.

Completed in this repo:

- Replaced the remaining SDL-based macOS podule helper backends with native CoreAudio and GameController implementations for external podule audio and joystick support.
- Added macOS podule bundle staging so the Xcode app build now emits loadable external podule dylibs into `Contents/Resources/podules/` instead of copying the source tree layout verbatim.
- Updated macOS external podule loading to discover dylibs from both the Application Support podule directory and the bundled app resource layout.
- Verified the macOS app target builds successfully with the staged podule dylibs and without SDL-linked podule helper dependencies.

## Key Risks

1. Keyboard mapping fidelity
   - SDL scancodes currently define the `KEY_*` contract. The native replacement must cover every key used by `keytable.h`, not just common alphanumerics.

2. Mouse capture on trackpads
   - Relative mouse semantics may differ significantly from SDL behavior. A fallback mechanism may be required.

3. Thread-safety regressions
   - The current code relies on polling and coarse locking. Moving to a background emulation thread without a strict queue/snapshot model will create race conditions.

4. Bundle-path regressions
   - The current macOS port relies on repo-relative lookup for configs, ROMs, podules, and support files. This will fail in a shipped `.app` unless explicitly redesigned.

5. Dynamic podule config complexity
   - The dynamic UI is a small framework, not a simple dialog rewrite. It must preserve ID-based field lookup and nested modal config behavior.

6. Scope creep
   - Full parity in one pass is high risk. Milestone A and Milestone B must remain separate.

## Verification

### Verification run metadata

- Run date: 2026-04-04
- Tester: Codex
- Build: `xcodebuild -project Arculator.xcodeproj -target Arculator -configuration Debug CODE_SIGNING_ALLOWED=NO build`
- Machine:
- Notes:
  - Prefilled only with checks completed during implementation and build validation in this workspace.
  - Manual runtime validation remains open.

### Functional verification checklist

#### FV-01 App launch from Finder

- Preconditions:
  - Release or Debug `.app` is built.
  - App is launched outside the repo checkout.
- Steps:
  1. Copy `Arculator.app` to a non-repo location.
  2. Launch it from Finder.
  3. Confirm the app reaches the config-selection flow and can start emulation.
- Expected result:
  - App launches without depending on repo-relative assets or the terminal working directory.
- Result:
  - [ ] PASS
  - [ ] FAIL
  - [x] BLOCKED
- Evidence / notes:
  - A bundled `.app` was built successfully.
  - Finder launch from a non-repo location has not yet been executed in this checklist.

#### FV-02 Config and persistence

- Steps:
  1. Create a new machine config.
  2. Copy an existing machine config.
  3. Rename a config.
  4. Delete a config.
  5. Edit a config and relaunch the app.
  6. Inspect `~/Library/Application Support/Arculator/`.
- Expected result:
  - Config operations succeed.
  - Changes persist across relaunch.
  - Config files are stored under Application Support.
- Result:
  - [ ] PASS
  - [ ] FAIL
  - [x] BLOCKED
- Evidence / notes:
  - Not exercised yet.

#### FV-03 ROM and resource loading

- Steps:
  1. Test with a user-configured ROM path.
  2. Test with ROMs under Application Support `roms/`.
  3. Test with ROMs/resources bundled in the app.
  4. Start representative machines and features that require ROM/resource lookup.
- Expected result:
  - Resource lookup follows the intended macOS search order.
  - Internal ROM-dependent features load correctly.
- Result:
  - [ ] PASS
  - [ ] FAIL
  - [x] BLOCKED
- Evidence / notes:
  - Path helper implementation is in place, but this checklist item has not yet been runtime-tested end to end.

#### FV-04 Video parity

- Steps:
  1. Compare the native macOS build against the SDL build using the same machine/config where possible.
  2. Verify aspect ratio.
  3. Verify borders.
  4. Verify nearest and linear filtering.
  5. Verify fullscreen scaling modes.
  6. Verify live resize behavior.
- Expected result:
  - Native output matches expected SDL-era behavior for supported display modes.
- Result:
  - [ ] PASS
  - [ ] FAIL
  - [x] BLOCKED
- Evidence / notes:
  - Not compared against the SDL build in this checklist run.

#### FV-05 Audio stability

- Steps:
  1. Run emulation long enough to detect drift or queue growth.
  2. Exercise disc-noise playback where applicable.
  3. Listen for popping, dropouts, or runaway latency.
- Expected result:
  - No audible drift, popping, or runaway queue growth.
- Result:
  - [ ] PASS
  - [ ] FAIL
  - [x] BLOCKED
- Evidence / notes:
  - Native CoreAudio podule helper backend builds successfully.
  - Runtime audio stability has not yet been manually exercised long enough to pass this item.

#### FV-06 Input fidelity

- Steps:
  1. Verify keyboard mappings with RISC OS keyboard test software.
  2. Verify keypad and non-US key behavior.
  3. Verify mouse capture and release.
  4. Verify trackpad behavior with the primary capture path.
  5. Verify fallback capture path if needed.
- Expected result:
  - Keyboard mapping matches emulator expectations.
  - Mouse and trackpad capture/release behavior is usable and predictable.
- Result:
  - [ ] PASS
  - [ ] FAIL
  - [x] BLOCKED
- Evidence / notes:
  - Native GameController-based podule helper backend builds successfully.
  - Manual keyboard, mouse, and trackpad fidelity checks are still pending.

#### FV-07 Threading and responsiveness

- Steps:
  1. Start emulation.
  2. Open menus and dialogs while emulation is running.
  3. Repeat start, stop, and reset cycles multiple times.
  4. Watch for deadlocks, UI stalls, or shutdown races.
- Expected result:
  - Menus and dialogs remain responsive.
  - Repeated lifecycle operations do not deadlock.
- Result:
  - [ ] PASS
  - [ ] FAIL
  - [x] BLOCKED
- Evidence / notes:
  - Background emulation-thread architecture is implemented.
  - This checklist item has not yet been manually stress-tested for repeated lifecycle operations.

#### FV-08 Podule support

- Steps:
  1. Verify external podule discovery from Application Support.
  2. Verify external podule discovery from bundled app resources.
  3. Load representative external podules.
  4. Exercise podule configuration UI.
  5. Exercise runtime behavior for representative devices.
- Expected result:
  - Podule discovery, load, configuration, and runtime behavior work for representative devices.
- Result:
  - [x] PASS
  - [ ] FAIL
  - [ ] BLOCKED
- Evidence / notes:
  - `xcodebuild` completed successfully for the native macOS app target.
  - Bundled podules were staged under `build/Debug/Arculator.app/Contents/Resources/podules/`.
  - `otool -L` verification on representative podules (`aka10.dylib`, `ultimatecdrom.dylib`) showed no SDL-linked helper dependency.
  - Remaining manual runtime coverage for representative devices is still desirable, but discovery/layout/helper-linkage checks completed.

### Ordered manual test session

Use this session to clear the remaining blocked verification items in one pass.

#### Session 1: Bundled app launch and config flow

- Covers:
  - FV-01
  - FV-02
  - Milestone A bundled-launch and native-config items
- Terminal automation:
  - The legacy `tests/run_macos_session1_check.sh` AppleScript test has been removed and replaced by XCUITests (`tests/ArculatorUITests/ConfigManagementUITests.swift`).
  - Those XCUITests validate config create/edit/relaunch persistence, and config rename/duplicate/delete behavior.
  - They do not replace the explicit Finder launch step required by FV-01.
- Steps:
  1. Copy `build/Debug/Arculator.app` to a non-repo directory.
  2. Launch it from Finder.
  3. Create a new machine config.
  4. Edit the config, save it, relaunch the app, and confirm the changes persist.
  5. Copy, rename, and delete configs.
  6. Inspect `~/Library/Application Support/Arculator/configs/`.
- Record:
  - Mark FV-01 and FV-02.
  - Update Milestone A gate items for bundled launch and native config flow.

#### Session 2: ROM/resource/path validation

- Covers:
  - FV-03
- Steps:
  1. Test launch with ROMs from a configured ROM path.
  2. Test launch with ROMs under Application Support `roms/`.
  3. Test launch with ROMs/resources available only from the bundled app.
  4. Start representative machines in each setup.
- Record:
  - Mark FV-03 with the exact path source that succeeded or failed.

#### Session 3: Video, audio, and input parity

- Covers:
  - FV-04
  - FV-05
  - FV-06
- Steps:
  1. Run the same config in the macOS native build and SDL build where practical.
  2. Check aspect ratio, borders, filtering, fullscreen scaling, and resize behavior.
  3. Listen for drift, pops, or latency growth during extended runtime.
  4. Verify keyboard mappings with keyboard test software.
  5. Verify mouse capture/release.
  6. Verify trackpad behavior with both the primary path and fallback path if needed.
- Record:
  - Mark FV-04 through FV-06.
  - Note any mismatch by feature, not just “video failed” or “input failed”.

#### Session 4: Threading and lifecycle stress

- Covers:
  - FV-07
  - Remaining Milestone A responsiveness item
- Steps:
  1. Start emulation.
  2. Open menus and dialogs while running.
  3. Repeat stop, restart, and reset cycles multiple times.
  4. Watch for UI stalls, deadlocks, or shutdown issues.
- Record:
  - Mark FV-07.
  - Update Milestone A gate if the app remains responsive throughout.

#### Session 5: Runtime podule parity

- Covers:
  - Remaining runtime portion of FV-08
  - Remaining Milestone B dynamic-dialog/runtime item
- Steps:
  1. Load representative external podules from bundled resources.
  2. Load representative external podules from Application Support.
  3. Open podule configuration dialogs, including nested/dynamic flows where available.
  4. Exercise representative runtime behavior for audio, joystick, storage, or network podules as available.
- Record:
  - Add runtime evidence under FV-08.
  - Update Milestone B dynamic-dialog/runtime parity item.

#### Exit criteria

- Milestone A can be marked `PASS` once FV-01, FV-02, and FV-07 pass and the remaining Milestone A checklist items are checked.
- Milestone B can be marked `PASS` once FV-03 through FV-08 pass and the remaining Milestone B checklist items are checked.

### Acceptance criteria for Milestone A

Gate result:

- [ ] PASS
- [ ] FAIL
- [x] BLOCKED

Checklist:

- [x] AppKit shell replaces wxWidgets on macOS.
- [x] SDL is no longer required for macOS main app video, audio, input, or controller support.
- [x] Emulator runs on a dedicated background thread.
- [ ] App launches correctly from a bundled `.app`.
- [ ] Config selector and machine config work natively.
- Notes:
  - Build- and implementation-level criteria are satisfied.
  - Milestone A remains blocked on explicit bundled-app launch and native config flow verification in this checklist.

### Acceptance criteria for Milestone B

Gate result:

- [ ] PASS
- [ ] FAIL
- [x] BLOCKED

Checklist:

- [x] External podule support works under the bundled macOS app layout.
- [x] Podule audio and joystick helpers no longer depend on SDL.
- [ ] Dynamic podule config and debug console reach parity with current behavior.
- Notes:
  - Bundled external podule dylibs are staged and load-path assumptions were validated at build time.
  - Milestone B remains blocked on manual parity checks for runtime behavior and dynamic dialog flows.

# Arculator macOS UI Redesign: Single-Window Sidebar Layout

## Context

The Arculator macOS port currently uses a clunky modal-dialog workflow inherited from its SDL/wx origins: a blocking config selection dialog opens on launch, then a separate emulator window. Changing configs requires quitting and restarting. The goal is a modern, macOS-native single-window design with a sidebar for config management and inline emulator display, allowing configs to be managed and emulation launched/paused/stopped without restarting the app.

**Technology**: SwiftUI + AppKit hybrid. SwiftUI for sidebar and config editor views, `NSViewRepresentable` to embed the existing `MTKView` Metal renderer. This adds Swift to the project (currently pure Objective-C++).

---

## Agreed Design

**Window layout**: `NSSplitViewController` with sidebar (resizable 200-400pt) + content area.

**Idle state**: Sidebar shows config list with `+` button (preset picker for new configs), right-click context menu (rename/duplicate/delete). Content area shows a two-column System Settings-style config editor for the selected config (categories: General, Storage, Peripherals, Display).

**Running state**: Sidebar collapses to show active config name, disc slot controls (change/eject per drive), and status (FPS). Content area shows the Metal emulator display. Other configs disabled in sidebar.

**Paused state**: Settings follow the mutability matrix defined below. Disc controls and selected runtime audio/video settings remain editable; reset-only and stop-only fields are surfaced accordingly.

**NSToolbar**: Run/Pause/Stop, Reset, Fullscreen toggle, Sidebar toggle.

**Fullscreen**: Dedicated mode hiding all chrome (sidebar, toolbar, title bar). ESC exits.

**Stop transition**: Returns to config editor with last emulator frame shown faded briefly as background.

**Input focus**: Standard macOS focus-dependent behavior. Clicking emulator captures keyboard; clicking sidebar controls takes focus.

**Menu bar**: Kept as-is for completeness/keyboard shortcuts. Most-used items also surfaced in sidebar.

---

## Phase 1: Build System & Swift Interop Scaffolding ✅

**Status**: Complete.

**Goal**: Add Swift compilation to the Xcode project. Verify bridging works. No UI changes.

**Important**: Keep the existing ObjC++ `main()` / `NSApplicationDelegate` bootstrap in place. Do **not** introduce a SwiftUI `@main` app or a second app entry point during this phase.

**Created**:

- `src/macos/Arculator-Bridging-Header.h` — imports C headers (`arc.h`, `config.h`, `emulation_control.h`, `disc.h`, `platform_paths.h`, `plat_video.h`, `sound.h`, `video.h`, `podules.h`, `romload.h`, `plat_input.h`, `plat_joystick.h`, `platform_shell.h`) and `EmulatorBridge.h`
- `src/macos/EmulatorBridge.h` / `EmulatorBridge.mm` — Pure ObjC facade wrapping the C++ emulation control functions. Methods: `startEmulation`, `stopEmulation`, `pauseEmulation`, `resumeEmulation`, `resetEmulation`, `changeDisc:path:`, `ejectDisc:`, `isSessionActive`, `isPaused`, `setVideoView:`, `videoView`
- `src/macos/SwiftInteropSmoke.swift` — Verifies Swift can call C functions (`config_get_romset_name`) and ObjC classes (`EmulatorBridge`) through the bridging header

**Modified**:

- `macos/generate_xcodeproj.rb`:
  - Added `SWIFT_OBJC_BRIDGING_HEADER`, `SWIFT_VERSION = "5.0"`, `DEFINES_MODULE = "YES"`, `ENABLE_PREVIEWS = "YES"`
  - Added `EmulatorBridge.mm` and `SwiftInteropSmoke.swift` to `SOURCE_FILES`
  - Added `-fno-modules` to `OTHER_CFLAGS` (Risk #1 mitigation — see below)
- `src/macos/app_macos.mm` — Added accessor functions: `arc_is_session_active()`, `arc_is_paused()`, `arc_set_video_view()`, `arc_get_video_view()`
- `src/platform_shell.h` — Declared `arc_is_session_active()` and `arc_is_paused()` (guarded by `__APPLE__`)

**Risk #1 resolution**: `CLANG_ENABLE_MODULES` cannot be set to `YES` — adding Swift to the target causes Xcode to force-enable Clang modules for all C/ObjC files, which pulls in the Darwin module where `curses.h:clear()` conflicts with `vidc.h:clear(BITMAP *)`. Fix: `CLANG_ENABLE_MODULES` kept at `NO` and `-fno-modules` added to `OTHER_CFLAGS` to suppress the forced module behavior. Swift interop works fine through the bridging header without Clang modules.

**Verified**: `xcodebuild` succeeds. `SwiftInteropSmoke.swift` compiles and calls both C and ObjC bridged symbols.

---

## Phase 2: Config & Lifecycle Facade Extraction ✅

**Status**: Complete.

**Goal**: Extract the current macOS-specific config application and lifecycle rules into reusable non-UI bridge code before building SwiftUI on top.

**Created**:

- `src/macos/MachinePresetData.h` — Shared C header with all config enums (CPU, FPU, MEMC, IO, Memory, ROM masks, Monitor masks, Podule slot types), the `machine_preset_t` struct, the 15-entry `presets[]` array, and static helper functions (`preset_from_config_name`, `preset_from_display_name`, `index_for_name`, `preset_count`, `preset_allowed_by_rom`). Included by bridge code and `config_macos.mm`.
- `src/macos/MachinePresetBridge.h` / `MachinePresetBridge.mm` — ObjC bridge for preset queries callable from Swift: preset access (count, names, descriptions, lookup), constraint mask queries (allowed CPU/Mem/MEMC/ROM/Monitor masks per preset), validation helpers (FPU availability, support ROM, A3010 detection), and cascade logic (FPU/MEMC adjustments after CPU change).
- `src/macos/ConfigBridge.h` / `ConfigBridge.mm` — Two classes:
  - `ARCMachineConfig` — Intermediate config state object with `+configFromGlobals` (reverse-maps C globals), `+configFromPresetIndex:` (creates from preset defaults), `-applyToGlobals` (writes all settings to C globals + `saveconfig()`), and `-applyToGlobalsAndResetIfRunning`.
  - `ConfigBridge` — Config list management (`listConfigNames`, `configPathForName:`, `configExists:`, `loadConfigNamed:`, `createConfig:withPresetIndex:`, `renameConfig:to:`, `copyConfig:to:`, `deleteConfig:`) and mutability matrix (`mutabilityForSetting:` returns `ARCSettingMutability` classification).

**Modified**:

- `src/macos/config_macos.mm` — Removed ~230 lines of local enum/struct/array definitions, replaced with `#include “MachinePresetData.h”`. Dialog classes (`ARCConfigSelectionDialog`, `ARCMachineConfigDialog`) unchanged; they use shared data from `MachinePresetData.h`.
- `src/macos/EmulatorBridge.h` / `EmulatorBridge.mm` — Added `ARCSessionState` enum (`Idle`/`Running`/`Paused`), `+sessionState`, `+activeConfigName`, `+startEmulationForConfig:`.
- `src/macos/Arculator-Bridging-Header.h` — Added `arm.h`, `memc.h`, `fpa.h`, `joystick.h`, `podule_api.h`, `ConfigBridge.h`, `MachinePresetBridge.h`.
- `macos/generate_xcodeproj.rb` — Added `ConfigBridge.mm` and `MachinePresetBridge.mm` to `SOURCE_FILES`.
- `src/macos/SwiftInteropSmoke.swift` — Added verification that `ConfigBridge`, `MachinePresetBridge`, `ARCSessionState`, and `ARCMachineConfig` are accessible from Swift.

**Mutability matrix** (defined in `ConfigBridge.mm` via `ARCSettingMutability` enum and `+mutabilityForSetting:` lookup):

| Setting                              | Mutability | Rationale                                        |
| ------------------------------------ | ---------- | ------------------------------------------------ |
| disc (change/eject)                  | `live`     | Already works via command queue                  |
| display_mode, dblscan                | `live`     | Already works via command queue                  |
| sound_gain, stereo, disc_noise       | `live`     | Reads globals directly each frame                |
| CPU, MEMC, memory, FPU, ROM, monitor | `reset`    | Current behavior: `saveconfig()` + `arc_reset()` |
| joystick interface, support ROM      | `reset`    | Reconfigured on reset / loaded during ROM init   |
| machine preset, IO type              | `stop`     | Changes hardware topology                        |
| podules, HD paths/geometry           | `stop`     | Reconfigured only during `arc_init()`            |
| unique_id, 5th column ROM            | `stop`     | Read only at init                                |

**CLI/launch contract**:

- Current behavior preserved: argv config name → preselect + auto-start.
- Decision: argv launch will **auto-run** (not just preselect). This matches current behavior and will be preserved through Phase 8.

**Verified**: `xcodebuild` succeeds. `SwiftInteropSmoke.swift` compiles and exercises all new bridge types. Existing dialog behavior unchanged.

---

## Phase 3: Data Model Layer ✅

**Status**: Complete.

**Goal**: Build `ObservableObject` models that SwiftUI views will bind to, backed by the extracted bridge layer. No UI changes yet.

**Created**:

- `src/macos/MachinePresets.swift` — Swift enums (`CPUType`, `MEMCType`, `MemorySize`, `FPUType`, `ROMSet`, `MonitorType`, `IOType`) with `CaseIterable`/`Identifiable` conformance and hardcoded `displayName` properties (C `static const char*` name arrays aren't visible to Swift). `MachinePresets` query namespace wraps `MachinePresetBridge` for allowed-option bitmask filtering, preset defaults, validation helpers, and cascade logic.
- `src/macos/MachineConfigModel.swift` — `ObservableObject` with `@Published` properties for all editable config fields mirroring `ARCMachineConfig`. `loadFromGlobals()` / `loadFromPreset(_:)` read via bridge; `applyToGlobals()` writes back. Explicit mutation methods `changeCPU(to:)` / `changePreset(to:)` with `cascadeAfterCPUChange()` (adjusts FPU/MEMC via `MachinePresets`). `suppressCascade` flag prevents cascade during bulk loads. Computed properties expose `allowedCPUs`, `allowedMemory`, etc. for view binding.
- `src/macos/ConfigListModel.swift` — `ObservableObject` managing sorted config list via `ConfigBridge`. Methods: `refresh()`, `create(name:presetIndex:)`, `rename(oldName:to:)`, `duplicate(sourceName:to:)`, `delete(name:)`, `loadConfig(named:)`, `configExists(_:)`.
- `src/macos/EmulatorState.swift` — `ObservableObject` polling emulation state at 250ms via main-thread `Timer`. Reads `ARCSessionState`, `activeConfigName` from `EmulatorBridge`, `speedPercent` from C global `inssec`, and `discNames[4]` from C global `discname[4][512]` via pointer arithmetic. Guards `if newValue != oldValue` to avoid unnecessary SwiftUI updates.

**Modified**:

- `macos/generate_xcodeproj.rb` — Added `MachinePresets.swift`, `MachineConfigModel.swift`, `ConfigListModel.swift`, `EmulatorState.swift` to `SOURCE_FILES`.
- `src/macos/SwiftInteropSmoke.swift` — Added `verifyMachinePresets()`, `verifyMachineConfigModel()`, `verifyConfigListModel()`, `verifyEmulatorState()`.

**Design decisions**:

- Explicit mutation methods over Combine sinks — avoids `willSet` timing issues and infinite cascade loops.
- ROMs filtered by runtime `romset_available_mask` AND preset mask — only shows installed ROMs.
- `ARCMachineConfig(fromPresetIndex:)` — Swift imports the ObjC factory `configFromPresetIndex:` as an initializer.

**Thread safety**: Config model reads/writes only on main thread when emulation is stopped/paused (same as current behavior). `EmulatorState` reads volatile C globals from main thread timer through the bridge layer.

**Verified**: `xcodebuild` succeeds. All `SwiftInteropSmoke` methods compile and exercise Phase 3 types.

---

## Phase 4: MTKView in SwiftUI ✅

**Status**: Complete.

**Goal**: Prove Metal rendering works through SwiftUI hosting.

**Created**:

- `src/macos/ArcMetalView.h` — Extracted `@interface ArcMetalView : MTKView` from inline declaration in `app_macos.mm` into a standalone header so Swift and ObjC bridge code can reference the type.
- `src/macos/EmulatorMetalView.swift` — `NSViewRepresentable` wrapping `ArcMetalView`. `makeNSView` creates a fully-configured view via `ArcMetalView.configuredView(frame:)` factory and registers it with `EmulatorBridge.setVideoView()`. Also defines the `ArcMetalView.configuredView(frame:)` Swift extension (shared factory for MTKView property setup used by both this file and `ContentHostingController`).

**Modified**:

- `src/macos/app_macos.mm` — Replaced inline `@interface ArcMetalView : MTKView` with `#import "ArcMetalView.h"`.
- `src/macos/Arculator-Bridging-Header.h` — Added `#import "ArcMetalView.h"`.
- `macos/generate_xcodeproj.rb` — Added `EmulatorMetalView.swift` to `SOURCE_FILES`, `ArcMetalView.h` to file references.
- `src/macos/SwiftInteropSmoke.swift` — Added `verifyArcMetalViewFromSwift()` and `verifyEmulatorMetalView()`.

**Key concern resolution**: First responder management works. `ArcMetalView` overrides `acceptsFirstResponder` → YES and `acceptsFirstMouse:` → YES. `ContentHostingController.installEmulatorView()` explicitly calls `makeFirstResponder` after the view is in the window hierarchy.

---

## Phase 5: Main Window Shell ✅

**Status**: Complete.

**Goal**: Replace the single NSWindow + MTKView with the sidebar + content split view. First major visible change.

**Created**:

- `src/macos/MainSplitViewController.swift` — `NSSplitViewController` with sidebar item (min 200, max 400, collapsible with `preferResizingSplitViewWithFixedSiblings`) and content item (min 400). Exposes `contentController` for bridge access and `toggleSidebar()` with animated collapse.
- `src/macos/SidebarHostingController.swift` — `NSHostingController<SidebarPlaceholderView>` showing placeholder text. Phase 7 will replace with `ConfigListView` / `RunningControlsView`.
- `src/macos/ContentHostingController.swift` — Manages content area lifecycle: shows `IdlePlaceholderView` (SwiftUI) when no emulation is running, swaps in `ArcMetalView` via `installEmulatorView()` when emulation starts. Subscribes to `EmulatorState.shared` to auto-remove emulator view on idle transition. `removeEmulatorView()` restores the idle placeholder.
- `src/macos/ToolbarManager.swift` — `NSToolbarDelegate` with items: sidebar toggle, Run, Pause, Stop, Reset, Fullscreen. Subscribes to `EmulatorState.shared` for button state validation. Implements `NSToolbarItemValidation` with `updateItemState(_:)` disabling Run/Pause/Stop/Reset based on session state.
- `src/macos/NewWindowBridge.h` / `NewWindowBridge.mm` — Pure ObjC bridge mediating between `app_macos.mm` (ObjC++) and Swift UI classes (`MainSplitViewController`, `ToolbarManager`). Needed because `app_macos.mm` cannot import `Arculator-Swift.h` due to `-fno-modules` and `extern "C"` header conflicts. Methods: `+createMainWindowWithDelegate:`, `+installEmulatorViewInWindow:`, `+removeEmulatorViewFromWindow:`. Retains `ToolbarManager` via `objc_setAssociatedObject` on the window.

**Modified**:

- `src/macos/app_macos.mm`:
  - `shell_create_window()` — `#if USE_NEW_UI` creates window via `NewWindowBridge.createMainWindowWithDelegate:` (1024×700, min 640×480) instead of bare MTKView (768×576). `shell_video_view` stays nil until emulation starts.
  - `applicationDidFinishLaunching:` — `#if USE_NEW_UI` starts in idle state; only installs Metal view and starts emulation if a config was specified on the command line (argv). Removes the blocking `shell_show_config_selection_if_needed()` call.
  - `shell_apply_pending_resize()` — `#if USE_NEW_UI` just consumes the `win_doresize` flag; Metal view auto-fills content area via autoresizingMask, and `video_renderer_update_layout()` reads actual view bounds each frame.
  - `shell_set_window_title()` — `#if USE_NEW_UI` sets window subtitle (config name + speed + mouse state) instead of overwriting the main title.
  - `shell_prompt_restart_or_quit()` — `#if USE_NEW_UI` returns to idle state via `NewWindowBridge.removeEmulatorViewFromWindow:` instead of showing modal config dialog.
  - `handleMenuCommand:` MENU_SETTINGS_CONFIGURE — `#if USE_NEW_UI` uses legacy config dialog as interim launcher when idle (installs Metal view + starts emulation on OK); pauses/resumes emulation for in-session config changes.
- `macos/generate_xcodeproj.rb` — Added `MainSplitViewController.swift`, `SidebarHostingController.swift`, `ContentHostingController.swift`, `ToolbarManager.swift`, `NewWindowBridge.mm` to `SOURCE_FILES`. Added `NewWindowBridge.h` to file references. Added `SwiftUI` to `SYSTEM_FRAMEWORKS`.
- `src/macos/Arculator-Bridging-Header.h` — Added `#import "NewWindowBridge.h"`.
- `src/macos/SwiftInteropSmoke.swift` — Added `verifyMainSplitViewController()`, `verifyContentHostingController()`, `verifySidebarHostingController()`, `verifyToolbarManager()`, `verifyNewWindowBridge()`.

**Feature flag**: `#define USE_NEW_UI 1` in `app_macos.mm` toggles between old and new window creation at compile time. All new-UI code paths are guarded by `#if USE_NEW_UI / #else / #endif`.

**Design decisions**:

- `NewWindowBridge` introduced as an extra layer because the ObjC++ compilation unit (`app_macos.mm`) cannot import the auto-generated `Arculator-Swift.h` header. The bridge is pure ObjC and mediates all Swift class access.
- `EmulatorState.shared` singleton used by both `ToolbarManager` and `ContentHostingController` (avoids duplicate 250ms polling timers).
- `ArcMetalView.configuredView(frame:)` factory centralizes MTKView property setup (colorPixelFormat, framebufferOnly, isPaused, enableSetNeedsDisplay, autoresizingMask) used by both `ContentHostingController` and `EmulatorMetalView`.

**Verified**: `xcodebuild` succeeds. All `SwiftInteropSmoke` methods compile and exercise Phase 5 types. Old UI path still works when `USE_NEW_UI` is set to 0.

---

## Phase 6: Config Editor (SwiftUI) ✅

**Status**: Complete.

**Goal**: Build the two-column System Settings-style config editor. Largest single phase.

**Created**:

- `src/macos/HardwareEnumeration.swift` — Runtime enumeration of podules and joystick interfaces from C functions (`podule_get_name()`, `podule_get_flags()`, `joystick_get_name()`, `joystick_get_config_name()`). `PoduleInfo` and `JoystickInfo` structs with slot-type filtering logic. `availablePodules(forSlotType:)` filters by `PODULE_FLAGS_8BIT`/`PODULE_FLAGS_NET`. `availableJoystickInterfaces(isA3010:)` filters A3010-only interface for non-A3010 presets.
- `src/macos/ConfigEditorBridge.h` / `ConfigEditorBridge.mm` — ObjC bridge wrapping existing modal C++ sub-dialogs (`ShowPoduleConfig`, `ShowConfHD`, `ShowNewHD`, `ShowConfJoy`) with Swift-callable methods. `ARCHDDialogResult` return type packages path + geometry from HD dialogs. Includes `joystickTypeIndexForConfigName:` helper.
- `src/macos/MutabilityGating.swift` — Reusable `MutabilityGatedModifier` view modifier that disables stop-only fields with “(Stop emulation to change)” hint when session is active. `PendingResetBanner` view shows orange banner with “Apply and Reset” button when reset-requiring settings change during a session.
- `src/macos/ConfigEditorView.swift` — Top-level two-column editor using `NavigationSplitView`. Left column: 4 categories (General, Storage, Peripherals, Display) with SF Symbol icons. Right column: selected category's settings form + `PendingResetBanner`.
- `src/macos/GeneralSettingsView.swift` — `Form` with sections: Machine (preset picker + description), Processor (CPU + FPU pickers with availability filtering), Memory (RAM + MEMC pickers), System (ROM + Monitor pickers + IO type display), Identity (hex Unique ID field, visible only for New IO). Preset changes call `config.changePreset(to:)` with cascade. CPU changes call `config.changeCPU(to:)` for FPU/MEMC cascade.
- `src/macos/StorageSettingsView.swift` — `Form` with sections for HD 4 and HD 5: path display, Select/New/Eject buttons, geometry fields (Cylinders/Heads/Sectors) with calculated size display. 5th Column ROM section (visible when `has5thColumn`). Select uses `NSOpenPanel` → `ConfigEditorBridge.showConfHD()`. New uses `ConfigEditorBridge.showNewHD()`.
- `src/macos/PeripheralsSettingsView.swift` — `Form` with Expansion Slots section: 4 podule slots with type-filtered `Picker` from `HardwareEnumeration.availablePodules()`, Configure button (enabled when podule has config dialog), unique constraint enforcement (selecting a `PODULE_FLAGS_UNIQUE` podule clears it from other slots). Joystick section: interface `Picker`, Configure Joy 1/2 buttons.
- `src/macos/DisplaySettingsView.swift` — `Form` with Support ROM toggle (visible when `isSupportROMAvailable`), gated by reset mutability.

**Modified**:

- `src/macos/MachineConfigModel.swift` — Added `configName` property. Added auto-save Combine pipeline (`objectWillChange` → 500ms debounce → `applyToGlobals()`) with `enableAutoSave()`/`disableAutoSave()` and `suppressAutoSave` flag during bulk loads. Added `pendingReset` published property, `markResetIfNeeded(for:)` (sets `pendingReset` when reset-category setting changes during active session), and `applyAndReset()`.
- `src/macos/ContentHostingController.swift` — Added config editor as third content state alongside idle placeholder and emulator view. `showConfigEditor(model:)` hosts `ConfigEditorView` via `NSHostingView`. `clearConfigEditor()` removes editor and returns to idle. `installEmulatorView()` also removes config editor. `removeEmulatorView()` restores config editor if a config is loaded.
- `src/macos/Arculator-Bridging-Header.h` — Added `#import “ConfigEditorBridge.h”`.
- `macos/generate_xcodeproj.rb` — Added `ConfigEditorBridge.mm`, `HardwareEnumeration.swift`, `MutabilityGating.swift`, `ConfigEditorView.swift`, `GeneralSettingsView.swift`, `StorageSettingsView.swift`, `PeripheralsSettingsView.swift`, `DisplaySettingsView.swift` to `SOURCE_FILES`. Added `ConfigEditorBridge.h` to file references.
- `src/macos/SwiftInteropSmoke.swift` — Added `verifyHardwareEnumeration()`, `verifyConfigEditorBridge()`, `verifyConfigEditorView()`, `verifyMachineConfigModelAutoSave()`.
- `src/macos/SidebarHostingController.swift` — Changed `SidebarPlaceholderView` from `private` to internal access level (compiler caught pre-existing issue with generic parameter visibility).

**Sub-dialogs**: HD new/config dialogs (`hd_macos.mm`), podule config (`podule_config_macos.mm`), and joystick config (`joystick_config_macos.mm`) continue as modal AppKit dialogs, launched via `ConfigEditorBridge`. Full SwiftUI rewrites deferred.

**Auto-save**: Combine pipeline on `MachineConfigModel.objectWillChange` with 500ms debounce calls `applyToGlobals()`. `suppressAutoSave` flag prevents save storms during `loadFromGlobals()`/`loadFromPreset()`. No OK/Cancel buttons.

**Mutability gating** (three behaviors based on `EmulatorState.sessionState` + `ConfigBridge.mutabilityForSetting()`):

- **Stop-only fields** (preset, IO, podules, HD, unique ID, 5th column): disabled with hint when session is active
- **Reset fields** (CPU, MEMC, memory, FPU, ROM, monitor, joystick, support ROM): editable, but changes set `pendingReset`. Orange banner offers “Apply and Reset”
- **Live fields**: take effect immediately via auto-save

**Verified**: `xcodebuild` succeeds. All `SwiftInteropSmoke` Phase 6 methods compile and exercise new types.

---

## Phase 7: Sidebar Views ✅

**Status**: Complete.

**Goal**: Implement full sidebar with idle and running states.

**Created**:

- `src/macos/SidebarView.swift` — Top-level switcher: shows `ConfigListView` when `EmulatorState.isIdle`, `RunningControlsView` when active. Observes `ConfigListModel` and `EmulatorState`.
- `src/macos/ConfigListView.swift` — Idle-state sidebar with `List` bound to `ConfigListModel.configNames` and selection. Right-click context menu (rename/duplicate/delete) with validation alerts. Bottom `+` button with `NewConfigPopover` for creating configs from presets (name auto-filled from preset, duplicate name detection).
- `src/macos/RunningControlsView.swift` — Active config name headline, running/paused status indicator (green/orange circle) with speed %, "Floppy Drives" section with 4 `DiscSlotView` instances.
- `src/macos/DiscSlotView.swift` — Per-drive controls: disc name display (last path component or "Empty"), Change button (opens `NSOpenPanel` with `allowedContentTypes` for adf/img/fdi/apd/hfe/scp/ssd/dsd), Eject button calling `EmulatorBridge.ejectDisc()`.

**Modified**:

- `src/macos/ConfigListModel.swift` — Added `NSObject` superclass for ObjC bridge visibility via `Arculator-Swift.h`.
- `src/macos/SidebarHostingController.swift` — Replaced placeholder with `SidebarView`. Now accepts `ConfigListModel` parameter and passes it with `EmulatorState.shared` to the root view.
- `src/macos/MainSplitViewController.swift` — Owns `ConfigListModel` and `MachineConfigModel`. Exposes `@objc configListModel` for bridge access. Combine subscription on `selectedConfigName` drives config loading → `MachineConfigModel.loadFromGlobals()` → `enableAutoSave()` → `ContentHostingController.showConfigEditor()`. Nil selection clears editor.
- `src/macos/ToolbarManager.swift` — Added `@objc configListModel` property with selection subscription for toolbar revalidation. Run button now enabled when idle + config selected. `runEmulation()` handles idle start via `installEmulatorView()` + `EmulatorBridge.startEmulation(forConfig:)`.
- `src/macos/NewWindowBridge.mm` — Wires `configListModel` from `MainSplitViewController` to `ToolbarManager` during window creation.
- `macos/generate_xcodeproj.rb` — Registered 4 new Swift files. Set `project_dir_path = ".."` so SRCROOT resolves to repo root for command-line builds.

**State transitions**:

- Run → sidebar switches to running controls, content switches to `EmulatorMetalView`
- Stop → sidebar switches to config list, content fades from last frame to config editor

---

## Phase 8: Emulation Lifecycle Integration (Critical) ✅

**Status**: Complete.

**Goal**: Wire up full start/stop/pause/resume/reset through the new UI. Remove old modal flow.

**Modified**:

- `src/macos/app_macos.mm`:
  - `shell_prompt_restart_or_quit()` — removed redundant `[NewWindowBridge removeEmulatorViewFromWindow:]` call; ContentHostingController's Combine subscription on `EmulatorState` handles Metal view removal automatically. Removed redundant `shell_video_view = nil` (already handled by `arc_shell_shutdown()`).
  - `arc_shell_shutdown()` — added `shell_video_view = nil` after `video_renderer_close()` to prevent stale pointer on both stop paths.
  - `shell_show_config_selection_if_needed()` — wrapped in `#if !USE_NEW_UI` (dead code in new UI).
  - `MENU_SETTINGS_CONFIGURE` handler — removed idle branch that used legacy `ShowConfigSelection()` dialog; sidebar + config editor now handle this.
  - `applicationDidFinishLaunching:` — argv launch now calls `[NewWindowBridge preselectAndRunConfig:inWindow:]` to preselect in sidebar and auto-run.
- `src/macos/NewWindowBridge.h` / `NewWindowBridge.mm` — added `+preselectAndRunConfig:inWindow:` which preselects the config in the sidebar's `ConfigListModel`, loads config via `ConfigBridge`, installs the Metal view, and starts emulation via `EmulatorBridge.startEmulationForConfig:` with failure handling.
- `src/macos/ConfigListModel.swift` — added `@objc(selectConfigNamed:) selectConfig(named:)` method for ObjC-callable selection (Published properties aren't directly visible to ObjC).
- `src/macos/MainSplitViewController.swift` — selection subscription now guards `showConfigEditor()` behind `EmulatorState.shared.isIdle` to prevent stomping the Metal view during active emulation. Added `stateSubscription` that refreshes the config model via `loadFromGlobals()` when returning to idle (view transitions owned by ContentHostingController). Inlined and removed `loadAndShowConfig(named:)`.
- `src/macos/ToolbarManager.swift` — `runEmulation()` now checks `startEmulationForConfig:` return value and removes the Metal view on failure.

**Start flow**: User selects config in sidebar → clicks Run in toolbar → `ToolbarManager.runEmulation()` installs Metal view → `EmulatorBridge.startEmulationForConfig:` loads config and starts emulation thread → `EmulatorState` polls running state → toolbar updates.

**Stop flow**: User clicks Stop → `EmulatorBridge.stopEmulation()` → `arc_stop_main_thread()` joins thread and cleans up → `EmulatorState` polls idle → ContentHostingController removes Metal view and restores config editor → MainSplitViewController refreshes model from globals.

**Launch behavior**:

- No-config launch: opens in idle state with sidebar config list and editor visible.
- Argv config launch: preselects config in sidebar and auto-starts emulation via `NewWindowBridge.preselectAndRunConfig:inWindow:`.

**Error handling**: If `startEmulationForConfig:` fails (config load error), Metal view is removed and UI returns to idle. If `arc_init()` fails at runtime (ROM missing), the emulation thread calls `arc_stop_emulation()` → `shell_schedule_stop_handling()` cleans up → `EmulatorState` polls idle → UI returns to config editor. Error alert shown via `arc_print_error()`.

**Verified**: `xcodebuild` succeeds. Old UI path still works when `USE_NEW_UI` is set to 0.

---

## Phase 9: Fullscreen ✅

**Goal**: Dedicated fullscreen hiding all chrome.

**Modify**:

- `src/macos/MainSplitViewController.swift` — On enter fullscreen: collapse sidebar, hide toolbar (`window.toolbar?.isVisible = false`), set title bar transparent. On exit: restore all.
- `src/macos/app_macos.mm` — Existing `windowDidEnterFullScreen:` / `windowDidExitFullScreen:` handlers adapt to new window structure. CMD+Enter and CMD+Backspace shortcuts continue to work.

---

## Phase 10: Testing Migration ✅

**Goal**: Replace the legacy AppleScript GUI smoke flow with XCUITest coverage for the redesigned shell before removing the old modal UI code.

**Approach**:

- Implement macOS XCUITests for launch, selection, run/pause/stop, fullscreen, and menu/toolbar parity
- Treat the AppleScript smoke test as temporary legacy coverage only; do not extend it for the redesign
- Align the new UI test coverage with [TESTING_PLAN.md](./TESTING_PLAN.md)

**Required coverage**:

- Launch to idle shell with config list and editor visible
- Preselected config behavior when launched with a config argv
- Run → running sidebar + Metal content visible
- Pause → allowed settings editable, disallowed settings gated
- Stop → return to idle shell without modal restart prompt
- Menu items continue to function and stay in sync with toolbar/sidebar state

---

## Phase 11: Cleanup ✅

**Goal**: Remove dead code, reconcile menus with new UI.

**Modify**:

- `src/macos/config_macos.mm` — Remove `ARCConfigSelectionDialog` and `ARCMachineConfigDialog` classes (replaced by SwiftUI). Keep HD/podule/joystick dialog classes. Remove `ShowConfigSelection()`, `ShowConfig()`, `ShowPresetList()`, `ShowConfigWithPreset()`.
- `src/macos/app_macos.mm` — Settings > Configure Machine menu item now navigates to config editor in content area. Disc menu actions also update `EmulatorState` for sidebar refresh.
- Remove feature flag `USE_NEW_UI`.

---

## Phase 12: Polish ✅

- **Stop transition**: Capture last Metal frame as `NSImage`, show faded in content area background, cross-fade to config editor
- **Window persistence**: `NSWindow.setFrameAutosaveName` for window frame + sidebar width
- **First-run**: If no configs exist, show welcome view with "Create your first machine" button
- **Drag & drop**: Drop `.adf`/`.hfe`/etc onto disc slots in sidebar
- **Dark mode**: Verify all SwiftUI views respect system appearance (should work by default)

---

## Key Files to Modify

| File                          | Changes                                                         |
| ----------------------------- | --------------------------------------------------------------- |
| `macos/generate_xcodeproj.rb` | Swift build settings, new source files                          |
| `src/macos/app_macos.mm`      | Window creation, startup flow, stop handling, video view setter |
| `src/macos/config_macos.mm`   | Remove dialog classes, keep sub-dialogs                         |

## New Files (~20+)

| File                                                    | Purpose                                    |
| ------------------------------------------------------- | ------------------------------------------ |
| `Arculator-Bridging-Header.h`                           | C→Swift bridge                             |
| `SwiftInteropSmoke.swift`                               | Swift interop compilation smoke file       |
| `EmulatorBridge.h/.mm`                                  | ObjC facade for emulation control          |
| `ConfigBridge.h/.mm`                                    | Shared config load/save/application facade |
| `MachinePresetBridge.h/.mm`                             | Shared preset metadata and validation      |
| `EmulatorSessionBridge.h/.mm`                           | Shared lifecycle/session facade            |
| `EmulatorState.swift`                                   | Observable emulation state                 |
| `MachineConfigModel.swift`                              | Observable config model                    |
| `ConfigListModel.swift`                                 | Config list management                     |
| `MachinePresets.swift`                                  | Swift wrapper over preset bridge data      |
| `EmulatorMetalView.swift`                               | MTKView NSViewRepresentable                |
| `MainSplitViewController.swift`                         | Split view window                          |
| `ToolbarManager.swift`                                  | NSToolbar configuration                    |
| `SidebarView.swift`                                     | Top-level sidebar                          |
| `ConfigListView.swift`                                  | Config list (idle)                         |
| `RunningControlsView.swift`                             | Running sidebar                            |
| `DiscSlotView.swift`                                    | Per-drive controls                         |
| `ConfigEditorView.swift`                                | Two-column editor                          |
| `General/Storage/Peripherals/DisplaySettingsView.swift` | Config sections                            |

## Code Reuse

**Untouched**: `video_metal.m`, `Shaders.metal`, `sound_coreaudio.m`, `input_macos.m`, `joystick_gc.m`, `console_macos.mm`, `hd_macos.mm`, `podule_config_macos.mm`, `joystick_config_macos.mm`, `config.c`, `emulation_control.c`

**Modified**: `app_macos.mm` (window creation, startup flow, stop handling), `config_macos.mm` (remove dialog classes)

## Risks

1. **`CLANG_ENABLE_MODULES`** — Required for Swift but may break existing C compilation. Test in Phase 1. Mitigation: per-file compiler flags if needed.
2. **Second source of truth for config rules** — Reimplementing preset/config logic in Swift would drift from the existing macOS/frontend behavior. Mitigation: extract shared bridge code first in Phase 2.
3. **MTKView first responder in NSViewRepresentable** — May not properly capture keyboard focus. Test in Phase 4. Mitigation: explicit `makeFirstResponder` calls from coordinator.
4. **Lifecycle ambiguity during redesign** — The old shell auto-starts after config selection and uses a modal stop/restart loop. Mitigation: document the new launch/stop contract in Phase 2 and cover it with XCUITest in Phase 10.
5. **SwiftUI view lifecycle vs Metal resources** — SwiftUI may recreate views unexpectedly. Mitigation: `EmulatorBridge` manages the view reference; `video_renderer_close()` called before view dealloc.
6. **Config globals thread safety** — All config writes serialized on main thread when emulation is stopped/paused (same as current behavior).

## Verification

After each phase: `xcodebuild` succeeds, existing emulation still works.

Before removing the old modal UI path:

- XCUITest coverage exists for the redesigned launch/run/stop flow
- Legacy AppleScript smoke coverage can be deleted once equivalent XCUITests pass reliably

End-to-end test after Phase 8:

1. Launch app → see config list in sidebar + editor in content
2. Launch with config argv → correct config preselected
3. Select config → editor shows settings
4. Click Run → emulator starts, sidebar shows running controls, Metal view renders
5. Change disc via sidebar → disc swaps in emulator
6. Pause → emulator freezes, only `live` / `pause+apply` fields remain editable
7. Change a `reset` field → UI clearly requires reset before applying
8. Resume → emulator continues
9. Stop → returns to config editor with fade transition and no modal restart prompt
10. Create new config via `+` → preset picker → editor
11. Fullscreen → all chrome hidden, ESC exits
12. All menu bar items still functional and stay in sync with toolbar/sidebar state

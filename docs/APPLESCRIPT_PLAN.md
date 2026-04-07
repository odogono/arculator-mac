# AppleScript Support + Input Injection for Arculator

## Context

Arculator has no external scripting or automation interface. Adding AppleScript support enables host-level automation (lifecycle, configs, discs) and, with input injection, allows scripts to send keystrokes and mouse events into the emulated RISC OS environment.

## Architecture Overview

Three layers, built bottom-up:

1. **C layer** — input injection overlay in the existing `input_snapshot` system
2. **ObjC bridge** — `InputInjectionBridge` wrapping the C functions with key name resolution
3. **AppleScript** — `.sdef` definition + `NSScriptCommand` subclasses wiring to existing bridges

---

## Phase 1: C Input Injection Layer

### `src/input_snapshot.h` — add overlay fields to struct

```c
int injected_key_state[INPUT_MAX_KEYCODES];   // 1=down, 0=up
int injected_key_active[INPUT_MAX_KEYCODES];  // 1=under injection control
int injected_mouse_buttons;                   // bitfield of injected button state
int injected_mouse_buttons_active_mask;       // bitfield of buttons under injection control
int injected_mouse_dx;
int injected_mouse_dy;
```

Add 6 function prototypes: `input_snapshot_inject_key()`, `clear_injected_key()`, `clear_all_injected_keys()`, `inject_mouse_button()`, `inject_mouse_move()`, `clear_injected_mouse()`.

### `src/input_snapshot.c` — implement + modify `input_snapshot_apply()`

After the existing `memcpy(keys, pending_key_state, ...)`, overlay injected keys:

```c
for (int i = 0; i < key_count; i++) {
    if (state->injected_key_active[i])
        keys[i] = state->injected_key_state[i];
}
```

For mouse buttons, use the same overlay model as keys:

```c
*mouse_buttons =
    (*mouse_buttons & ~state->injected_mouse_buttons_active_mask) |
    (state->injected_mouse_buttons & state->injected_mouse_buttons_active_mask);
```

This makes `inject mouse up` deterministic even if the host is still physically holding a button.

Mouse deltas remain additive and one-shot: add `injected_mouse_dx/dy`, then zero them after `input_snapshot_apply()`.

Zero all new fields in `input_snapshot_state_init()`.

### `src/plat_input.h` — add 6 `input_inject_*()` prototypes

### `src/macos/input_macos.m` — implement wrappers + cleanup

Each wrapper locks `input_mutex`, calls the snapshot function, unlocks. Add `input_inject_clear_all_keys()` and `input_inject_clear_mouse()` calls in `input_close()`.

### Why this approach (overlay) vs alternatives

- **Command queue**: awkward for keys since they persist across frames (not one-shot events)
- **Direct `key[]` writes**: overwritten every frame by `input_snapshot_apply()`
- **Overlay**: merges naturally in the existing pipeline, thread-safe via same mutex

---

## Phase 2: ObjC Input Injection Bridge

### New: `src/macos/InputInjectionBridge.h/.mm`

- Static `NSDictionary` mapping ~85 key names (lowercase) to `KEY_*` constants
  - Letters: `"a"` → `KEY_A`, etc.
  - Digits: `"1"` → `KEY_1`, etc.
  - Named: `"escape"`, `"return"`, `"space"`, `"tab"`, `"backspace"`, `"delete"`, `"up"`, `"down"`, `"left"`, `"right"`, `"shift"`, `"control"`, `"alt"`, `"f1"`–`"f12"`, etc.
- `+injectKeyDown:` / `+injectKeyUp:` — resolve name, call C function
- `+typeText:` — async character-by-character injection with deterministic cancellation rules
  - ASCII lookup table mapping chars to (keycode, needsShift)
  - Running-session only: reject immediately if emulation is idle or paused
  - Dispatched to a serial background queue, with a generation token so stop/reset/new `type text` commands cancel any in-flight sequence
  - Use ~20ms as the minimum transition gap, but check session state before every key transition and before releasing modifiers
  - On cancellation or failure, always release any injected modifiers/keys before returning
  - Unsupported characters fail with a script error naming the first unsupported character
  - Returns via `suspendExecution`/`resumeExecutionWithResult:` for AppleScript
- `+injectMouseMoveDx:dy:` / `+injectMouseButtonDown:` / `+injectMouseButtonUp:`

---

## Phase 3: AppleScript Integration

### New: `macos/Arculator.sdef`

**Application properties** (read-only via KVC on NSApplication):

| Property | Type | Source |
|---|---|---|
| `emulation state` | text | `EmulatorBridge.sessionState` → "idle"/"running"/"paused" |
| `active config` | text | `EmulatorBridge.activeConfigName` |
| `speed` | integer | `inssec` C global |
| `disc names` | list of text | `discname[4][512]` C global |
| `config names` | list of text | `ConfigBridge.listConfigNames` |

**Lifecycle commands:**

- `start emulation`, `stop emulation`, `pause emulation`, `resume emulation`, `reset emulation`
- `start config` (direct param: config name)

**Config commands:**

- `load config`, `create config` (with optional `with preset`), `copy config` (with `to`), `delete config`

**Disc commands:**

- `change disc` (direct param: path, optional `drive` 0–3), `eject disc` (optional `drive`)

**Input injection commands:**

- `inject key down` / `inject key up` (direct param: key name)
- `type text` (direct param: string)
- `inject mouse move` (params: `dx`, `dy`)
- `inject mouse down` / `inject mouse up` (optional `button` bitmask, default 1)

### AppleScript command contract

Every command validates inputs and current emulator state before touching the runtime. `NSScriptCommand` subclasses should not silently no-op; failures return AppleScript errors via `setScriptErrorNumber:` and `setScriptErrorString:`.

| Command group | Allowed states | Notes |
|---|---|---|
| `start emulation` | `idle` | Error if already running/paused |
| `stop emulation` | `running`, `paused` | Error if already idle |
| `pause emulation` | `running` | Error if idle/paused |
| `resume emulation` | `paused` | Error if idle/running |
| `reset emulation` | `running`, `paused` | Error if idle |
| `start config` | `idle` | Validates config name, loads config, then starts |
| `load config` | `idle` | Does not mutate the active session |
| `create config`, `copy config`, `delete config` | `idle` | Reject while a session is active to avoid mutating the live config underneath the emulator |
| `change disc`, `eject disc` | `running`, `paused` | Validate drive `0...3`; reject while idle |
| `inject key ...`, `inject mouse ...`, `type text` | `running` | Input injection is only supported while the guest is actively polling input |

Suggested script error categories:

- `1000` series: invalid arguments (`bad key name`, `bad drive`, `unsupported text character`)
- `1100` series: invalid state (`cannot pause while idle`, `cannot start config while already running`)
- `1200` series: lookup/file failures (`config not found`, `config already exists`)
- `1300` series: runtime cancellation (`type text cancelled because emulation stopped`)

### Config name validation

Treat all AppleScript-supplied config names as untrusted input before calling any `ConfigBridge` method that builds a path.

- Reject empty or whitespace-only names
- Trim leading/trailing whitespace before validation
- Allow only a conservative filename-safe character set, for example ASCII letters, digits, space, `_`, `-`, `+`, `.`, `()`
- Reject `/`, `:`, `\\`, control characters, and any `..` segment
- Keep collision checks case-insensitive to match the user-facing config list behavior
- Surface invalid names as argument errors rather than letting them reach `platform_path_machine_config()`

### `macos/Info.plist` — add 2 keys

```xml
<key>NSAppleScriptEnabled</key>
<true/>
<key>OSAScriptingDefinition</key>
<string>Arculator.sdef</string>
```

### New: `src/macos/NSApplication+Scripting.mm`

ObjC category on NSApplication implementing KVC accessors for each .sdef property. Calls into `EmulatorBridge`, `ConfigBridge`, and C globals (`inssec`, `discname`).

### New: split scripting command implementations by domain

- `src/macos/ScriptingCommandSupport.h/.mm`
  - Shared helpers for argument extraction, state validation, config name validation, and AppleScript error creation
- `src/macos/LifecycleScriptingCommands.mm`
  - `start/stop/pause/resume/reset/start config`
- `src/macos/ConfigScriptingCommands.mm`
  - `load/create/copy/delete config`, `change/eject disc`
- `src/macos/InputScriptingCommands.mm`
  - `inject key ...`, `type text`, `inject mouse ...`

This keeps the scripting layer readable and avoids a single large file containing every command class.

---

## File Summary

### New files (9)

| File | Purpose |
|---|---|
| `macos/Arculator.sdef` | AppleScript dictionary definition |
| `src/macos/InputInjectionBridge.h` | Injection bridge header |
| `src/macos/InputInjectionBridge.mm` | Key name table, type text, mouse methods |
| `src/macos/NSApplication+Scripting.mm` | KVC property accessors for app-level queries |
| `src/macos/ScriptingCommandSupport.h` | Shared argument validation + error helpers |
| `src/macos/ScriptingCommandSupport.mm` | Shared state/config validation implementation |
| `src/macos/LifecycleScriptingCommands.mm` | Lifecycle and start-config commands |
| `src/macos/ConfigScriptingCommands.mm` | Config and disc commands |
| `src/macos/InputScriptingCommands.mm` | Key, text, and mouse injection commands |

### Modified files (5)

| File | Changes |
|---|---|
| `src/input_snapshot.h` | Overlay fields + 6 function prototypes |
| `src/input_snapshot.c` | Implement injection functions + modify `apply()` |
| `src/plat_input.h` | 6 `input_inject_*()` prototypes |
| `src/macos/input_macos.m` | Implement wrappers + cleanup in `input_close()` |
| `macos/Info.plist` | Enable scripting (2 keys) |

### Xcode project

Add new files to build target + `.sdef` to Copy Bundle Resources.

---

## Threading Notes

- AppleScript commands arrive on the main thread — most are fast enough to run synchronously
- `type text` blocks for multiple keystrokes, so it uses `suspendExecution`/`resumeExecutionWithResult:` to avoid freezing the UI
- `type text` is cancellable: if emulation pauses, stops, or another `type text` supersedes it, the command aborts, clears injected keys, and returns a script error
- The emulated keyboard controller processes one key change per poll — use ~20ms gaps as a baseline, but re-check emulator state before every transition
- Mouse deltas are additive and one-shot (consumed each frame) — multiple `inject mouse move` calls between frames accumulate
- Mouse button injection uses explicit overlay state, not OR-only merging, so scripted button-up events can override the host button state for the selected buttons
- Mouse injection works regardless of capture state
- All injected state is cleared in `input_close()` to prevent stuck keys across session restarts

---

## Verification

### Host automation test

```applescript
tell application "Arculator"
    start config "A3010"
    delay 3
    emulation state -- should return "running"
    speed -- should return a percentage
    reset emulation
    stop emulation
end tell
```

### Input injection test

```applescript
tell application "Arculator"
    start config "A3010"
    delay 5
    -- Shift+F12 to open the RISC OS task manager
    inject key down "shift"
    inject key down "f12"
    delay 0.1
    inject key up "f12"
    inject key up "shift"
    delay 1
    -- Type a command
    type text "cat"
    delay 0.1
    inject key down "return"
    delay 0.05
    inject key up "return"
end tell
```

### Mouse injection test

```applescript
tell application "Arculator"
    inject mouse move dx 100 dy -50
    inject mouse down button 1
    delay 0.1
    inject mouse up button 1
end tell
```

### Invalid-state / invalid-input tests

- `pause emulation` while idle → AppleScript error in the `1100` series
- `start config "A3010"` while already running → AppleScript error in the `1100` series
- `change disc "/tmp/test.adf" drive 9` → AppleScript error in the `1000` series
- `create config "../evil"` → AppleScript error in the `1000` series before any path is built
- `type text "£"` → AppleScript error in the `1000` series if the ASCII table does not support it

### `type text` cancellation test

Start a long `type text`, then stop or pause emulation mid-sequence. Verify:

- the command returns an AppleScript cancellation/state error
- any injected modifiers are released
- restarting emulation does not leave a stuck key behind

### Stuck key cleanup test

Start emulation → inject key down → stop emulation → restart → verify key is not stuck.

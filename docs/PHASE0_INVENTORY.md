# Phase 0 Inventory

This document records the boundary and ownership issues called out in Phase 0 of `docs/PORTING_PLAN.md`.

## Shell Boundary Extraction

The shell-facing control surface previously declared in `src/arc.h` has been moved to `src/platform_shell.h`.

Functions moved:

- `arc_print_error`
- `updatewindowsize`
- `arc_start_main_thread`
- `arc_stop_main_thread`
- `arc_pause_main_thread`
- `arc_resume_main_thread`
- `arc_do_reset`
- `arc_disc_change`
- `arc_disc_eject`
- `arc_enter_fullscreen`
- `arc_renderer_reset`
- `arc_set_display_mode`
- `arc_set_dblscan`
- `arc_stop_emulation`
- `arc_popup_menu`
- `arc_update_menu`
- `wx_getnativemenu`

Current implementation owners:

- `src/wx-sdl2.c`
- `src/wx-win32.c`
- `src/wx-app.cc`

`src/main.c` no longer includes `video_sdl2.h`. The remaining direct `video_sdl2.h` users are shell/backend files:

- `src/input_sdl2.c`
- `src/video_sdl2.c`
- `src/wx-sdl2.c`
- `src/wx-win32.c`

## Cross-Thread And Cross-Layer Functions

Current ownership is still mixed. This table captures the present state and the Phase 3 direction.

| Function | Current callers | Current owner/thread model | Current behavior | Target model |
|---|---|---|---|---|
| `arc_start_main_thread` | `src/wx-app.cc` | Shell; starts SDL/Win32 loop | Synchronous shell entrypoint that spawns or directly runs the emulation loop depending on platform | Remains shell-only; replaced by native macOS app controller startup |
| `arc_stop_main_thread` | `src/wx-app.cc` | Shell | Signals loop exit and joins thread | Remains shell-only |
| `arc_pause_main_thread` / `arc_resume_main_thread` | `src/wx-app.cc` | Shell | Coarse SDL mutex around emulation loop | Should become explicit control-state changes or queue messages |
| `arc_do_reset` | `src/wx-app.cc` | Shell -> emulator | Takes SDL mutex and resets emulator synchronously | Queue to emulation thread |
| `arc_disc_change` / `arc_disc_eject` | `src/wx-app.cc` | Shell -> emulator | Directly mutates media state, guarded by SDL mutex unless debugger owns flow | Queue to emulation thread |
| `arc_set_display_mode` / `arc_set_dblscan` | `src/wx-app.cc` | Shell -> emulator/video | Directly mutates display globals and clears buffers under mutex | Queue to emulation thread |
| `arc_renderer_reset` | `src/wx-app.cc` | Shell/video | Sets a shell-owned flag consumed by the loop | Keep as shell/renderer request, but decouple from SDL globals |
| `arc_enter_fullscreen` | `src/wx-app.cc` | Shell/window | Sets a shell-owned flag consumed by the loop | Remains main-thread shell action |
| `updatewindowsize` | `src/vidc.c`, `src/g332.c`, `src/lc.c`, `src/wx-sdl2.c`, `src/wx-win32.c` | Emulator/video -> shell/window | Core code requests shell window resize directly | Convert to renderer publish/display-state update, marshaled to main thread |
| `arc_update_menu` | `src/wx-sdl2.c`, `src/wx-win32.c` | Shell/UI | UI refresh request from emulation loop startup and config changes | Remains shell-only, main thread |
| `arc_popup_menu` | `src/wx-sdl2.c` | Shell/UI | Direct UI popup request from SDL event loop | Remains shell-only, main thread |
| `arc_stop_emulation` | `src/wx-sdl2.c`, `src/wx-app.cc`, `src/wx-win32.c` | Shell/UI | Posts shutdown/config-selection transition back into wx layer | Remains shell-only, but should operate on native controller state |
| `arc_print_error` | `src/podules.c` | Emulator -> shell/UI | Direct UI error surfacing from non-shell code | Likely becomes shell callback/service rather than globally exposed UI function |

Notes:

- On macOS today, `src/wx-sdl2.c` runs `arc_main_thread(NULL)` directly because SDL/UI work must stay on the main thread.
- On Windows, the shell starts a separate emulation thread and coordinates through `main_thread_mutex`.
- The current synchronization model mixes lifecycle, UI, and emulator mutation through one coarse lock plus shell-owned flags.

## `exname` Path Inventory

The following sites derive paths from `exname` and therefore assume the executable directory is both the resource root and writable data root.

### Writable/user-state paths

- `src/config.c`
  - `arc.cfg`
- `src/cmos.c`
  - per-machine CMOS files
- `src/wx-config_sel.cc`
  - `configs/`
- `src/hostfs.c`
  - `hostfs/`

### Read-only bundled resource paths

- `src/ddnoise.c`
  - `ddnoise/35/`
- `src/romload.c`
  - ROM-set directories
  - `roms/A4 5th Column.rom`
  - `roms/arcrom_ext`
- `src/podules.c`
  - internal podule probe root
- `src/podules-macosx.c`
  - `podules/`
- `src/podules-linux.c`
  - `podules/`
- `src/podules-win.c`
  - `podules\\`

### Internal podule ROM assets loaded via `exname`

- `src/colourcard.c`
  - `roms/podules/colourcard/cc.bin`
- `src/g16.c`
  - `roms/podules/g16/g16.rom`
- `src/ide_a3in.c`
  - `roms/podules/a3inv5/ICS 93 A3IN 3V5 3V06 - 256.BIN`
- `src/ide_idea.c`
  - `roms/podules/idea/idea`
- `src/ide_riscdev.c`
  - `roms/podules/riscdev/riscdev`
- `src/ide_zidefs.c`
  - `roms/podules/zidefs/zidefsrom`
- `src/ide_zidefs_a3k.c`
  - `roms/podules/zidefs_a3k/zidefsrom`
- `src/riscdev_hdfc.c`
  - `roms/podules/hdfc/hdfc.rom`
- `src/st506_akd52.c`
  - `roms/podules/akd52/akd52`

## Immediate Follow-On For Phase 1/2

- Introduce a path service that separates app resources from Application Support.
- Replace `updatewindowsize` with a shell-agnostic display-state notification.
- Replace direct shell mutation helpers with an emulation control queue.

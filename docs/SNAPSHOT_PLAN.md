# Floppy-Only Snapshot Files

## Summary

Build a v1 snapshot feature that saves a paused, floppy-only emulator session into a single `.arcsnap` file and later starts that snapshot directly from idle.

Defaults locked for v1:
- Scope: base machine + floppy drives only
- Packaging: self-contained snapshot file with bundled config and bundled floppy media
- Media behavior after load: run against extracted temporary copies, never the original source images
- UX: manual `Save Snapshot...` and `Load Snapshot...`
- Safety limits: save only while paused and only when the floppy subsystem is idle; load only from idle
- Compatibility: reject snapshots for sessions using internal hard disks, podules, or other unsupported devices; reject incompatible/corrupt snapshot versions

## Key Changes

- Add a new core snapshot subsystem, likely `src/snapshot.h` / `src/snapshot.c`, using a chunked binary format:
  - Header: magic, format version, emulator version string
  - Manifest chunk: original config name, machine/FDC identifiers, supported-scope flags, mounted floppy metadata
  - Config chunk: exact machine config text
  - Media chunks: full bytes of each mounted floppy image plus original extension/write-protect metadata
  - Preview chunk: optional PNG screenshot captured at save time, with width/height metadata for snapshot browsing UI
  - State chunks: per-subsystem serialized machine state

- Serialize emulated machine state through explicit save/load hooks per subsystem rather than one giant `memcpy`:
  - ARM CPU/register/cache state
  - Timer core (`tsc`, pending timer timestamps, enabled flags)
  - RAM and memory-controller state needed beyond bundled ROM/config
  - IOC, VIDC, keyboard/mouse, CMOS, DS2401, sound DMA/emulated sound state
  - Machine-specific pieces such as `lc` / `ioeb` when applicable
  - Floppy controller/core state: disc selection/current track/motor/density plus WD1770 or 82C711 FDC registers/timer state

- Do not serialize host-side presentation state:
  - Video renderer objects, Cocoa/Metal views, host input snapshots, host audio buffers
  - On restore, clear host input/audio buffers and redraw from restored machine state
  - Treat the preview screenshot as optional metadata only; it is not required for restore and preview decode failures must not invalidate snapshot loading

- Keep floppy backends file-based on restore:
  - On load, extract bundled config and floppy images into a temp runtime directory under Application Support, for example `snapshots/runtime/<id>/`
  - Rewrite the extracted runtime config before initialization so `disc_name_0` through `disc_name_3` point at extracted temp floppy copies, not the user's original source image paths. This must happen before `arc_init()`, because `arc_init()` currently autoloads configured floppy paths.
  - Point `machine_config_file` at the extracted/rebased runtime config, call `arc_init()`, let the existing config loader open the extracted floppy files through `disc_load()`, then apply restored machine/FDC state
  - Preserve the original config name as manifest/UI metadata, but do not use it as the live runtime identity for filesystem writes
  - Use a snapshot-specific runtime identity for writable per-session state such as CMOS, or add an explicit CMOS save/load remapping or suppression path so a loaded snapshot never writes `cmos/<original-config-name>...`
  - Because media is isolated temp data, resumed sessions never touch the user's original images

- Add snapshot support gates/preflight:
  - Add a shared `snapshot_can_save(char *error, size_t error_len)` style preflight API so UI and command handlers report the same rejection reason
  - Block save if internal hard-disc state is configured: non-empty `hd_fn[]`, old-IO `st506_present`, or other hard-disc-backed controller state
  - Block save if any podule slot in `podule_names[]` is configured, including the default `arculator_rom`/HostFS-style podule unless v1 explicitly whitelists it. If it remains unsupported, the UI error must call out that default configs may need the podule removed before snapshots can be saved.
  - Block save if unsupported ROM/support hardware is configured, including `_5th_column_fn` and any other runtime state not covered by v1 serialization
  - Decide and document whether non-floppy host integrations such as `support_rom_enabled` and `joystick_if` are allowed, ignored, or rejected; prefer rejecting them until the snapshot manifest has explicit support bits
  - Block save if floppy activity is in progress; require a quiescent controller/backend state
  - Block load if snapshot manifest declares unsupported hardware/scope
  - Add per-subsystem quiescence helpers, especially for FDC/backends whose busy state is currently private static state, rather than inferring safety only from pause state

- Extend shell/UI interfaces:
  - `platform_shell.h`: add `arc_save_snapshot(const char *path)` and `arc_start_snapshot_session(const char *path)` (or equivalent)
  - `emulation_control.h`: add `EMU_COMMAND_SAVE_SNAPSHOT`
  - `EmulatorBridge`: add Objective-C wrappers for save/load snapshot
  - macOS menus: add `Save Snapshot...` when paused and `Load Snapshot...` when idle
  - Keep v1 out of the toolbar/sidebar; menu-driven is enough for the first pass
  - Wire the macOS-native shell path in `src/macos/app_macos.mm`, not just the legacy `wx-sdl2.c` path:
    - add menu command IDs and handlers for save/load
    - update `shell_update_menu_state()` / `menuNeedsUpdate:` validation
    - add command queue handling in the macOS pthread emulation loop for save
    - report snapshot errors back to AppKit alerts on the main thread
    - install the Metal emulator view before starting a snapshot session from idle, matching `EmulatorBridge.startEmulationForConfig:`

- Shell flow:
  - Save: UI picks path -> optionally captures preview PNG bytes through the macOS/AppKit screenshot bridge while paused -> queues save command -> emulation thread validates quiescence and writes `.arcsnap`
  - Keep preview capture platform-owned. The core snapshot writer should accept optional preview bytes/metadata, not call Objective-C or depend on the Metal renderer directly.
  - Load: UI picks snapshot while idle -> shell validates manifest support -> installs emulator view -> prepares temp runtime bundle with config/media paths rebased to extracted files -> starts a snapshot session -> emulation thread initializes emulator from the rebased config, restores machine state, then begins running from that point

## Test Plan

- Core serialization tests:
  - Roundtrip header/manifest/media chunks
  - Roundtrip snapshots with and without preview chunks
  - Corrupt magic/version/truncated file rejection
  - Unsupported-scope manifest rejection
  - Corrupt preview chunk is ignored for restore purposes and does not prevent snapshot load

- Core emulator tests:
  - Save a paused floppy-only session, stop, load snapshot, verify RAM/CPU/device restore points match
  - Save/load preserves mounted floppy set, current tracks, and controller state
  - Source floppy image remains unchanged after running a loaded snapshot
  - Re-saving a loaded snapshot captures changes made against the isolated temp media

- Guardrail tests:
  - Save rejected when podules or hard disks are configured
  - Save rejected with a clear message for a default config containing `arculator_rom`, unless v1 explicitly whitelists that podule
  - Save rejected when floppy controller/backend is busy
  - Load rejected from active session
  - Loading a snapshot never opens the original floppy image path from the saved config
  - Loading and later closing a snapshot never writes CMOS under the original config name

- macOS integration tests:
  - Menu enablement: `Save Snapshot...` only for paused sessions, `Load Snapshot...` only when idle
  - Loading a snapshot transitions idle -> running and restores the active config label/disc UI state

## Assumptions

- v1 intentionally excludes podules and hard-disk-backed machines because their runtime state is not reconstructible cheaply from the current architecture.
- Snapshot format is versioned but not guaranteed backward-compatible across future incompatible schema changes.
- Save is restricted to paused + floppy-idle sessions so restore can reuse existing floppy loaders instead of serializing mid-transfer backend internals.
- Snapshot files are single-file `.arcsnap` bundles with no compression requirement in v1; floppy sizes are small enough to keep that simple.

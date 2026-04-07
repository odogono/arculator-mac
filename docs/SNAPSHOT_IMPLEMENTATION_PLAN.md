# Floppy-Only Snapshots — Implementation Plan

## Context

Add a v1 snapshot feature so a paused, floppy-only Arculator session can be saved to a single self-contained `.arcsnap` file and later resumed from idle. The feature is described in `docs/SNAPSHOT_PLAN.md` (already in the repo).

Why now: there is currently no way to preserve a running Archimedes session across app restarts; users have to cold-boot RISC OS every time. v1 unblocks "save where I left off" for the common case (floppy-based machines), without taking on the much harder problem of serializing hard-disc/podule runtime state.

User-confirmed scope decisions for v1:
- **arculator_rom podule:** allowed (treated as static/stateless). All other podules in any slot reject the save.
- **FDCs supported:** WD1770, 82C711, and WD1793 (A500).
- **CMOS isolation:** snapshot sessions run under a synthetic `__snapshot_<uuid>` machine_config_name so CMOS writes never touch the user's `cmos/<original-name>.*` files. The original name is preserved in the snapshot manifest and exposed to the UI.
- **Delivery:** single branch, one commit per phase. Reviewable as a sequence of self-contained changes.

Out of scope for v1: hard discs, custom podules, save while running (must pause), load while running (must be idle), backwards-compatible format upgrades, compression.

## Architecture overview

Snapshot-related code lives in three new layers:

1. **Core file format & I/O** — `src/snapshot.h` / `src/snapshot.c`. Chunked binary writer/reader, manifest, scope guards, no platform deps.
2. **Per-subsystem serializers** — small `*_save_state` / `*_load_state` functions added to each existing subsystem `.c` file (or grouped in `src/snapshot_state.c` where touching globals from outside the owning module would be uglier). These are called by `snapshot.c` in a fixed order matching `arc_init()`.
3. **Shell integration** — new `EMU_COMMAND_SAVE_SNAPSHOT`, `arc_save_snapshot()`, `arc_start_snapshot_session()`, EmulatorBridge methods, and macOS menu items in `src/macos/app_macos.mm`.

The save flow runs **inside the emulation thread** (queued via the existing command queue) so it observes a consistent point in execution. The load flow is "out-of-band": it tears down any current session if needed (idle is required), prepares a runtime bundle on disk, then starts a fresh emulation thread that calls a new `arc_init_from_snapshot()` instead of `arc_init()`.

## File format (`.arcsnap`)

Single-file chunked binary, little-endian, no compression in v1.

```
ArcSnapHeader {
    char     magic[8];          // "ARCSNAP\0"
    uint32_t format_version;    // 1
    uint32_t emulator_version;  // numeric, e.g. 0x00020200 for v2.2
    uint32_t flags;             // reserved, 0 in v1
    uint32_t header_crc32;      // CRC32 of the header above
}

Chunk {
    uint32_t id;          // FourCC, e.g. 'MNFT', 'CFG ', 'MEDA', 'PREV', 'CPU ', etc.
    uint32_t version;     // per-chunk version
    uint64_t size;        // payload bytes (does not include this header)
    uint32_t crc32;       // CRC32 of payload
    uint32_t reserved;    // 0
    uint8_t  payload[size];
}
```

Chunks (fixed order in v1, but reader is order-tolerant):

| FourCC | Required | Contents |
|--------|---------|---|
| `MNFT` | yes | Manifest: original_config_name, machine string, fdctype, romset, memsize, scope flags bitmap, machine_type, mounted-floppy table (per drive: original_path, file_size, write_protect, extension), screenshot dims if a `PREV` chunk follows |
| `CFG ` | yes | Verbatim bytes of the original machine config file |
| `MEDA` | yes (one per mounted drive) | drive_index + raw bytes of the floppy image. One chunk per drive that has media. |
| `PREV` | optional | PNG preview (captured at save time, used for snapshot browsing UI). Decode failures are non-fatal. |
| `CPU ` | yes | ARM core state |
| `CP15` | conditional | CP15 cache/control regs (only if `arm_has_cp15`) |
| `FPA ` | conditional | FPA regs (only if `fpaena`) |
| `MEM ` | yes | RAM bytes + memmode |
| `MEMC` | yes | MEMC state including CAM (`memc_cam[512]`), DMA pointers/timestamps, vinit/vstart/vend/cinit, sound DMA pointers, `memcpages[]`, `memctrl`, etc. |
| `IOC ` | yes | Full `IOC_t` plus serialized timer state for ioc.timers[4] |
| `VIDC` | yes | VIDC palette, register cache, timing/DMA state, framecount |
| `KBD ` | yes | Keyboard I2C state machine, key/mouse runtime state |
| `CMOS` | yes | `cmos.ram[256]`, `cmos.rtc_ram[8]`, cmos state machine, i2c state |
| `DS24` | yes | DS2401 state machine |
| `SND ` | yes | Sound period/enable/gain/filter (config-ish) + any in-progress DMA scratch |
| `IOEB` | conditional | IOEB state (only on machines that init it) |
| `LC  ` | conditional | A4 LC state (only on `MACHINE_TYPE_A4`) |
| `FDC ` | yes | Either `wd1770` struct or `_fdc` struct, plus globals: `motoron`, `curdrive`, `disc_drivesel`, `fdc_ready`, `fdc_overridden`, `disc_current_track[4]`, `discchange[4]`, `writeprot[4]`, `readflash[4]` |
| `TIMR` | yes | Global timer state: `tsc`, `timer_target`. Per-timer state is co-located with the owning subsystem's chunk so callbacks line up. |
| `END ` | yes | Trailer with overall CRC32 across all preceding payload bytes, used as a final integrity check. |

Scope-flag bitmap in `MNFT` declares which optional subsystems are present; the loader rejects mismatches between manifest and the scope of the runtime config it's about to start.

## Phasing (one branch, one commit per phase)

Each phase compiles and passes existing tests. Each phase ends in a commit. Full implementation lives on a new branch `snapshot-v1` cut from `ui-update`.

### Phase 1 — Format primitives + serialization framework

Files added:
- `src/snapshot.h` — public C API:
  ```c
  int snapshot_save(const char *path,
                    const uint8_t *preview_png, size_t preview_png_size,
                    int preview_w, int preview_h,
                    char *error_buf, size_t error_buf_len);
  int snapshot_can_save(char *error_buf, size_t error_buf_len);

  typedef struct snapshot_load_ctx_t snapshot_load_ctx_t;
  snapshot_load_ctx_t *snapshot_open(const char *path,
                                     char *error_buf, size_t error_buf_len);
  int snapshot_prepare_runtime(snapshot_load_ctx_t *ctx,
                               char *runtime_dir_out, size_t runtime_dir_out_len,
                               char *runtime_config_out, size_t runtime_config_out_len,
                               char *runtime_name_out, size_t runtime_name_out_len,
                               char *error_buf, size_t error_buf_len);
  int snapshot_apply_machine_state(snapshot_load_ctx_t *ctx,
                                   char *error_buf, size_t error_buf_len);
  void snapshot_close(snapshot_load_ctx_t *ctx);
  ```
- `src/snapshot.c` — chunk reader/writer, header, CRC32 (small inline implementation), manifest encode/decode. Stub `snapshot_can_save` (returns OK), stub `snapshot_apply_machine_state` (returns OK with no-op).
- `src/snapshot_chunks.h` — internal: FourCC IDs, chunk struct definitions, payload-version constants.
- `src/platform_paths.h` / `src/platform_paths.c` — add `platform_path_snapshot_runtime_dir(char *dest, size_t size, const char *id)` returning `<support>/snapshots/runtime/<id>/` and ensuring the directory exists. Auto-create `<support>/snapshots/` in `platform_paths_init()`.
- `tests/snapshot_format_tests.c` (added to existing tests/Makefile pattern alongside `phase3_tests.c`):
  - Header round-trip and reject on bad magic / bad version / bad CRC
  - Chunk writer/reader round-trip with multiple chunks
  - Manifest encode/decode round-trip
  - Truncated file rejection

Phase 1 commit message:
> snapshot: add file format, framework, and platform paths

### Phase 2 — Per-subsystem state serialization

This is the bulk of the work. Each subsystem grows two static-or-extern functions: one to write its chunk(s) to a `snapshot_writer_t *`, one to read from a `snapshot_reader_t *`. To keep the diff per file small, each subsystem owns its own serializer; `snapshot.c` only orchestrates the call order.

Files added:
- `src/snapshot_subsystems.h` — internal header listing every `*_save_state` / `*_load_state` symbol.

Files modified (each gets two small functions following the same pattern):

| Subsystem | File | Save/load symbols | Notes |
|---|---|---|---|
| ARM core | `src/arm.c` | `arm_save_state`, `arm_load_state` | Writes `armregs[16]`, `opcode`, `armirq`, `armfiq`, `databort`, `prefabort`, `prefabort_next`, `osmode`, `memmode`. |
| CP15 | `src/cp15.c` | `cp15_save_state`, `cp15_load_state` | Only emitted/loaded if `arm_has_cp15`. Writes `arm3cp` struct + `cp15_cacheon`. |
| FPA | `src/fpa.c` | `fpa_save_state`, `fpa_load_state` | Only if `fpaena`. Writes `fpsr`, `fpcr`, FPA register file. |
| Memory/RAM | `src/mem.c` | `mem_save_state`, `mem_load_state` | Writes `memsize`, then `ram[memsize*1024]` raw bytes. `memstat[]` and `mempoint[]` are reconstructed by MEMC restore (CAM writes). |
| MEMC | `src/memc.c` | `memc_save_state`, `memc_load_state` | Writes `memc_cam[512]`, all MEMC DMA pointers/timestamps, `vinit`/`vstart`/`vend`/`cinit`, `sstart`/`ssend`/`sptr`/`spos`/`sendN`/`sstart2`, `nextvalid`, `sdmaena`, `memctrl`, `bigcyc`, `pagesize`, `memcpages[0x2000]`, `memc_videodma_enable`, `memc_refreshon`. On load, walk `memc_cam[]` and call `writecam()`/`writememc()` equivalents to rebuild `memstat[]` and `mempoint[]`. |
| IOC | `src/ioc.c` | `ioc_save_state`, `ioc_load_state` | Writes full `IOC_t` (irqa/b/fiq, masks, ctrl, timerc/l/r). For each `ioc.timers[4]` writes `{ts_integer, ts_frac, enabled}` and `ref8m_period`. |
| VIDC | `src/vidc.c` | `vidc_save_state`, `vidc_load_state` | Writes palette, register shadow array, timing regs, cursor regs, DMA pointers, `vidc_displayon`, `vidc_framecount`, `vidc_dma_length`. On load, calls `vidc_redopalette()` and `setredrawall()`. |
| Keyboard/mouse | `src/keyboard.c` | `keyboard_save_state`, `keyboard_load_state` | I2C state machine + key matrix snapshot. Reuses `input_snapshot_state_t` if helpful. Mouse runtime state is reset on load (host input is platform state). |
| CMOS | `src/cmos.c` | `cmos_save_state`, `cmos_load_state` | Writes `cmos.ram[256]`, `cmos.rtc_ram[8]`, `cmos.state`, `cmos.addr`, `cmos.rw`, `cmos.device_addr`, `i2c.*`, `cmos_changed`, plus `cmos.timer` state via `{ts_integer, ts_frac, enabled}`. Skips wall-clock RTC bytes (1–6) which are refreshed on next tick anyway. |
| DS2401 | `src/ds2401.c` | `ds2401_save_state`, `ds2401_load_state` | Whatever state machine + bit position state. |
| Sound | `src/sound.c` | `sound_save_state`, `sound_load_state` | Period/enable/gain/filter. Host audio buffers are NOT serialized. On load: clear platform audio queue, reapply settings via existing setters. |
| WD1770 | `src/wd1770.c` | `wd1770_save_state`, `wd1770_load_state` | Writes the entire `wd1770` static struct + its embedded timer state. Skipped if `fdctype == FDC_82C711`. |
| 82C711 FDC | `src/82c711_fdc.c` | `c82c711_fdc_save_state`, `c82c711_fdc_load_state` | Writes the entire `_fdc` static struct + its embedded timer state. Skipped unless `fdctype == FDC_82C711`. |
| Disc globals | `src/disc.c` | `disc_save_state`, `disc_load_state` | Writes `motoron`, `curdrive`, `disc_drivesel`, `fdc_ready`, `fdc_overridden`, `disc_current_track[4]`, `discchange[4]`, `writeprot[4]`, `readflash[4]`. ADF/HFE in-memory track buffers are NOT serialized; they get repopulated by replaying `disc_seek()` to `disc_current_track[drive]` after load. |
| IOEB | `src/ioeb.c` | `ioeb_save_state`, `ioeb_load_state` | `ioeb_clock_select` and any other module statics. |
| LC (A4) | `src/lc.c` | `lc_save_state`, `lc_load_state` | Only on `MACHINE_TYPE_A4`. |
| Timer global | `src/timer.c` | `timer_save_global`, `timer_load_global` | `tsc` and `timer_target`. **Per-timer state lives in each subsystem's chunk** — restoration is done by setting `{ts_integer, ts_frac}` directly on the existing `emu_timer_t` and calling `timer_enable()` / `timer_disable()` which correctly handles the linked list. |

Timer-restore helper added to `src/timer.h`:
```c
static inline void timer_restore(emu_timer_t *t, uint32_t ts_int, uint32_t ts_frac, int enabled)
{
    timer_disable(t);
    t->ts_integer = ts_int;
    t->ts_frac = ts_frac;
    if (enabled)
        timer_enable(t);
}
```

`snapshot.c` calls these in the same order `arc_init()` initializes the corresponding subsystems, so callbacks and module statics are always wired before state is applied.

Phase 2 commit message:
> snapshot: serialize per-subsystem machine state

### Phase 3 — Quiescence + scope guards

Files added:
- `src/snapshot_scope.c` (or grow `src/snapshot.c`) — implements `snapshot_can_save()`. Walks the configured machine and emits a precise rejection reason:

```c
int snapshot_can_save(char *err, size_t n)
{
    if (!arc_is_paused())                       return reject(err, n, "save snapshot only while paused");
    if (st506_present || hd_fn[0][0] || hd_fn[1][0])
                                                 return reject(err, n, "internal hard disc configured (snapshots are floppy-only in v1)");
    for (int i = 0; i < 4; i++)
        if (podule_names[i][0] && strcmp(podule_names[i], "arculator_rom"))
            return reject(err, n, "podule '%s' in slot %d not supported in v1", podule_names[i], i);
    if (_5th_column_fn[0])                      return reject(err, n, "5th-column ROM not supported in v1");
    if (joystick_if[0])                         return reject(err, n, "joystick interface not supported in v1");
    if (!floppy_is_idle())                      return reject(err, n, "floppy controller is busy; wait and try again");
    return 1;
}
```

- `src/disc.c` — add public helper:
  ```c
  int floppy_is_idle(void); // 1 = no command in flight, motor off-or-idle, FDC accepting commands
  ```
  Implementation checks `motoron`, the relevant FDC busy flags (`wd1770.status & 1` or `_fdc.stat & 0x80` etc.), `_fdc.inread`, `_fdc.pnum != _fdc.ptot`, plus that the FDC timer is disabled. Tested with a small unit test that drives WD1770 into busy and quiescent states.

Symmetrical scope check on **load**: `snapshot_open()` reads the manifest and rejects mismatches before any state is touched.

Tests added to `tests/snapshot_format_tests.c`:
- Reject save when `st506_present` is set
- Reject save when an unknown podule is configured
- Reject save when `floppy_is_idle()` returns false
- Allow save when only `arculator_rom` is configured
- Reject load when manifest has hard-disc / unknown podule scope flags

Phase 3 commit message:
> snapshot: add scope guards and floppy quiescence helper

### Phase 4 — Loader: runtime bundle preparation + arc_init_from_snapshot

Files added/modified:
- `src/snapshot.c` — `snapshot_prepare_runtime()`:
  1. Generates a per-session ID: `__snapshot_<8-byte-hex>`
  2. Creates `<support>/snapshots/runtime/<id>/`
  3. Extracts `CFG ` chunk to `<runtime_dir>/machine.cfg`
  4. For each `MEDA` chunk, extracts to `<runtime_dir>/disc<n>.<ext>` using the original extension
  5. Rewrites `disc_name_0..disc_name_3` in the extracted config to point at the extracted disc files (use the existing `config_load`/`config_set_string`/`config_save` API on a `CFG_MACHINE` reload — easier than line-editing). The rewrite happens **before** `arc_init()` runs so the standard config-driven floppy autoload picks up the right paths.
  6. Returns the runtime directory, runtime config path, and the synthetic `__snapshot_<id>` name to the shell.

- `src/main.c` — new entry point:
  ```c
  int arc_init_from_snapshot(snapshot_load_ctx_t *ctx); // returns 0 on success
  ```
  This is a thin wrapper around `arc_init()`:
  - Caller has already set `machine_config_file` and `machine_config_name` to the runtime versions.
  - `arc_init()` runs as normal — loads the rebased config, autoloads the extracted floppy images via `disc_load()`, etc.
  - On return, `snapshot_apply_machine_state(ctx)` is called to overwrite ARM/MEMC/IOC/VIDC/CMOS/FDC/etc. state.
  - After state is applied, calls `disc_seek(drive, disc_current_track[drive])` for each loaded drive so the ADF/HFE backend track buffers are repopulated to match the restored controller position.
  - Calls `setredrawall()` and `vidc_redopalette()` so the very next frame draws the restored display correctly.
  - Finally, `snapshot_close(ctx)`.

- `src/snapshot.h` — also expose:
  ```c
  // Capture original config name from manifest for the UI
  const char *snapshot_original_config_name(snapshot_load_ctx_t *ctx);
  ```

Phase 4 commit message:
> snapshot: implement loader, runtime bundle, and arc_init_from_snapshot

### Phase 5 — macOS shell integration

Files modified:

- `src/emulation_control.h` — add `EMU_COMMAND_SAVE_SNAPSHOT` to the enum. Reuse the existing `path[512]` field on `emulation_command_t`.

- `src/platform_shell.h` — add prototypes:
  ```c
  void arc_save_snapshot(const char *path);                       // queues save command
  int  arc_start_snapshot_session(const char *path, char *err_out, size_t n);
                                                                  // load: idle -> running snapshot session
  ```

- `src/main.c` — add `int arc_init_from_snapshot(snapshot_load_ctx_t *)` exported declaration in `arc.h`.

- `src/macos/app_macos.mm`:
  1. **Menu IDs:** add `MENU_FILE_SAVE_SNAPSHOT`, `MENU_FILE_LOAD_SNAPSHOT` to the existing enum. Add the two items to `shell_create_file_menu()` after `Hard Reset`.
  2. **Menu validation:** `shell_update_menu_state()` enables `Save Snapshot…` only when `arc_is_paused() && shell_session_active && snapshot_can_save(NULL, 0)`. Enables `Load Snapshot…` only when `!shell_session_active`.
  3. **Command handler:** `handleMenuCommand:` opens an `NSSavePanel` (for save) or `NSOpenPanel` (for load) using the existing patterns from `MENU_DISC_CHANGE_*`. The dialogs default to `<support>/snapshots/` (created by `platform_paths_init()`).
  4. **Save command path:** UI thread captures preview PNG via the existing `EmulatorBridge.captureScreenshotToPath:` machinery (writes to a temp file, reads bytes, deletes temp). It then queues `EMU_COMMAND_SAVE_SNAPSHOT` with the chosen path. The emulation thread executes `snapshot_save()` (which re-runs `snapshot_can_save()` defensively). Errors are sent back to AppKit via `arc_print_error()` which is already main-thread-safe.
  5. **Load command path:** UI thread calls `arc_start_snapshot_session(path, err, n)` directly (since session is idle, the emulation thread isn't running yet). That helper:
     - Calls `snapshot_open()` (validates header + manifest scope)
     - Calls `snapshot_prepare_runtime()` (extracts config + media to a temp dir under `<support>/snapshots/runtime/<id>/`)
     - Sets `machine_config_file` and `machine_config_name` to the runtime versions
     - Calls `[EmulatorBridge ensureVideoViewInstalled]` (the same path `startEmulationForConfig:` uses)
     - Stores the open `snapshot_load_ctx_t *` in a static so the new emulation thread can pick it up
     - Calls `arc_start_main_thread(NULL, NULL)`
     - The emulation thread inits via `arc_init_from_snapshot(ctx)` instead of `arc_init()` when the static ctx is non-NULL
  6. **Cleanup:** when a snapshot-session emulation thread shuts down (`arc_close()`), the runtime directory under `<support>/snapshots/runtime/<id>/` is removed and the `cmos/__snapshot_<id>.*.cmos.bin` file is removed. Cleanup is best-effort and logged via `rpclog`.

- `src/macos/EmulatorBridge.h/.mm` — add:
  ```objc
  + (BOOL)saveSnapshotToPath:(NSString *)path error:(NSString **)error;
  + (BOOL)startSnapshotSessionFromPath:(NSString *)path error:(NSString **)error;
  + (BOOL)canSaveSnapshotWithError:(NSString **)error;  // wraps snapshot_can_save
  ```
  These are thin wrappers that call into `arc_save_snapshot` / `arc_start_snapshot_session` / `snapshot_can_save`. Used by both the menu handler and (later) any UI buttons or AppleScript commands.

- `src/macos/EmulatorState.swift` — add `@Published private(set) var canSaveSnapshot: Bool = false`. Polled alongside `sessionState` on the existing 0.25s timer so menu/UI gating is reactive.

- `src/macos/app_macos.mm` `shell_set_window_title()` — when `machine_config_name` starts with `__snapshot_`, render the original name from the snapshot context instead so the user sees a real name in the title bar.

Phase 5 commit message:
> snapshot: wire macOS menus, EmulatorBridge, and snapshot session lifecycle

### Phase 6 — Tests

Files added/modified:
- `tests/snapshot_format_tests.c` (extended from Phase 1) — adds:
  - End-to-end synthetic save/load roundtrip using a hand-built fake machine state (no ROM required: serializers operate on plain globals which the test sets up directly, then the test calls each `*_save_state` and `*_load_state` and asserts byte equality after a `memset`-and-restore cycle).
  - `floppy_is_idle()` truth-table test
- `tests/run_phase3_tests.sh` updated (or new `tests/run_snapshot_tests.sh`) to also run snapshot test binary.
- `tests/ArculatorCoreTests/SnapshotScopeTests.m` — Objective-C XCTest hitting `snapshot_can_save` with various config setups (HD configured, unknown podule, busy FDC, valid floppy-only) and asserting the right error string.
- `tests/ArculatorUITests/SnapshotMenuUITests.swift` — light UI test:
  - With idle session: `Save Snapshot…` disabled, `Load Snapshot…` enabled
  - With running session: both disabled
  - With paused session: `Save Snapshot…` enabled, `Load Snapshot…` disabled

Manual verification (run by me before declaring done):
1. `make` from project root, ensure clean build.
2. Run `./tests/phase3_tests` and the new `./tests/snapshot_format_tests`.
3. Open the macOS app, start a floppy-only config, boot to RISC OS desktop, drop a file in `!Scrap`, pause, **Save Snapshot…**.
4. Quit the app entirely.
5. Re-launch app, **Load Snapshot…**, pick the saved file. Verify the desktop comes back with the file still in `!Scrap`.
6. Confirm the source `.adf` on disk has not changed (compare hashes before/after).
7. Re-save from the loaded session, confirm the new snapshot reflects further changes made against the isolated temp media.
8. Try saving a snapshot for a config with a hard disc configured: confirm rejection alert with the expected message.
9. Try saving a snapshot while the FDC is mid-transfer (e.g. immediately after typing `*COPY`): confirm "floppy controller is busy" rejection.

Phase 6 commit message:
> snapshot: tests for format, scope, and floppy quiescence

## Critical files to modify

- `src/snapshot.h`, `src/snapshot.c`, `src/snapshot_chunks.h` (new)
- `src/snapshot_scope.c` (new, or in snapshot.c)
- `src/main.c` — `arc_init_from_snapshot()`
- `src/arc.h` — declaration of `arc_init_from_snapshot`
- `src/timer.h` — `timer_restore()` inline helper
- `src/timer.c` — `timer_save_global` / `timer_load_global`
- `src/arm.c`, `src/cp15.c`, `src/fpa.c` — CPU/coprocessor serializers
- `src/mem.c`, `src/memc.c` — RAM and MEMC serializers (CAM replay on load)
- `src/ioc.c`, `src/vidc.c`, `src/keyboard.c`, `src/cmos.c`, `src/ds2401.c`, `src/sound.c`, `src/ioeb.c`, `src/lc.c` — per-subsystem serializers
- `src/wd1770.c`, `src/82c711_fdc.c`, `src/disc.c` — FDC + disc globals + `floppy_is_idle()`
- `src/disc.h` — declare `floppy_is_idle()`
- `src/platform_paths.c`, `src/platform_paths.h` — `<support>/snapshots/...` helpers
- `src/emulation_control.h` — `EMU_COMMAND_SAVE_SNAPSHOT`
- `src/platform_shell.h` — `arc_save_snapshot`, `arc_start_snapshot_session`
- `src/macos/app_macos.mm` — menu items, command handler, command queue dispatch, snapshot ctx static, runtime cleanup
- `src/macos/EmulatorBridge.h`, `src/macos/EmulatorBridge.mm` — Objective-C wrappers
- `src/macos/EmulatorState.swift` — `canSaveSnapshot` polling
- `tests/snapshot_format_tests.c` (new), `tests/ArculatorCoreTests/SnapshotScopeTests.m` (new), `tests/ArculatorUITests/SnapshotMenuUITests.swift` (new)
- `tests/run_phase3_tests.sh` or new sibling — wire new test binary

## Reused existing code

- `emulation_command_queue_*` from `src/emulation_control.h` for the save command path.
- `dialog_util.h`'s `arc_choose_open_file` / `arc_choose_save_file` patterns for snapshot file pickers (currently inlined in `app_macos.mm:776` for disc change — same pattern works for snapshots).
- `EmulatorBridge.captureScreenshotToPath:` (`src/macos/EmulatorBridge.mm:147`) for preview PNG capture.
- `platform_path_join_support` and `ensure_dir_recursive` patterns from `src/platform_paths.c` for the runtime directory.
- `arc_print_error` (`src/macos/app_macos.mm:1309`) for posting errors back to AppKit alerts on the main thread.
- `config_load` / `config_get_string` / `config_set_string` / `config_save` (`src/config.c`) for rewriting the extracted runtime config.
- `cmos_load` / `cmos_save` are left unchanged — the synthetic `machine_config_name` redirects them naturally to per-snapshot files.

## Verification

End-to-end manual verification (covered in Phase 6) plus the automated tests:

```bash
# from project root
make                                # full build
./tests/phase3_tests                # existing tests still pass
./tests/snapshot_format_tests       # new format/scope tests
./tests/run_phase3_tests.sh         # umbrella runner
xcodebuild test -scheme ArculatorCoreTests   # CMOS, scope, etc.
xcodebuild test -scheme ArculatorUITests     # menu gating
```

Final manual smoke test (doc-style):
1. Start `Test Machine` config, boot RISC OS, pause, **Save Snapshot…** to `~/Desktop/test.arcsnap`.
2. Quit Arculator.
3. Reopen Arculator (no config arg), **Load Snapshot…** `~/Desktop/test.arcsnap`. Confirm session resumes from the exact paused point.
4. Verify `~/Library/Application Support/Arculator/cmos/Test Machine.*.cmos.bin` is unchanged after the loaded session.
5. Verify the original `.adf` files are unchanged after the loaded session writes data.

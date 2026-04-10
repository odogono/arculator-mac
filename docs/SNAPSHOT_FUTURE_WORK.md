# Snapshot System — Next Steps & Future Expansions

## Context

Arculator's floppy-only snapshot feature (`.arcsnap`) has been fully implemented per `docs/SNAPSHOT_IMPLEMENTATION_PLAN.md`. All six phases shipped in the recent commits (15346b0…661ba01):

- Chunked binary format + CRC32 + header validation (`src/snapshot.{h,c}`, `src/snapshot_chunks.h`)
- Per-subsystem `*_save_state` / `*_load_state` for 16 subsystems (ARM, CP15, FPA, MEM, MEMC, IOC, VIDC, KBD, CMOS, DS2401, SND, IOEB, LC, WD1770, 82C711, DISC, TIMR)
- Scope guards and `floppy_is_idle()` quiescence helper (`src/snapshot.c:889–937`, `src/disc.c:267`)
- Loader + runtime bundle + `arc_init_from_snapshot()` (`src/snapshot_load.c`, `src/main.c:241`)
- macOS menu items, EmulatorBridge wrappers, `canSaveSnapshot` polling, runtime-dir cleanup on session close (`src/macos/app_macos.mm:735` `shell_snapshot_session_cleanup`)
- Tests: `tests/snapshot_format_tests.c`, `tests/ArculatorCoreTests/SnapshotScopeTests.m`, `tests/ArculatorUITests/SnapshotMenuUITests.swift`

The v1 feature unblocks "resume where I left off" for the common case (floppy-based machines) but is deliberately narrow. This doc enumerates the logical next steps, ranked by value-for-effort, so we can pick the next milestone.

## Observed state (facts, not aspirations)

- **Preview PNG path is fully wired.** `capture_preview_png()` in `src/macos/EmulatorBridge.mm` runs on the UI thread before the save command is queued; `arc_save_snapshot()` carries the preview bytes (and an `arcsnap_meta_t`) through `emulation_command_t` to the emulation thread, which transfers ownership to `snapshot_save()`. New snapshots include a `PREV` chunk.
- **`META` chunk and summary reader API shipped.** `snapshot_peek_summary()` (`src/snapshot.c`) opens, parses `MNFT` + optional `META` + optional `PREV`, and closes without touching emulation state. `META` is informational only — load never depends on it. See `docs/SNAPSHOT_FORMAT.md` for the format spec.
- **Snapshot browser UI shipped.** `Load Snapshot…` opens an in-app browser page (`src/macos/SnapshotBrowserView.swift`, `SnapshotBrowserModel.swift`) that lists `.arcsnap` files in `<support>/snapshots/` with thumbnail, title, machine, timestamp, and floppy count. "Browse Other Location…" is the escape hatch for snapshots stored elsewhere.
- **Recent snapshots menu shipped.** `File → Open Recent Snapshot` lists the last 10 successfully opened snapshots, persisted via `NSUserDefaults` (`AppSettings.recentSnapshotPaths`). Missing files are pruned automatically.
- **Runtime cleanup is wired** — not a gap. `shell_snapshot_session_cleanup()` runs on session close and removes `<support>/snapshots/runtime/<id>/`.
- **Only macOS shell is wired.** The wxWidgets/SDL shell (`src/wx-sdl2.c`) has no snapshot menu items or command-queue handling.
- **No headless / CLI save/load.** Useful for CI-driven integration tests and scripted automation.
- **Manifest evolution is rigid today.** `MNFT` is decoded as an exact schema; changing its payload shape without a version bump and reader fallback would break older builds. Adding new optional summary chunks (like `META`) does not require a manifest bump.
- **Automation bridge hook exists.** `src/macos/AutomationScriptingCommands.mm` is a natural place to expose save/load to AppleScript.

## Recommended roadmap

Grouped by tier, ordered within each tier by dependency. Each item lists scope + rough effort + key files.

### Tier 1 — Finish v1 polish (small, high value)

**1.1 Wire preview PNG capture into the save flow** *(small)* — ✅ **Done**
- `capture_preview_png()` in `src/macos/EmulatorBridge.mm` captures via `captureScreenshotToPath:` and reads the bytes into a heap buffer before queueing the save command.
- `emulation_command_t` (`src/emulation_control.h`) carries `preview_png` / `preview_png_size` / `preview_width` / `preview_height` plus a `void *meta` pointer with documented ownership transfer.
- The emulation-thread handler at `src/macos/app_macos.mm` passes the bytes (and the `arcsnap_meta_t`) into `snapshot_save()` and frees both buffers after the save runs, regardless of success.

**1.2 Optional `META` chunk + summary reader API** *(small)* — ✅ **Done**
- `ARCSNAP_CHUNK_META` defined in `src/snapshot_chunks.h`. Encoder/decoder pair (`snapshot_writer_write_meta` / `snapshot_decode_meta`) in `src/snapshot.c` round-trips name, description, `created_at_unix_ms_utc`, and extensible host key/value properties.
- `snapshot_peek_summary(path, out_summary, err, err_size)` in `src/snapshot.c` opens, parses `MNFT` + optional `META` + optional `PREV`, then closes without touching emulation state. `snapshot_summary_dispose()` releases the heap-owned preview bytes.
- `snapshot_load.c` skips `META` cleanly during runtime preparation — load never depends on it.
- Test coverage: `tests/snapshot_format_tests.c` adds META round-trip + version + trailing-bytes negative tests; `tests/snapshot_summary_tests.c` exercises `snapshot_peek_summary` end-to-end.

**1.3 Snapshot browser / "Open Snapshot…" sheet with thumbnails** *(medium)* — ✅ **Done**
- `src/macos/SnapshotBrowserView.swift` + `SnapshotBrowserModel.swift` render an in-app browser page (not a sheet) showing thumbnail, display name, description, machine config, machine, timestamp, and floppy count for each `.arcsnap` in `<support>/snapshots/`.
- Backed by `snapshot_peek_summary` via `EmulatorBridge.peekSnapshotSummaryAtPath:error:` (`src/macos/EmulatorBridge.mm`); peek failures are logged and skipped so one corrupt file doesn't hide the rest.
- `MENU_FILE_LOAD_SNAPSHOT` opens the browser (via `MainSplitViewController.navigateToSnapshotBrowser` / `ContentHostingController.showSnapshotBrowser`); a "Browse Other Location…" button surfaces an `NSOpenPanel` for snapshots stored outside the default directory.

**1.4 CLI / command-line snapshot flags** *(small)*
- `arculator --save-snapshot <path>` / `arculator --load-snapshot <path>` so integration tests and scripting can drive save/load without a UI event loop.
- Hook into the existing arg parsing; load path reuses `arc_start_snapshot_session()`; save path requires a way to pause + save + quit (probably a `--save-snapshot-at-boot-done` style hook, or accept that v1.1 only wires load).
- Files: `src/main.c` or wherever argv parsing lives, `src/macos/main_macos.m`.

**1.5 AppleScript / automation commands** *(small)*
- Extend `src/macos/AutomationScriptingCommands.mm` with `save snapshot to <POSIX file>` and `load snapshot from <POSIX file>` verbs.
- Thin wrappers over `EmulatorBridge.saveSnapshotToPath:error:` / `startSnapshotSessionFromPath:error:`.
- Valuable for driving manual verification from a script.

**1.6 Snapshot "verify" standalone tool** *(small)*
- `tools/arcsnap-verify <file>` — reads header, walks all chunks, checks CRCs, prints manifest + chunk inventory. Non-invasive integrity check. Uses the core reader directly; no emulator linkage needed.
- Also prints optional `META` contents and flags duplicate or malformed descriptive chunks.
- Useful as a triage tool and as a golden-file regression gate in CI.
- Files: new `tools/arcsnap_verify.c`, `tests/Makefile` addition.

### Tier 2 — UX expansions (medium, directly user-visible)

**2.1 Quicksave / quickload slots** *(medium)*
- Standard emulator idiom: 10 hotkey-bound slots under `<support>/snapshots/quick/<machine>/slot<N>.arcsnap`.
- Hotkeys: F5/F8 (save/load current slot), Shift-F5/F8 (previous/next slot), number keys for direct slot selection.
- Requires a per-machine scoped slot directory so two different configs don't clobber each other.
- Needs keyboard capture carve-out: current input plumbing routes F-keys into the emulated keyboard, so these bindings need to intercept at the AppKit `keyDown:` level before the input pipeline.
- Files: new `src/macos/SnapshotSlots.swift` (or integrated into EmulatorState), input interception in the Metal view layer, possibly an `EmulatorBridge.quickSaveSlot:error:` pair.

**2.2 Recent snapshots menu** *(small)* — ✅ **Done**
- `File → Open Recent Snapshot` submenu populated from `AppSettings.recentSnapshotPaths`, persisted via `NSUserDefaults` (`ArculatorRecentSnapshotPaths`), capped at `AppSettings.maxRecentSnapshots = 10`, deduplicated, newest first.
- `pruneMissingRecentSnapshots()` filters out files that no longer exist; the dispatcher in `app_macos.mm` also removes a stale entry on the spot if the user picks a deleted file.
- Cocoa notification (`AppSettings.recentSnapshotsChangedNotification`) drives an automatic submenu rebuild from `app_macos.mm` whenever the recents list mutates.
- Future polish: thumbnail previews in the menu via `NSMenuItem.image` are not yet wired.

**2.3 Auto-resume on launch** *(small)*
- Optional setting: on quit, auto-save current state to a well-known slot (e.g. `<support>/snapshots/autosave.arcsnap`). On next launch with no explicit config, auto-load it.
- Guarded by the same `snapshot_can_save()` preflight; falls back to cold boot if the session wasn't snapshot-eligible.
- Needs the "save on quit" path to be synchronous enough to finish before the emulation thread is joined — `snapshot_save()` is already synchronous on the emulation thread, so the existing pause-then-save-then-stop ordering fits.

### Tier 3 — Format evolution (prophylactic, before schema pressure accumulates)

**3.1 Document the chunk/version bump policy** *(trivial)* — ✅ **Done**
- `docs/SNAPSHOT_FORMAT.md` ships the format spec: header fields, chunk inventory, per-chunk version semantics, ordering contract (`MNFT` first, optional summary chunks may follow, machine-state chunks last), and the rules for adding/deprecating chunks.
- `MNFT` is documented as load-critical and schema-stable; `META` and `PREV` are documented as optional summary/UI chunks that load must skip rather than depend on.

**3.2 Forward-compat smoke test corpus** *(small)*
- Check in 2–3 known-good `.arcsnap` files produced by the current build under `tests/fixtures/snapshots/`. On every commit, the test suite round-trips each fixture through `snapshot_open()` + `snapshot_apply_machine_state()` and asserts a post-load memory/register hash. Breaks loudly if any serializer accidentally changes its on-disk layout without a version bump.
- Include summary-focused fixtures too: `MNFT`-only, `MNFT+PREV`, `MNFT+META`, and `MNFT+META+PREV`, plus negative cases for malformed or duplicate `META`.

**3.3 Deterministic replay test harness** *(medium)*
- Load a snapshot, step N instructions, hash `(armregs, ram, memc, ioc, vidc)`, compare against a golden hash committed alongside the fixture. Proves end-to-end fidelity far more strongly than the current per-chunk round-trip tests.
- Requires a `arc_run_deterministic_instructions(uint64_t n)` helper on the core (which will also be valuable for future TAS work, item 6.3).

**3.4 Optional zstd/zlib compression for payloads** *(small, deferrable)*
- A new chunk flag bit: "payload is zstd-compressed." Reader decompresses transparently. Writer compresses chunks over a size threshold (e.g. `MEM ` once HDs are in scope).
- Not urgent for floppy-only (4MB RAM + ~800KB ADFs = ~5MB snapshots, fine uncompressed), but worth it before Tier 4.

### Tier 4 — Scope expansion (large, unblocks more users)

**4.1 Hard-disc support** *(large)* — **IDE done; ST506/SCSI deferred**
IDE hard-disc support has been implemented:
- **IDE controller serialization**: `ide_internal_save_state` / `ide_internal_load_state` (`src/ide.c`) with `HDIE` chunk and `ide_internal_is_idle()` quiescence check.
- **Media bundling**: inline bundling with zlib compression via new `MHDA` chunk (compressed HD media data). HD images are bundled into the snapshot, then decompressed on load.
- **Manifest v2**: `MNFT` version 2 extends v1 with HD records (drive index, path, file size, geometry). Floppy-only snapshots remain v1 for backward compatibility.
- **Scope guards**: `ARCSNAP_SCOPE_HAS_HD` removed from `ARCSNAP_SCOPE_UNSUPPORTED_MASK`. `snapshot_can_save()` allows IDE HD when the controller is idle; ST506 HD remains rejected.
- Files: `src/ide.c`, `src/snapshot.c`, `src/snapshot_load.c`, `src/snapshot_chunks.h`, `src/snapshot.h`, `src/snapshot_subsystems.h`.

Remaining sub-problems for future work:
- **ST506 controller serialization** (`src/st506.c`): needs save_state/load_state pair and `st506_internal_is_idle()`.
- **SCSI**: typically podule-based, deferred to 4.2 (podule framework).
- **Copy-on-write overlay**: deferrable optimisation to avoid bundling unchanged sectors.

**4.2 Generic podule save/load framework** *(large)*
- Add a `podule_ops_t` function-pointer block with optional `save_state` / `load_state` / `is_idle` / `snapshot_scope_flags` entries. Podules that leave these NULL continue to be rejected by `snapshot_can_save()`.
- Port known-stateless podules (arculator_rom already whitelisted; filestore, serial, parallel are candidates) to implement the ops as no-ops.
- Stateful podules (Econet, AKA32, SCSI cards) implement real serialization.
- Files: `src/podules.h`, `src/podules.c`, each podule implementation file under `src/podules/`.

**4.3 5th-column ROM + joystick interface** *(small, after 4.2)*
- Falls out naturally once the podule/peripheral-ops pattern exists.
- 5th-column is essentially static (ROM bytes), so serialization is trivial.
- Joystick runtime state is also small.

### Tier 5 — Cross-shell portability

**5.1 wxWidgets/SDL shell wiring** *(medium)*
- Port `EmulatorBridge` equivalents + menu items + command queue handling to `src/wx-sdl2.c`.
- Tests should run against both shells once wired; the XCTest suite stays macOS-only but the C-level `tests/snapshot_format_tests.c` becomes the portable gate.
- This is the prerequisite for shipping snapshots to the Linux/Windows builds.

### Tier 6 — Advanced features (moonshot)

**6.1 Rewind buffer** *(large)*
- Circular buffer of in-memory snapshots every N seconds, keeping the last M minutes. Requires either (a) `snapshot_save()` to support an in-memory sink as well as a file, or (b) an alternate memory-only serializer path.
- Memory budget: 10 slots × ~5MB = 50MB, acceptable.
- UX: "Rewind 5s" hotkey that pauses, loads the most recent pre-cursor snapshot, resumes.

**6.2 Live save (save while running)** *(large, architectural)*
- Drop the "must be paused" requirement. Requires an atomic quiescence point during emulation: either a short pause (few ms, invisible to user) or a lock-free serialization scheme.
- The cleanest route is to make the save command behave like "pause, save, resume" atomically on the emulation thread — which is already essentially free since `arc_save_snapshot` runs on that thread.
- Real live save (no pause at all) would require snapshotting while instructions execute, which is harder and not obviously worth it.

**6.3 Deterministic replay / TAS infrastructure** *(large)*
- Record input events alongside save states; replay them deterministically on load. Enables tool-assisted speedruns and regression tests ("play this input trace against this snapshot, assert the final frame hash").
- Builds on 3.3.

## "Snapshot UX v1.1" — shipped

Items 1.1, 1.2, 1.3, 2.2, and 3.1 have all landed. Only 3.2 (fixture corpus + round-trip smoke test) is still outstanding from the original v1.1 bundle — pick it up next so the format we just shipped is protected against accidental drift.

## Next milestone candidates

Tier 4.1 IDE hard-disc support has landed. The remaining short tasks form a tight "automation" bundle suitable for v1.2:
- Tier 1.4 (CLI flags)
- Tier 1.5 (AppleScript)
- Tier 1.6 (`arcsnap-verify` tool)

Then evaluate Tier 4.1 ST506 completion, Tier 4.2 (podule framework), or Tier 5.1 (wx shell) based on user demand.

## Critical files referenced

Current snapshot surface area the roadmap touches:

- **Core format & API**: `src/snapshot.h`, `src/snapshot.c`, `src/snapshot_load.c`, `src/snapshot_chunks.h`, `src/snapshot_subsystems.h`, `src/snapshot_internal.h`
- **Subsystem serializers**: `src/arm.c`, `src/cp15.c`, `src/fpa.c`, `src/mem.c`, `src/memc.c`, `src/ioc.c`, `src/vidc.c`, `src/keyboard.c`, `src/cmos.c`, `src/ds2401.c`, `src/sound.c`, `src/ioeb.c`, `src/lc.c`, `src/wd1770.c`, `src/82c711_fdc.c`, `src/disc.c`, `src/ide.c`, `src/timer.c`
- **Entry points**: `src/main.c:241` (`arc_init_from_snapshot`), `src/arc.h`
- **Platform paths**: `src/platform_paths.c:358–373`
- **macOS shell**: `src/macos/app_macos.mm` (menus: lines 51–52, 232–233, 463–464, 919–966; `arc_save_snapshot` at 1466; `arc_start_snapshot_session` at 1479; cleanup at 735), `src/macos/EmulatorBridge.{h,mm}` (lines 148–228), `src/macos/EmulatorState.swift` (lines 21, 83–85), `src/macos/AutomationScriptingCommands.mm`
- **Command queue**: `src/emulation_control.h` (`EMU_COMMAND_SAVE_SNAPSHOT`), `src/platform_shell.h`
- **Tests**: `tests/snapshot_format_tests.c`, `tests/ArculatorCoreTests/SnapshotScopeTests.m`, `tests/ArculatorUITests/SnapshotMenuUITests.swift`

## Verification strategy (per milestone)

For any follow-up milestone:

1. `make && ./tests/snapshot_format_tests` — format & scope unit tests still pass.
2. `./tests/run_phase3_tests.sh` — umbrella runner.
3. `xcodebuild test -scheme ArculatorCoreTests -scheme ArculatorUITests` — XCTest + UITest gates.
4. Manual smoke test documented in `docs/SNAPSHOT_IMPLEMENTATION_PLAN.md:291–300` (boot RISC OS, drop file in `!Scrap`, pause, save, quit, reload, verify state).
5. For Tier 3.2 once landed: fixture corpus auto-runs on each commit — no manual step needed.
6. For Tier 4.1 (HD): extend the manual smoke test to boot from HD and verify a write-then-snapshot-then-restore round trip preserves filesystem contents.

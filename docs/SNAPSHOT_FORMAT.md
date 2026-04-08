# Snapshot Format (`.arcsnap`)

This document describes Arculator's snapshot file format as implemented in the current tree, and the format-evolution rules future changes should follow.

The current codebase implements `MNFT`, `CFG `, `MEDA`, `PREV`, `META`, the subsystem-state chunks, and `END `.

## Goals

- Keep load-critical state explicit and deterministic.
- Allow readers to skip unknown chunks safely.
- Separate load-critical machine facts from optional UI/summary data.
- Make future format additions additive where possible.

## Encoding rules

- File extension: `.arcsnap`
- Byte order: little-endian
- Compression: none in the current implementation
- Integrity:
  - File header has its own CRC32
  - Every chunk payload has its own CRC32
  - `END ` is currently an empty sentinel chunk, not an overall-file CRC trailer

## File layout

Every snapshot is:

1. A fixed-size file header
2. Zero or more chunk records
3. A required `END ` chunk at the end of the stream

The current writer emits chunks in a stable order:

1. `MNFT`
2. `CFG `
3. `MEDA` chunks, one per mounted floppy
4. `PREV` if a preview PNG was supplied
5. `META` if descriptive metadata was supplied
6. Machine-state chunks (`CPU `, `CP15`, `FPA `, and so on)
7. `END `

Readers should be order-tolerant where practical, but some early-chunk rules are currently part of the contract:

- `MNFT` must be the first chunk
- `CFG ` must appear before machine-state chunks
- Runtime-preparation code understands `CFG `, `MEDA`, `PREV`, and `META` as pre-state chunks and skips unknown ones as part of its bail-out rule
- Any future summary chunk added before the machine-state section must be explicitly recognised by the runtime-preparation pass before it can be considered supported

## File header

On-disk layout:

```c
typedef struct {
    char     magic[8];          // "ARCSNAP\0"
    uint32_t format_version;    // currently 1
    uint32_t emulator_version;  // currently written as 0
    uint32_t flags;             // reserved, currently 0
    uint32_t header_crc32;      // CRC32 of the first 20 bytes
} arcsnap_header_t;
```

Rules:

- `magic` must be `ARCSNAP\0`
- `format_version` is the top-level file-format version
- `emulator_version` is reserved for producer identification
- `flags` is reserved for future file-wide flags
- `header_crc32` covers the header bytes before the CRC field itself

## Chunk framing

Every chunk has this header:

```c
typedef struct {
    uint32_t id;        // FourCC
    uint32_t version;   // per-chunk schema version
    uint64_t size;      // payload bytes only
    uint32_t crc32;     // CRC32 of payload
    uint32_t reserved;  // currently 0
} arcsnap_chunk_header_t;
```

Rules:

- `id` is a FourCC such as `MNFT`, `CFG `, `MEDA`, `PREV`, `CPU `
- `version` is owned by the chunk schema, not the whole file
- `size` does not include the chunk header itself
- `crc32` covers only the payload
- `reserved` must be written as `0`; readers should ignore it for now

## Current chunk inventory

### Summary and media chunks

| Chunk | Required | Current meaning |
| --- | --- | --- |
| `MNFT` | yes | Load-critical manifest: machine/config/media summary and scope flags |
| `CFG ` | yes | Original machine config file bytes |
| `MEDA` | conditional | One per mounted floppy, containing drive index plus raw media bytes |
| `PREV` | no | Encoded PNG preview used for snapshot browsing UI |
| `META` | no | Descriptive metadata: name, description, creation timestamp, host properties |

### Machine-state chunks

| Chunk | Required | Current meaning |
| --- | --- | --- |
| `CPU ` | yes | ARM core state |
| `CP15` | conditional | CP15 state when the machine has CP15 |
| `FPA ` | conditional | FPA state when enabled |
| `MEM ` | yes | RAM and memory mode |
| `MEMC` | yes | MEMC state |
| `IOC ` | yes | IOC state |
| `VIDC` | yes | VIDC state |
| `KBD ` | yes | Keyboard and mouse runtime state |
| `CMOS` | yes | CMOS and RTC state |
| `DS24` | yes | DS2401 state |
| `SND ` | yes | Sound runtime state |
| `IOEB` | yes in current v1 saves | IOEB state |
| `LC  ` | conditional | A4 LC state |
| `FDCW` | conditional | WD1770 FDC state |
| `FDCS` | conditional | 82C711 FDC state |
| `DISC` | yes | Disc subsystem runtime state |
| `TIMR` | yes | Global timer state |
| `END ` | yes | End-of-stream sentinel; current payload is empty |

## `MNFT` chunk

`MNFT` is the load-critical manifest. In the current implementation it is a strict schema, not a self-describing map.

Current payload order:

```text
u32    manifest_version
str    original_config_name
str    machine
i32    fdctype
i32    romset
i32    memsize
i32    machine_type
u32    scope_flags
i32    preview_width
i32    preview_height
u32    floppy_count
repeat floppy_count times:
  i32  drive_index
  str  original_path
  u64  file_size
  i32  write_protect
  str  extension
```

Current rules:

- `MNFT` must be the first chunk
- `manifest_version` is currently `1`
- The decoder rejects unsupported manifest versions
- The decoder also rejects trailing bytes
- Because of that, appending extra fields to `MNFT` is a breaking change unless the reader grows explicit fallback logic

### `MNFT` responsibilities

`MNFT` should contain only data required to:

- decide whether the snapshot is in supported scope
- prepare the runtime bundle
- load the machine with the right topology
- display basic, already-load-critical identity such as original config name

`MNFT` should not become a dumping ground for optional UI metadata.

## Scope flags

Current scope flag bits:

| Bit | Symbol | Meaning |
| --- | --- | --- |
| 0 | `ARCSNAP_SCOPE_HAS_CP15` | Snapshot includes CP15 state |
| 1 | `ARCSNAP_SCOPE_HAS_FPA` | Snapshot includes FPA state |
| 2 | `ARCSNAP_SCOPE_HAS_IOEB` | Snapshot includes IOEB state |
| 3 | `ARCSNAP_SCOPE_HAS_LC` | Snapshot includes A4 LC state |
| 4 | `ARCSNAP_SCOPE_HAS_PREV` | Snapshot includes a `PREV` chunk |
| 5 | `ARCSNAP_SCOPE_HAS_HD` | Hard-disc state present; unsupported in current v1 loader |
| 6 | `ARCSNAP_SCOPE_HAS_PODULE` | Podule state present; unsupported in current v1 loader |
| 7 | `ARCSNAP_SCOPE_HAS_5TH_COLUMN` | 5th-column ROM state present; unsupported in current v1 loader |
| 8 | `ARCSNAP_SCOPE_HAS_JOYSTICK` | Joystick state present; unsupported in current v1 loader |

Rules:

- Save-side code should set bits to describe what the snapshot contains
- Load-side code may reject snapshots whose scope exceeds current support
- Scope flags are declarations, not substitutes for actual chunk validation

## `PREV` chunk

Current meaning:

- Payload is a complete PNG byte stream
- `MNFT.preview_width` and `MNFT.preview_height` describe the display dimensions associated with the preview
- Preview decode failure should not prevent machine-state load, though browser/summary tooling may surface the problem

`PREV` is optional and purely descriptive. It must not affect emulation correctness.

## `META` chunk

`META` carries richer snapshot metadata without destabilising `MNFT`. It is the accepted way to add descriptive, non-load-critical data that browsers, verify tools, and catalog tooling can surface.

### Role

`META` holds descriptive, non-load-critical data such as:

- snapshot title (`name`)
- freeform description
- creation timestamp
- extensible properties like host OS name/version

### Payload shape

`META` is a single versioned record:

```text
u32    meta_version                 /* currently 1 */
str    name                         /* may be empty */
str    description                  /* may be empty */
u64    created_at_unix_ms_utc       /* wall-clock capture time */
u32    property_count               /* 0..ARCSNAP_META_MAX_PROPS */
repeat property_count times:
  str  key
  str  value
```

All strings are length-prefixed UTF-8 (same format as `MNFT` strings). Decoders enforce fixed upper bounds on each string so malformed input cannot bloat memory — the current caps live in `src/snapshot.h` as `ARCSNAP_META_MAX_*`.

Conventional property keys the macOS shell writes today:

- `host_os_name`
- `host_os_version`
- `emulator_version_string`

Tooling is free to read these, ignore them, or record additional keys.

### `META` rules

- `META` is informational only
- Absence of `META` is never a load failure
- Load must not depend on `META`
- Browser and verification tooling may parse and display `META`
- Duplicate `META` chunks are treated as malformed input
- Trailing bytes inside a `META` payload are rejected; extending `META` requires a version bump (`meta_version`)

## Reader behavior

### Current behavior in code

- File open validates header magic, file-format version, and header CRC
- Chunk iteration validates each chunk payload CRC before exposing it
- `snapshot_open()` requires `MNFT` to be the first chunk
- Runtime-preparation code extracts `CFG ` and `MEDA`, skips `PREV`, then stops at the first non-summary chunk
- Machine-state application ignores unknown state chunk IDs as no-ops

### Required behavior going forward

- Unknown chunk IDs should be skippable by default unless the loader is in a position where a specific chunk is mandatory
- New optional summary chunks must not silently interfere with runtime preparation
- Any early optional chunk added after `MNFT` must be explicitly recognized as skippable by the runtime-preparation pass

## Versioning policy

### Top-level file format version

Bump `format_version` only for changes that alter global framing semantics, not for ordinary chunk additions.

Examples:

- changing the file header layout
- changing chunk-header semantics
- changing the global endianness or framing rules

### Per-chunk version

Bump a chunk's `version` when that chunk's payload schema changes incompatibly.

Rules:

- Readers should reject chunk versions they do not understand when that chunk is required for correct loading
- Optional descriptive chunks may be ignored if their version is unknown, but tooling should report that clearly
- Do not change a chunk payload shape in place without a version bump

### `MNFT` special rule

`MNFT` is currently strict. If it needs new fields, choose one of these approaches explicitly:

1. Add a new optional chunk such as `META` instead
2. Introduce `MNFT` v2 and add reader fallback for both v1 and v2

Do not append fields to `MNFT` v1 and assume older readers will ignore them. They will not.

## Ordering policy

Current and recommended policy:

- `MNFT` is first
- Optional summary chunks come before machine-state chunks
- `CFG ` and `MEDA` remain part of the pre-state extraction region
- `END ` is last

If future chunks are added before machine-state data, document whether they belong to:

- the runtime-preparation phase
- the summary/browser phase only
- the machine-state application phase

## Validation and fixtures

At minimum, the format test corpus should cover:

- valid summary-reader fixture with `MNFT` only
- valid fully loadable snapshot with `MNFT + CFG + state + END`
- valid snapshot with `PREV`
- valid snapshot with `META`
- valid snapshot with `META + PREV`
- duplicate optional summary chunk (`META` or `PREV`)
- truncated chunk header
- truncated chunk payload
- bad header CRC
- bad chunk CRC
- unsupported `MNFT` version
- unsupported `META` version
- trailing bytes inside `META` payload

## Source of truth

This document should stay aligned with:

- [src/snapshot_chunks.h](/Users/alex/work/arculator-mac-github/src/snapshot_chunks.h)
- [src/snapshot.h](/Users/alex/work/arculator-mac-github/src/snapshot.h)
- [src/snapshot.c](/Users/alex/work/arculator-mac-github/src/snapshot.c)
- [src/snapshot_load.c](/Users/alex/work/arculator-mac-github/src/snapshot_load.c)

If the code and this document disagree, update one of them immediately. The format is too easy to accidentally fork by drift.

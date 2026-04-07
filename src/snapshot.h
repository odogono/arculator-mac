#ifndef SNAPSHOT_H
#define SNAPSHOT_H

#include <stddef.h>
#include <stdint.h>

#include "snapshot_chunks.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Public C API for the floppy-only snapshot feature (.arcsnap files).
 *
 * The format primitives, in-memory chunk writer/reader, and
 * header/manifest encode/decode helpers are implemented below. The
 * high-level save() flow and the loader's prepare_runtime() and
 * apply_machine_state() entry points are currently stubbed.
 */

/* ----- High level save/load API (callable by the shell). ------------- */

/* Captures a complete snapshot of the currently paused emulation to
 * `path`. `preview_png` may be NULL; otherwise it points at a fully
 * encoded PNG of size `preview_png_size` along with its display
 * dimensions. On failure, returns 0 and writes a human-readable
 * message into `error_buf`; on success, returns 1. */
int snapshot_save(const char *path,
                  const uint8_t *preview_png, size_t preview_png_size,
                  int preview_w, int preview_h,
                  char *error_buf, size_t error_buf_len);

/* Returns 1 if a snapshot can be saved right now, 0 otherwise.
 * On failure, writes a precise rejection reason to `error_buf`.
 * Currently stubbed; always returns 1. */
int snapshot_can_save(char *error_buf, size_t error_buf_len);

/* Opaque load context, lifecycle owned by snapshot_open / snapshot_close. */
typedef struct snapshot_load_ctx_t snapshot_load_ctx_t;

/* Opens a .arcsnap file, validates its header, and parses the
 * manifest. Returns NULL on failure with `error_buf` populated. */
snapshot_load_ctx_t *snapshot_open(const char *path,
                                   char *error_buf, size_t error_buf_len);

/* Extracts the embedded machine config and any media into a private
 * runtime directory under `<support>/snapshots/runtime/<id>/`. On
 * success, fills:
 *   - runtime_dir_out:    absolute path of the per-session directory
 *   - runtime_config_out: absolute path of the rebased machine config
 *   - runtime_name_out:   synthetic config name (`__snapshot_<id>`),
 *                         used to keep CMOS isolated
 * Currently stubbed; returns 0 with "not implemented". */
int snapshot_prepare_runtime(snapshot_load_ctx_t *ctx,
                             char *runtime_dir_out, size_t runtime_dir_out_len,
                             char *runtime_config_out, size_t runtime_config_out_len,
                             char *runtime_name_out, size_t runtime_name_out_len,
                             char *error_buf, size_t error_buf_len);

/* Applies the captured machine state on top of an already-initialised
 * emulation (i.e. immediately after `arc_init()` has been called against
 * the rebased runtime config). Currently stubbed; returns 1. */
int snapshot_apply_machine_state(snapshot_load_ctx_t *ctx,
                                 char *error_buf, size_t error_buf_len);

/* Returns the original (user-facing) machine_config_name from the
 * manifest, so the UI can show a sensible title even though the
 * runtime session uses a synthetic name. Returns NULL if `ctx` is
 * NULL or the manifest had no name. */
const char *snapshot_original_config_name(const snapshot_load_ctx_t *ctx);

/* Releases all resources held by a load context. Safe with NULL. */
void snapshot_close(snapshot_load_ctx_t *ctx);

/* ----- Manifest data type --------------------------------------------- */

typedef struct {
	int      drive_index;
	char     original_path[512];
	uint64_t file_size;
	int      write_protect;
	char     extension[16];
} arcsnap_manifest_floppy_t;

typedef struct {
	uint32_t                 version;            /* ARCSNAP_MNFT_VERSION */
	char                     original_config_name[256];
	char                     machine[16];
	int                      fdctype;
	int                      romset;
	int                      memsize;
	int                      machine_type;
	uint32_t                 scope_flags;
	int                      preview_width;
	int                      preview_height;
	int                      floppy_count;
	arcsnap_manifest_floppy_t floppies[4];
} arcsnap_manifest_t;

/* ----- Framework primitives ------------------------------------------- *
 *
 * The writer/reader are exposed in the public header so the
 * per-subsystem `*_save_state` / `*_load_state` functions can call
 * them. They operate on opaque heap-allocated objects, owning a
 * single in-memory growable buffer.
 */

typedef struct snapshot_writer_t snapshot_writer_t;
typedef struct snapshot_reader_t snapshot_reader_t;

/* --- Writer --- */

snapshot_writer_t *snapshot_writer_create(void);
void               snapshot_writer_destroy(snapshot_writer_t *w);

/* Writes the file header. Must be called exactly once before any chunks. */
int snapshot_writer_write_header(snapshot_writer_t *w);

/* Begin / end a chunk. Pairs must nest exactly once.
 * snapshot_writer_end_chunk backpatches size + CRC32. */
int snapshot_writer_begin_chunk(snapshot_writer_t *w, uint32_t id, uint32_t version);
int snapshot_writer_end_chunk(snapshot_writer_t *w);

/* Append payload bytes (only valid between begin_chunk / end_chunk,
 * unless explicitly noted otherwise). Returns 1 on success, 0 on OOM. */
int snapshot_writer_append(snapshot_writer_t *w, const void *data, size_t size);
int snapshot_writer_append_u8 (snapshot_writer_t *w, uint8_t  v);
int snapshot_writer_append_u16(snapshot_writer_t *w, uint16_t v);
int snapshot_writer_append_u32(snapshot_writer_t *w, uint32_t v);
int snapshot_writer_append_u64(snapshot_writer_t *w, uint64_t v);
int snapshot_writer_append_i32(snapshot_writer_t *w, int32_t  v);
/* Append a `double` (8 bytes, host bit pattern preserved as little-endian). */
int snapshot_writer_append_f64(snapshot_writer_t *w, double v);
/* Length-prefixed UTF-8 string (u32 length, then raw bytes, no NUL). */
int snapshot_writer_append_string(snapshot_writer_t *w, const char *s);

/* Writes the manifest as a single MNFT chunk. Convenience wrapper. */
int snapshot_writer_write_manifest(snapshot_writer_t *w, const arcsnap_manifest_t *manifest);

/* Persist the in-memory buffer to disk atomically (write to a tmp
 * sibling, then rename). Returns 1 on success, 0 on failure. */
int snapshot_writer_save_to_file(snapshot_writer_t *w, const char *path);

/* Returns a borrowed pointer into the writer's in-memory buffer
 * (valid until the writer is destroyed or further data is appended). */
const uint8_t *snapshot_writer_data(const snapshot_writer_t *w);
size_t         snapshot_writer_size(const snapshot_writer_t *w);

/* --- Reader --- */

/* Constructs a reader by loading the entire file into memory and
 * validating only the file-level header (magic, version, header CRC).
 * Per-chunk integrity is checked as chunks are iterated. */
snapshot_reader_t *snapshot_reader_open(const char *path,
                                        char *error_buf, size_t error_buf_len);

/* Constructs a reader from a memory buffer (used by tests). The
 * buffer is copied; the caller retains ownership of `data`. */
snapshot_reader_t *snapshot_reader_open_mem(const void *data, size_t size,
                                            char *error_buf, size_t error_buf_len);

void snapshot_reader_close(snapshot_reader_t *r);

/* Returns the validated file header. */
const arcsnap_header_t *snapshot_reader_header(const snapshot_reader_t *r);

/* Iterates chunks. Returns 1 if a chunk was read (and validated),
 * 0 if EOF was reached cleanly. On failure, returns -1 and writes
 * to `error_buf`. The returned `payload_out` pointer is owned by the
 * reader and is valid until the next call or close. */
int snapshot_reader_next_chunk(snapshot_reader_t *r,
                               uint32_t *id_out, uint32_t *version_out,
                               const uint8_t **payload_out, uint64_t *size_out,
                               char *error_buf, size_t error_buf_len);

/* Manifest helpers (operate on a payload buffer that came from
 * snapshot_reader_next_chunk for an MNFT chunk). */
int snapshot_decode_manifest(const uint8_t *payload, uint64_t size,
                             arcsnap_manifest_t *out,
                             char *error_buf, size_t error_buf_len);

/* CRC32 (IEEE 802.3, init 0xFFFFFFFF, final XOR 0xFFFFFFFF). */
uint32_t snapshot_crc32(const void *data, size_t size);

/* ----- Payload reader -------------------------------------------------- *
 *
 * Each subsystem's `*_load_state` function uses one of these to walk over
 * the bytes of a single chunk's payload. Bounds-checking is centralised
 * in the helpers; once an underflow is hit the reader latches into a
 * not-ok state and every subsequent read becomes a no-op.
 */

typedef struct snapshot_payload_reader_t {
	const uint8_t *data;
	size_t         size;
	size_t         cursor;
	int            ok;
} snapshot_payload_reader_t;

void snapshot_payload_reader_init(snapshot_payload_reader_t *r,
                                  const uint8_t *data, size_t size);
int  snapshot_payload_reader_ok(const snapshot_payload_reader_t *r);
int  snapshot_payload_reader_at_end(const snapshot_payload_reader_t *r);
int  snapshot_payload_reader_read(snapshot_payload_reader_t *r,
                                  void *dest, size_t size);
int  snapshot_payload_reader_skip(snapshot_payload_reader_t *r, size_t size);
int  snapshot_payload_reader_read_u8 (snapshot_payload_reader_t *r, uint8_t  *out);
int  snapshot_payload_reader_read_u16(snapshot_payload_reader_t *r, uint16_t *out);
int  snapshot_payload_reader_read_u32(snapshot_payload_reader_t *r, uint32_t *out);
int  snapshot_payload_reader_read_u64(snapshot_payload_reader_t *r, uint64_t *out);
int  snapshot_payload_reader_read_i32(snapshot_payload_reader_t *r, int32_t  *out);
int  snapshot_payload_reader_read_f64(snapshot_payload_reader_t *r, double   *out);

#ifdef __cplusplus
}
#endif

#endif /* SNAPSHOT_H */

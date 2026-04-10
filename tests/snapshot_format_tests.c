/*
 * Phase 1 tests for the snapshot file format primitives.
 *
 * Build:   tests/run_snapshot_format_tests.sh
 * Tests:   header round-trip, header rejection (bad magic / version / CRC),
 *          chunk writer/reader round-trip with multiple chunks,
 *          manifest encode/decode round-trip,
 *          truncated file rejection.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "config.h"
#include "snapshot.h"
#include "snapshot_chunks.h"

/* ----- tiny test runner ----------------------------------------------- */

static int g_failures = 0;
static const char *g_current_test = "(none)";

#define EXPECT_TRUE(cond, msg) do {                                         \
		if (!(cond)) {                                                       \
			fprintf(stderr, "FAIL %s: %s\n", g_current_test, (msg));         \
			g_failures++;                                                    \
		}                                                                    \
	} while (0)

#define EXPECT_EQ_INT(actual, expected, msg) do {                            \
		long long _a = (long long)(actual);                                  \
		long long _e = (long long)(expected);                                \
		if (_a != _e) {                                                      \
			fprintf(stderr,                                                  \
			        "FAIL %s: %s (got %lld, expected %lld)\n",               \
			        g_current_test, (msg), _a, _e);                          \
			g_failures++;                                                    \
		}                                                                    \
	} while (0)

#define EXPECT_EQ_STR(actual, expected, msg) do {                            \
		const char *_a = (actual) ? (actual) : "(null)";                     \
		const char *_e = (expected) ? (expected) : "(null)";                 \
		if (strcmp(_a, _e) != 0) {                                           \
			fprintf(stderr,                                                  \
			        "FAIL %s: %s (got '%s', expected '%s')\n",               \
			        g_current_test, (msg), _a, _e);                          \
			g_failures++;                                                    \
		}                                                                    \
	} while (0)

/* ----- Phase 3 scope-guard test fixtures ------------------------------ *
 *
 * snapshot_can_save() inspects a handful of emulator-wide globals plus
 * the helpers arc_is_paused() and floppy_is_idle(). The format-test
 * binary stands alone (it only links src/snapshot.c), so we provide
 * test-controlled definitions here. Each test resets the fixture to
 * a known-good state before flipping a single field.
 */

int  st506_present       = 0;
int  fdctype             = FDC_WD1770;
char hd_fn[2][512]       = {{0}, {0}};
char podule_names[4][16] = {{0}, {0}, {0}, {0}};
char joystick_if[16]     = {0};
char _5th_column_fn[512] = {0};

static int g_test_paused      = 1;
static int g_test_floppy_idle = 1;
static int g_test_ide_idle    = 1;

int arc_is_paused(void) { return g_test_paused; }
int floppy_is_idle(void) { return g_test_floppy_idle; }
int ide_internal_is_idle(void) { return g_test_ide_idle; }

static void scope_reset_fixture(void)
{
	int i;
	g_test_paused      = 1;
	g_test_floppy_idle = 1;
	g_test_ide_idle    = 1;
	st506_present      = 0;
	fdctype            = FDC_WD1770;
	hd_fn[0][0]        = 0;
	hd_fn[1][0]        = 0;
	for (i = 0; i < 4; i++)
		podule_names[i][0] = 0;
	joystick_if[0]     = 0;
	_5th_column_fn[0]  = 0;
}

/* ----- helpers -------------------------------------------------------- */

static snapshot_writer_t *make_writer_with_header(void)
{
	snapshot_writer_t *w = snapshot_writer_create();
	if (!w) return NULL;
	if (!snapshot_writer_write_header(w))
	{
		snapshot_writer_destroy(w);
		return NULL;
	}
	return w;
}

static void fill_test_manifest(arcsnap_manifest_t *m)
{
	memset(m, 0, sizeof(*m));
	m->version = ARCSNAP_MNFT_VERSION;
	snprintf(m->original_config_name, sizeof(m->original_config_name), "Test Machine");
	snprintf(m->machine, sizeof(m->machine), "a3000");
	m->fdctype       = 0;
	m->romset        = 5;
	m->memsize       = 4096;
	m->machine_type  = 0;
	m->scope_flags   = ARCSNAP_SCOPE_HAS_PREV;
	m->preview_width  = 640;
	m->preview_height = 512;
	m->floppy_count  = 2;

	m->floppies[0].drive_index = 0;
	snprintf(m->floppies[0].original_path, sizeof(m->floppies[0].original_path),
	         "/Users/test/work.adf");
	m->floppies[0].file_size = 819200;
	m->floppies[0].write_protect = 0;
	snprintf(m->floppies[0].extension, sizeof(m->floppies[0].extension), "adf");

	m->floppies[1].drive_index = 1;
	snprintf(m->floppies[1].original_path, sizeof(m->floppies[1].original_path),
	         "/Users/test/games.hfe");
	m->floppies[1].file_size = 1474560;
	m->floppies[1].write_protect = 1;
	snprintf(m->floppies[1].extension, sizeof(m->floppies[1].extension), "hfe");
}

/* ----- header round trip ---------------------------------------------- */

static void test_header_round_trip(void)
{
	snapshot_writer_t *w;
	snapshot_reader_t *r;
	const arcsnap_header_t *h;
	char err[256] = {0};

	g_current_test = "header_round_trip";

	w = snapshot_writer_create();
	EXPECT_TRUE(w != NULL, "writer create");
	EXPECT_TRUE(snapshot_writer_write_header(w), "write header");
	EXPECT_EQ_INT(snapshot_writer_size(w), 24, "header is 24 bytes");

	r = snapshot_reader_open_mem(snapshot_writer_data(w), snapshot_writer_size(w),
	                             err, sizeof(err));
	EXPECT_TRUE(r != NULL, err);
	if (r)
	{
		h = snapshot_reader_header(r);
		EXPECT_TRUE(h != NULL, "header pointer");
		EXPECT_EQ_INT(memcmp(h->magic, ARCSNAP_MAGIC, ARCSNAP_MAGIC_SIZE), 0, "magic matches");
		EXPECT_EQ_INT(h->format_version, ARCSNAP_FORMAT_VERSION, "format version matches");
	}
	snapshot_reader_close(r);
	snapshot_writer_destroy(w);
}

/* ----- header rejection ----------------------------------------------- */

static void test_header_bad_magic(void)
{
	snapshot_writer_t *w;
	snapshot_reader_t *r;
	uint8_t buf[24];
	char err[256] = {0};

	g_current_test = "header_bad_magic";

	w = snapshot_writer_create();
	EXPECT_TRUE(snapshot_writer_write_header(w), "write header");
	EXPECT_EQ_INT(snapshot_writer_size(w), sizeof(buf), "expected 24 bytes");
	memcpy(buf, snapshot_writer_data(w), sizeof(buf));
	snapshot_writer_destroy(w);

	buf[0] = 'X';
	r = snapshot_reader_open_mem(buf, sizeof(buf), err, sizeof(err));
	EXPECT_TRUE(r == NULL, "reader should reject bad magic");
	EXPECT_TRUE(err[0] != 0, "error message should be set for bad magic");
	snapshot_reader_close(r);
}

static void test_header_bad_version(void)
{
	snapshot_writer_t *w;
	snapshot_reader_t *r;
	uint8_t buf[24];
	char err[256] = {0};
	uint32_t crc;

	g_current_test = "header_bad_version";

	w = snapshot_writer_create();
	EXPECT_TRUE(snapshot_writer_write_header(w), "write header");
	memcpy(buf, snapshot_writer_data(w), sizeof(buf));
	snapshot_writer_destroy(w);

	/* Bump format_version to an invalid value, then recompute CRC so the
	 * version check (not the CRC check) is what trips. */
	buf[8]  = 99;
	buf[9]  = 0;
	buf[10] = 0;
	buf[11] = 0;
	crc = snapshot_crc32(buf, 20);
	buf[20] = (uint8_t)(crc        & 0xff);
	buf[21] = (uint8_t)((crc >>  8) & 0xff);
	buf[22] = (uint8_t)((crc >> 16) & 0xff);
	buf[23] = (uint8_t)((crc >> 24) & 0xff);

	r = snapshot_reader_open_mem(buf, sizeof(buf), err, sizeof(err));
	EXPECT_TRUE(r == NULL, "reader should reject unknown version");
	EXPECT_TRUE(strstr(err, "version") != NULL, "error should mention version");
	snapshot_reader_close(r);
}

static void test_header_bad_crc(void)
{
	snapshot_writer_t *w;
	snapshot_reader_t *r;
	uint8_t buf[24];
	char err[256] = {0};

	g_current_test = "header_bad_crc";

	w = snapshot_writer_create();
	EXPECT_TRUE(snapshot_writer_write_header(w), "write header");
	memcpy(buf, snapshot_writer_data(w), sizeof(buf));
	snapshot_writer_destroy(w);

	buf[20] ^= 0xff; /* corrupt CRC */
	r = snapshot_reader_open_mem(buf, sizeof(buf), err, sizeof(err));
	EXPECT_TRUE(r == NULL, "reader should reject bad CRC");
	EXPECT_TRUE(strstr(err, "CRC") != NULL, "error should mention CRC");
	snapshot_reader_close(r);
}

/* ----- chunk round trip ----------------------------------------------- */

static void test_chunk_round_trip(void)
{
	snapshot_writer_t *w;
	snapshot_reader_t *r;
	uint32_t id, version;
	const uint8_t *payload;
	uint64_t payload_size;
	int rc;
	char err[256] = {0};

	g_current_test = "chunk_round_trip";

	w = make_writer_with_header();
	EXPECT_TRUE(w != NULL, "writer + header");

	/* Chunk 1: a few primitives. */
	EXPECT_TRUE(snapshot_writer_begin_chunk(w, ARCSNAP_CHUNK_CPU, 1), "begin CPU chunk");
	EXPECT_TRUE(snapshot_writer_append_u32(w, 0xdeadbeefu), "append u32");
	EXPECT_TRUE(snapshot_writer_append_u64(w, 0x0123456789abcdefULL), "append u64");
	EXPECT_TRUE(snapshot_writer_append_string(w, "hello"), "append string");
	EXPECT_TRUE(snapshot_writer_end_chunk(w), "end CPU chunk");

	/* Chunk 2: raw bytes. */
	{
		const uint8_t bytes[] = {1, 2, 3, 4, 5, 6, 7, 8};
		EXPECT_TRUE(snapshot_writer_begin_chunk(w, ARCSNAP_CHUNK_MEM, 2), "begin MEM chunk");
		EXPECT_TRUE(snapshot_writer_append(w, bytes, sizeof(bytes)), "append bytes");
		EXPECT_TRUE(snapshot_writer_end_chunk(w), "end MEM chunk");
	}

	r = snapshot_reader_open_mem(snapshot_writer_data(w), snapshot_writer_size(w),
	                             err, sizeof(err));
	EXPECT_TRUE(r != NULL, err);

	/* Chunk 1 */
	rc = snapshot_reader_next_chunk(r, &id, &version, &payload, &payload_size,
	                                err, sizeof(err));
	EXPECT_EQ_INT(rc, 1, "first next_chunk should succeed");
	EXPECT_EQ_INT(id, ARCSNAP_CHUNK_CPU, "first chunk id is CPU");
	EXPECT_EQ_INT(version, 1, "first chunk version is 1");
	EXPECT_EQ_INT(payload_size, 4 + 8 + 4 + 5, "first chunk payload size");
	{
		uint32_t v32 = (uint32_t)payload[0] |
		               ((uint32_t)payload[1] << 8) |
		               ((uint32_t)payload[2] << 16) |
		               ((uint32_t)payload[3] << 24);
		EXPECT_EQ_INT(v32, 0xdeadbeefu, "first u32 round-trips");

		uint32_t string_len = (uint32_t)payload[12] |
		                      ((uint32_t)payload[13] << 8) |
		                      ((uint32_t)payload[14] << 16) |
		                      ((uint32_t)payload[15] << 24);
		EXPECT_EQ_INT(string_len, 5, "string length round-trips");
		EXPECT_EQ_INT(memcmp(payload + 16, "hello", 5), 0, "string contents round-trip");
	}

	/* Chunk 2 */
	rc = snapshot_reader_next_chunk(r, &id, &version, &payload, &payload_size,
	                                err, sizeof(err));
	EXPECT_EQ_INT(rc, 1, "second next_chunk should succeed");
	EXPECT_EQ_INT(id, ARCSNAP_CHUNK_MEM, "second chunk id is MEM");
	EXPECT_EQ_INT(version, 2, "second chunk version is 2");
	EXPECT_EQ_INT(payload_size, 8, "second chunk payload size");
	{
		const uint8_t expected[] = {1, 2, 3, 4, 5, 6, 7, 8};
		EXPECT_EQ_INT(memcmp(payload, expected, sizeof(expected)), 0, "MEM payload contents");
	}

	/* EOF */
	rc = snapshot_reader_next_chunk(r, &id, &version, &payload, &payload_size,
	                                err, sizeof(err));
	EXPECT_EQ_INT(rc, 0, "third next_chunk should hit EOF");

	snapshot_reader_close(r);
	snapshot_writer_destroy(w);
}

/* ----- chunk CRC corruption ------------------------------------------- */

static void test_chunk_corruption_detected(void)
{
	snapshot_writer_t *w;
	snapshot_reader_t *r;
	uint8_t *buf;
	size_t   size;
	uint32_t id, version;
	const uint8_t *payload;
	uint64_t payload_size;
	int rc;
	char err[256] = {0};

	g_current_test = "chunk_corruption_detected";

	w = make_writer_with_header();
	EXPECT_TRUE(snapshot_writer_begin_chunk(w, ARCSNAP_CHUNK_CPU, 1), "begin chunk");
	EXPECT_TRUE(snapshot_writer_append_u32(w, 0x12345678u), "append");
	EXPECT_TRUE(snapshot_writer_end_chunk(w), "end chunk");

	size = snapshot_writer_size(w);
	buf = (uint8_t *)malloc(size);
	memcpy(buf, snapshot_writer_data(w), size);
	snapshot_writer_destroy(w);

	/* Flip a bit in the chunk payload (just past the chunk header). */
	buf[ARCSNAP_HEADER_DISK_SIZE + ARCSNAP_CHUNK_HEADER_DISK_SIZE] ^= 0x01;

	r = snapshot_reader_open_mem(buf, size, err, sizeof(err));
	EXPECT_TRUE(r != NULL, err); /* file header is still valid */
	if (r)
	{
		rc = snapshot_reader_next_chunk(r, &id, &version, &payload, &payload_size,
		                                err, sizeof(err));
		EXPECT_EQ_INT(rc, -1, "corrupted chunk should be rejected");
		EXPECT_TRUE(strstr(err, "CRC") != NULL, "error should mention CRC");
	}
	snapshot_reader_close(r);
	free(buf);
}

/* ----- truncation rejection ------------------------------------------- */

static void test_truncated_header(void)
{
	uint8_t buf[10] = {0};
	snapshot_reader_t *r;
	char err[256] = {0};

	g_current_test = "truncated_header";

	r = snapshot_reader_open_mem(buf, sizeof(buf), err, sizeof(err));
	EXPECT_TRUE(r == NULL, "reader should reject truncated header");
	EXPECT_TRUE(err[0] != 0, "error message should be set");
}

static void test_truncated_chunk_header(void)
{
	snapshot_writer_t *w;
	snapshot_reader_t *r;
	uint32_t id, version;
	const uint8_t *payload;
	uint64_t payload_size;
	int rc;
	uint8_t *buf;
	size_t size;
	char err[256] = {0};

	g_current_test = "truncated_chunk_header";

	w = make_writer_with_header();
	EXPECT_TRUE(snapshot_writer_begin_chunk(w, ARCSNAP_CHUNK_CPU, 1), "begin chunk");
	EXPECT_TRUE(snapshot_writer_append_u32(w, 0xaabbccddu), "append");
	EXPECT_TRUE(snapshot_writer_end_chunk(w), "end chunk");

	/* Drop the last 8 bytes so the chunk header itself is missing fields. */
	size = snapshot_writer_size(w) - 8;
	buf  = (uint8_t *)malloc(size);
	memcpy(buf, snapshot_writer_data(w), size);
	snapshot_writer_destroy(w);

	r = snapshot_reader_open_mem(buf, size, err, sizeof(err));
	EXPECT_TRUE(r != NULL, err);
	if (r)
	{
		rc = snapshot_reader_next_chunk(r, &id, &version, &payload, &payload_size,
		                                err, sizeof(err));
		EXPECT_EQ_INT(rc, -1, "truncated chunk should be rejected");
		EXPECT_TRUE(strstr(err, "truncated") != NULL || strstr(err, "EOF") != NULL,
		            "error should mention truncation");
	}
	snapshot_reader_close(r);
	free(buf);
}

static void test_truncated_chunk_payload(void)
{
	snapshot_writer_t *w;
	snapshot_reader_t *r;
	uint32_t id, version;
	const uint8_t *payload;
	uint64_t payload_size;
	int rc;
	uint8_t *buf;
	size_t size;
	char err[256] = {0};

	g_current_test = "truncated_chunk_payload";

	w = make_writer_with_header();
	EXPECT_TRUE(snapshot_writer_begin_chunk(w, ARCSNAP_CHUNK_MEM, 1), "begin chunk");
	{
		uint8_t bytes[16];
		size_t i;
		for (i = 0; i < sizeof(bytes); i++) bytes[i] = (uint8_t)i;
		EXPECT_TRUE(snapshot_writer_append(w, bytes, sizeof(bytes)), "append");
	}
	EXPECT_TRUE(snapshot_writer_end_chunk(w), "end chunk");

	/* Lose the last few payload bytes only — header still claims 16. */
	size = snapshot_writer_size(w) - 4;
	buf  = (uint8_t *)malloc(size);
	memcpy(buf, snapshot_writer_data(w), size);
	snapshot_writer_destroy(w);

	r = snapshot_reader_open_mem(buf, size, err, sizeof(err));
	EXPECT_TRUE(r != NULL, err);
	if (r)
	{
		rc = snapshot_reader_next_chunk(r, &id, &version, &payload, &payload_size,
		                                err, sizeof(err));
		EXPECT_EQ_INT(rc, -1, "truncated payload should be rejected");
	}
	snapshot_reader_close(r);
	free(buf);
}

/* ----- manifest round trip -------------------------------------------- */

static void test_manifest_round_trip(void)
{
	snapshot_writer_t *w;
	snapshot_reader_t *r;
	arcsnap_manifest_t in, out;
	uint32_t id, version;
	const uint8_t *payload;
	uint64_t payload_size;
	int rc;
	char err[256] = {0};

	g_current_test = "manifest_round_trip";

	fill_test_manifest(&in);

	w = make_writer_with_header();
	EXPECT_TRUE(snapshot_writer_write_manifest(w, &in), "write manifest");

	r = snapshot_reader_open_mem(snapshot_writer_data(w), snapshot_writer_size(w),
	                             err, sizeof(err));
	EXPECT_TRUE(r != NULL, err);

	rc = snapshot_reader_next_chunk(r, &id, &version, &payload, &payload_size,
	                                err, sizeof(err));
	EXPECT_EQ_INT(rc, 1, "manifest chunk read");
	EXPECT_EQ_INT(id, ARCSNAP_CHUNK_MNFT, "chunk id is MNFT");
	EXPECT_EQ_INT(version, ARCSNAP_MNFT_VERSION, "chunk version is MNFT v1");

	memset(&out, 0xcc, sizeof(out));
	EXPECT_TRUE(snapshot_decode_manifest(payload, payload_size, &out, err, sizeof(err)),
	            "decode manifest");

	EXPECT_EQ_INT(out.version, in.version, "version round-trips");
	EXPECT_EQ_STR(out.original_config_name, in.original_config_name, "config name");
	EXPECT_EQ_STR(out.machine, in.machine, "machine");
	EXPECT_EQ_INT(out.fdctype, in.fdctype, "fdctype");
	EXPECT_EQ_INT(out.romset, in.romset, "romset");
	EXPECT_EQ_INT(out.memsize, in.memsize, "memsize");
	EXPECT_EQ_INT(out.machine_type, in.machine_type, "machine_type");
	EXPECT_EQ_INT(out.scope_flags, in.scope_flags, "scope_flags");
	EXPECT_EQ_INT(out.preview_width, in.preview_width, "preview_width");
	EXPECT_EQ_INT(out.preview_height, in.preview_height, "preview_height");
	EXPECT_EQ_INT(out.floppy_count, in.floppy_count, "floppy_count");

	{
		int i;
		for (i = 0; i < in.floppy_count; i++)
		{
			char where[64];
			snprintf(where, sizeof(where), "floppy[%d].drive_index", i);
			EXPECT_EQ_INT(out.floppies[i].drive_index, in.floppies[i].drive_index, where);

			snprintf(where, sizeof(where), "floppy[%d].original_path", i);
			EXPECT_EQ_STR(out.floppies[i].original_path, in.floppies[i].original_path, where);

			snprintf(where, sizeof(where), "floppy[%d].file_size", i);
			EXPECT_EQ_INT(out.floppies[i].file_size, in.floppies[i].file_size, where);

			snprintf(where, sizeof(where), "floppy[%d].write_protect", i);
			EXPECT_EQ_INT(out.floppies[i].write_protect, in.floppies[i].write_protect, where);

			snprintf(where, sizeof(where), "floppy[%d].extension", i);
			EXPECT_EQ_STR(out.floppies[i].extension, in.floppies[i].extension, where);
		}
	}

	snapshot_reader_close(r);
	snapshot_writer_destroy(w);
}

/* ----- file save round trip ------------------------------------------- */

static void test_file_save_round_trip(void)
{
	snapshot_writer_t *w;
	snapshot_reader_t *r;
	arcsnap_manifest_t in, out;
	uint32_t id, version;
	const uint8_t *payload;
	uint64_t payload_size;
	int rc;
	char err[256] = {0};
	const char *path = "snapshot_format_tests.arcsnap";

	g_current_test = "file_save_round_trip";
	remove(path);

	fill_test_manifest(&in);
	w = make_writer_with_header();
	EXPECT_TRUE(snapshot_writer_write_manifest(w, &in), "write manifest");
	EXPECT_TRUE(snapshot_writer_save_to_file(w, path), "save to file");
	snapshot_writer_destroy(w);

	r = snapshot_reader_open(path, err, sizeof(err));
	EXPECT_TRUE(r != NULL, err);
	rc = snapshot_reader_next_chunk(r, &id, &version, &payload, &payload_size,
	                                err, sizeof(err));
	EXPECT_EQ_INT(rc, 1, "next_chunk after file open");
	EXPECT_EQ_INT(id, ARCSNAP_CHUNK_MNFT, "first chunk MNFT");
	EXPECT_TRUE(snapshot_decode_manifest(payload, payload_size, &out, err, sizeof(err)),
	            "decode manifest from file");
	EXPECT_EQ_STR(out.original_config_name, in.original_config_name, "name from file");

	snapshot_reader_close(r);
	remove(path);
}

/* ----- end-to-end multi-chunk save/load roundtrip --------------------- *
 *
 * Simulates a realistic .arcsnap file: manifest + several state-like
 * chunks written in the Phase 2 order, persisted to disk, then reopened
 * and walked. Asserts every chunk comes back byte-for-byte identical,
 * that scope flags survive the round-trip, and that the cursor save /
 * restore API can rewind through the state chunks.
 *
 * This test operates purely on the file-format primitives (no
 * per-subsystem serializers are called), which keeps the test binary
 * standalone while still exercising the full MNFT + N-chunk shape that
 * the loader will see in production.
 */

/* One chunk per major subsystem in the Phase 2 order — not exhaustive,
 * but enough to verify the loader can walk a multi-chunk file. Each
 * payload is seeded with a distinct pattern so corrupted contents or
 * mis-ordered reads fail the byte-for-byte comparison below. */
typedef struct e2e_state_chunk_t {
	uint32_t id;
	uint32_t version;
	uint8_t  seed;
	size_t   payload_size;
	uint8_t  payload[64];
} e2e_state_chunk_t;

static e2e_state_chunk_t e2e_chunks[] = {
	{ ARCSNAP_CHUNK_CPU,  1, 0x10, 40, {0} },
	{ ARCSNAP_CHUNK_MEM,  1, 0x20, 64, {0} },
	{ ARCSNAP_CHUNK_MEMC, 1, 0x30, 48, {0} },
	{ ARCSNAP_CHUNK_IOC,  1, 0x40, 32, {0} },
	{ ARCSNAP_CHUNK_VIDC, 1, 0x50, 56, {0} },
	{ ARCSNAP_CHUNK_CMOS, 1, 0x60, 24, {0} },
	{ ARCSNAP_CHUNK_DISC, 1, 0x70, 16, {0} },
	{ ARCSNAP_CHUNK_END,  1, 0x80,  4, {0} },
};
#define E2E_CHUNK_COUNT (sizeof(e2e_chunks) / sizeof(e2e_chunks[0]))

static void e2e_fill_payloads(void)
{
	size_t i, j;
	for (i = 0; i < E2E_CHUNK_COUNT; i++)
		for (j = 0; j < e2e_chunks[i].payload_size; j++)
			e2e_chunks[i].payload[j] = (uint8_t)(e2e_chunks[i].seed + j * 7);
}

static void test_end_to_end_roundtrip(void)
{
	const char *path = "snapshot_format_tests_e2e.arcsnap";
	snapshot_writer_t *w;
	snapshot_reader_t *r;
	arcsnap_manifest_t in_manifest, out_manifest;
	size_t i;
	uint32_t id, version;
	const uint8_t *payload;
	uint64_t payload_size;
	int rc;
	char err[256] = {0};
	size_t after_manifest_cursor;

	g_current_test = "end_to_end_roundtrip";
	remove(path);
	e2e_fill_payloads();

	/* Build a manifest with all optional scope flags set so we can
	 * verify they survive save/load unchanged. */
	fill_test_manifest(&in_manifest);
	in_manifest.scope_flags = ARCSNAP_SCOPE_HAS_CP15 |
	                          ARCSNAP_SCOPE_HAS_FPA  |
	                          ARCSNAP_SCOPE_HAS_IOEB |
	                          ARCSNAP_SCOPE_HAS_PREV;

	/* ----- Write ------------------------------------------------------ */
	w = make_writer_with_header();
	EXPECT_TRUE(w != NULL, "writer + header");
	EXPECT_TRUE(snapshot_writer_write_manifest(w, &in_manifest), "write manifest");

	for (i = 0; i < E2E_CHUNK_COUNT; i++)
	{
		EXPECT_TRUE(snapshot_writer_begin_chunk(w, e2e_chunks[i].id, e2e_chunks[i].version),
		            "begin state chunk");
		EXPECT_TRUE(snapshot_writer_append(w, e2e_chunks[i].payload, e2e_chunks[i].payload_size),
		            "append state chunk payload");
		EXPECT_TRUE(snapshot_writer_end_chunk(w), "end state chunk");
	}

	EXPECT_TRUE(snapshot_writer_save_to_file(w, path), "save to file");
	snapshot_writer_destroy(w);

	/* ----- Read ------------------------------------------------------- */
	r = snapshot_reader_open(path, err, sizeof(err));
	EXPECT_TRUE(r != NULL, err);
	if (!r)
	{
		remove(path);
		return;
	}

	/* Manifest chunk first. */
	rc = snapshot_reader_next_chunk(r, &id, &version, &payload, &payload_size,
	                                err, sizeof(err));
	EXPECT_EQ_INT(rc, 1, "manifest chunk read after file open");
	EXPECT_EQ_INT(id, ARCSNAP_CHUNK_MNFT, "first chunk is MNFT");
	EXPECT_TRUE(snapshot_decode_manifest(payload, payload_size, &out_manifest,
	                                     err, sizeof(err)),
	            "decode manifest after file round-trip");
	EXPECT_EQ_STR(out_manifest.original_config_name, in_manifest.original_config_name,
	              "config name survives file round-trip");
	EXPECT_EQ_INT(out_manifest.scope_flags, in_manifest.scope_flags,
	              "scope flags survive file round-trip");
	EXPECT_EQ_INT(out_manifest.floppy_count, in_manifest.floppy_count,
	              "floppy_count survives file round-trip");

	after_manifest_cursor = snapshot_reader_cursor(r);

	/* State chunks in order. */
	for (i = 0; i < E2E_CHUNK_COUNT; i++)
	{
		char where[64];
		snprintf(where, sizeof(where), "state chunk[%zu] next_chunk", i);
		rc = snapshot_reader_next_chunk(r, &id, &version, &payload, &payload_size,
		                                err, sizeof(err));
		EXPECT_EQ_INT(rc, 1, where);

		snprintf(where, sizeof(where), "state chunk[%zu] id", i);
		EXPECT_EQ_INT(id, e2e_chunks[i].id, where);

		snprintf(where, sizeof(where), "state chunk[%zu] version", i);
		EXPECT_EQ_INT(version, e2e_chunks[i].version, where);

		snprintf(where, sizeof(where), "state chunk[%zu] payload size", i);
		EXPECT_EQ_INT(payload_size, e2e_chunks[i].payload_size, where);

		snprintf(where, sizeof(where), "state chunk[%zu] payload contents", i);
		EXPECT_EQ_INT(memcmp(payload, e2e_chunks[i].payload, e2e_chunks[i].payload_size),
		              0, where);
	}

	/* EOF after the final state chunk. */
	rc = snapshot_reader_next_chunk(r, &id, &version, &payload, &payload_size,
	                                err, sizeof(err));
	EXPECT_EQ_INT(rc, 0, "EOF after walking every state chunk");

	/* Cursor save / restore: rewind to just after the manifest and
	 * re-walk. Matches how snapshot_apply_machine_state seeks back to
	 * the first state chunk after parsing the manifest up-front. */
	snapshot_reader_set_cursor(r, after_manifest_cursor);
	for (i = 0; i < E2E_CHUNK_COUNT; i++)
	{
		char where[64];
		rc = snapshot_reader_next_chunk(r, &id, &version, &payload, &payload_size,
		                                err, sizeof(err));
		snprintf(where, sizeof(where), "rewind state chunk[%zu] next_chunk", i);
		EXPECT_EQ_INT(rc, 1, where);
		snprintf(where, sizeof(where), "rewind state chunk[%zu] id", i);
		EXPECT_EQ_INT(id, e2e_chunks[i].id, where);
	}

	snapshot_reader_close(r);
	remove(path);
}

/* ----- Phase 3: snapshot_can_save scope guards ------------------------ */

static void test_can_save_clean_floppy_only(void)
{
	char err[256] = {0};

	g_current_test = "can_save_clean_floppy_only";
	scope_reset_fixture();

	EXPECT_EQ_INT(snapshot_can_save(err, sizeof(err)), 1, "clean floppy-only config should be allowed");
	EXPECT_EQ_INT(err[0], 0, "no error message on success");
}

static void test_can_save_allows_arculator_rom(void)
{
	char err[256] = {0};

	g_current_test = "can_save_allows_arculator_rom";
	scope_reset_fixture();
	snprintf(podule_names[2], sizeof(podule_names[2]), "arculator_rom");

	EXPECT_EQ_INT(snapshot_can_save(err, sizeof(err)), 1, "arculator_rom podule should be allowed");
	EXPECT_EQ_INT(err[0], 0, "no error message on success");
}

static void test_can_save_allows_unpaused(void)
{
	char err[256] = {0};

	g_current_test = "can_save_allows_unpaused";
	scope_reset_fixture();
	g_test_paused = 0;

	EXPECT_EQ_INT(snapshot_can_save(err, sizeof(err)), 1, "running session should be allowed (live save)");
	EXPECT_EQ_INT(err[0], 0, "no error message on success");
}

static void test_can_save_allows_st506_without_drive_image(void)
{
	char err[256] = {0};

	g_current_test = "can_save_allows_st506_without_drive_image";
	scope_reset_fixture();
	st506_present = 1;

	EXPECT_EQ_INT(snapshot_can_save(err, sizeof(err)), 1, "empty ST506 controller should be allowed");
	EXPECT_EQ_INT(err[0], 0, "no error message on success");
}

static void test_can_save_allows_ide_hd_when_idle(void)
{
	char err[256] = {0};

	g_current_test = "can_save_allows_ide_hd_when_idle";
	scope_reset_fixture();
	fdctype = FDC_82C711;
	snprintf(hd_fn[0], sizeof(hd_fn[0]), "/tmp/foo.hdf");
	g_test_ide_idle = 1;

	EXPECT_EQ_INT(snapshot_can_save(err, sizeof(err)), 1, "IDE HD should be allowed when idle");
	EXPECT_EQ_INT(err[0], 0, "no error message on success");
}

static void test_can_save_rejects_busy_ide_hd(void)
{
	char err[256] = {0};

	g_current_test = "can_save_rejects_busy_ide_hd";
	scope_reset_fixture();
	fdctype = FDC_82C711;
	snprintf(hd_fn[0], sizeof(hd_fn[0]), "/tmp/foo.hdf");
	g_test_ide_idle = 0;

	EXPECT_EQ_INT(snapshot_can_save(err, sizeof(err)), 0, "IDE HD should be rejected when busy");
	EXPECT_TRUE(strstr(err, "IDE") != NULL, "error should mention IDE");
	EXPECT_TRUE(strstr(err, "busy") != NULL, "error should mention busy");
}

static void test_can_save_rejects_st506_hd(void)
{
	char err[256] = {0};

	g_current_test = "can_save_rejects_st506_hd";
	scope_reset_fixture();
	st506_present = 1;
	snprintf(hd_fn[0], sizeof(hd_fn[0]), "/tmp/foo.hdf");

	EXPECT_EQ_INT(snapshot_can_save(err, sizeof(err)), 0, "ST506 HD should still be rejected");
	EXPECT_TRUE(strstr(err, "ST506") != NULL, "error should mention ST506");
}

static void test_can_save_allows_joystick_none_literal(void)
{
	char err[256] = {0};

	g_current_test = "can_save_allows_joystick_none_literal";
	scope_reset_fixture();
	snprintf(joystick_if, sizeof(joystick_if), "none");

	EXPECT_EQ_INT(snapshot_can_save(err, sizeof(err)), 1, "'none' joystick interface should be allowed");
	EXPECT_EQ_INT(err[0], 0, "no error message on success");
}

static void test_can_save_rejects_unknown_podule(void)
{
	char err[256] = {0};

	g_current_test = "can_save_rejects_unknown_podule";
	scope_reset_fixture();
	snprintf(podule_names[1], sizeof(podule_names[1]), "ether3");

	EXPECT_EQ_INT(snapshot_can_save(err, sizeof(err)), 0, "unknown podule should be rejected");
	EXPECT_TRUE(strstr(err, "ether3") != NULL, "error should mention podule name");
	EXPECT_TRUE(strstr(err, "slot 1") != NULL, "error should mention slot index");
}

static void test_can_save_rejects_5th_column(void)
{
	char err[256] = {0};

	g_current_test = "can_save_rejects_5th_column";
	scope_reset_fixture();
	snprintf(_5th_column_fn, sizeof(_5th_column_fn), "/tmp/support.rom");

	EXPECT_EQ_INT(snapshot_can_save(err, sizeof(err)), 0, "5th-column ROM should be rejected");
	EXPECT_TRUE(strstr(err, "5th-column") != NULL, "error should mention 5th-column");
}

static void test_can_save_rejects_joystick(void)
{
	char err[256] = {0};

	g_current_test = "can_save_rejects_joystick";
	scope_reset_fixture();
	snprintf(joystick_if, sizeof(joystick_if), "fcc");

	EXPECT_EQ_INT(snapshot_can_save(err, sizeof(err)), 0, "joystick interface should be rejected");
	EXPECT_TRUE(strstr(err, "joystick") != NULL, "error should mention joystick");
}

static void test_can_save_rejects_busy_floppy(void)
{
	char err[256] = {0};

	g_current_test = "can_save_rejects_busy_floppy";
	scope_reset_fixture();
	g_test_floppy_idle = 0;

	EXPECT_EQ_INT(snapshot_can_save(err, sizeof(err)), 0, "busy floppy should be rejected");
	EXPECT_TRUE(strstr(err, "floppy") != NULL && strstr(err, "busy") != NULL,
	            "error should mention floppy busy");
}

/* ----- Phase 3: snapshot_open scope check ----------------------------- */

static int write_manifest_snapshot(const char *path, uint32_t scope_flags)
{
	snapshot_writer_t *w;
	arcsnap_manifest_t m;
	int ok;

	fill_test_manifest(&m);
	m.scope_flags = scope_flags;

	w = make_writer_with_header();
	if (!w)
		return 0;
	if (!snapshot_writer_write_manifest(w, &m))
	{
		snapshot_writer_destroy(w);
		return 0;
	}
	ok = snapshot_writer_save_to_file(w, path);
	snapshot_writer_destroy(w);
	return ok;
}

static void run_open_scope_case(const char *name, const char *path,
                                 uint32_t scope_flags, int expect_ok,
                                 const char *expect_err_substr)
{
	snapshot_load_ctx_t *ctx;
	char err[256] = {0};

	g_current_test = name;

	EXPECT_TRUE(write_manifest_snapshot(path, scope_flags), "build manifest");

	ctx = snapshot_open(path, err, sizeof(err));
	if (expect_ok)
	{
		EXPECT_TRUE(ctx != NULL, err);
		EXPECT_EQ_STR(snapshot_original_config_name(ctx), "Test Machine",
		              "manifest config name visible after open");
		snapshot_close(ctx);
	}
	else
	{
		EXPECT_TRUE(ctx == NULL, "snapshot_open should reject scope");
		EXPECT_TRUE(strstr(err, expect_err_substr) != NULL,
		            "error should mention rejected subsystem");
	}

	remove(path);
}

static void test_open_accepts_clean_manifest(void)
{
	run_open_scope_case("open_accepts_clean_manifest",
	                    "snapshot_format_tests_open_clean.arcsnap",
	                    ARCSNAP_SCOPE_HAS_PREV, 1, NULL);
}

static void test_open_accepts_hd_scope(void)
{
	run_open_scope_case("open_accepts_hd_scope",
	                    "snapshot_format_tests_open_hd.arcsnap",
	                    ARCSNAP_SCOPE_HAS_HD, 1, NULL);
}

static void test_open_rejects_podule_scope(void)
{
	run_open_scope_case("open_rejects_podule_scope",
	                    "snapshot_format_tests_open_podule.arcsnap",
	                    ARCSNAP_SCOPE_HAS_PODULE, 0, "podule");
}

/* ----- MNFT v2 (HD) round-trip --------------------------------------- */

static void fill_test_manifest_v2(arcsnap_manifest_t *m)
{
	fill_test_manifest(m);
	m->version = ARCSNAP_MNFT_VERSION_HD;
	m->scope_flags |= ARCSNAP_SCOPE_HAS_HD;
	m->hd_count = 2;

	m->hds[0].drive_index = 0;
	snprintf(m->hds[0].original_path, sizeof(m->hds[0].original_path),
	         "/Users/test/system.hdf");
	m->hds[0].file_size = 52428800;
	m->hds[0].spt = 63;
	m->hds[0].hpc = 16;
	m->hds[0].cyl = 100;

	m->hds[1].drive_index = 1;
	snprintf(m->hds[1].original_path, sizeof(m->hds[1].original_path),
	         "/Users/test/data.hdf");
	m->hds[1].file_size = 104857600;
	m->hds[1].spt = 63;
	m->hds[1].hpc = 16;
	m->hds[1].cyl = 200;
}

static void test_manifest_v2_hd_round_trip(void)
{
	snapshot_writer_t *w;
	snapshot_reader_t *r;
	arcsnap_manifest_t in, out;
	uint32_t id, version;
	const uint8_t *payload;
	uint64_t payload_size;
	int rc;
	char err[256] = {0};

	g_current_test = "manifest_v2_hd_round_trip";

	fill_test_manifest_v2(&in);

	w = make_writer_with_header();
	EXPECT_TRUE(snapshot_writer_write_manifest(w, &in), "write v2 manifest");

	r = snapshot_reader_open_mem(snapshot_writer_data(w), snapshot_writer_size(w),
	                             err, sizeof(err));
	EXPECT_TRUE(r != NULL, err);

	rc = snapshot_reader_next_chunk(r, &id, &version, &payload, &payload_size,
	                                err, sizeof(err));
	EXPECT_EQ_INT(rc, 1, "manifest chunk read");
	EXPECT_EQ_INT(id, ARCSNAP_CHUNK_MNFT, "chunk id is MNFT");
	EXPECT_EQ_INT(version, ARCSNAP_MNFT_VERSION_HD, "chunk version is MNFT v2");

	memset(&out, 0xcc, sizeof(out));
	EXPECT_TRUE(snapshot_decode_manifest(payload, payload_size, &out, err, sizeof(err)),
	            "decode v2 manifest");

	EXPECT_EQ_INT(out.version, ARCSNAP_MNFT_VERSION_HD, "version is v2");
	EXPECT_EQ_INT(out.floppy_count, in.floppy_count, "floppy_count preserved");
	EXPECT_EQ_INT(out.hd_count, 2, "hd_count is 2");
	EXPECT_TRUE(out.scope_flags & ARCSNAP_SCOPE_HAS_HD, "HD scope flag set");

	{
		int i;
		for (i = 0; i < in.hd_count; i++)
		{
			char where[64];
			snprintf(where, sizeof(where), "hd[%d].drive_index", i);
			EXPECT_EQ_INT(out.hds[i].drive_index, in.hds[i].drive_index, where);

			snprintf(where, sizeof(where), "hd[%d].original_path", i);
			EXPECT_EQ_STR(out.hds[i].original_path, in.hds[i].original_path, where);

			snprintf(where, sizeof(where), "hd[%d].file_size", i);
			EXPECT_EQ_INT((int)out.hds[i].file_size, (int)in.hds[i].file_size, where);

			snprintf(where, sizeof(where), "hd[%d].spt", i);
			EXPECT_EQ_INT(out.hds[i].spt, in.hds[i].spt, where);

			snprintf(where, sizeof(where), "hd[%d].hpc", i);
			EXPECT_EQ_INT(out.hds[i].hpc, in.hds[i].hpc, where);

			snprintf(where, sizeof(where), "hd[%d].cyl", i);
			EXPECT_EQ_INT(out.hds[i].cyl, in.hds[i].cyl, where);
		}
	}

	snapshot_reader_close(r);
	snapshot_writer_destroy(w);
}

static void test_manifest_v1_still_works_after_v2(void)
{
	snapshot_writer_t *w;
	snapshot_reader_t *r;
	arcsnap_manifest_t in, out;
	uint32_t id, version;
	const uint8_t *payload;
	uint64_t payload_size;
	int rc;
	char err[256] = {0};

	g_current_test = "manifest_v1_still_works_after_v2";

	fill_test_manifest(&in);

	w = make_writer_with_header();
	EXPECT_TRUE(snapshot_writer_write_manifest(w, &in), "write v1 manifest");

	r = snapshot_reader_open_mem(snapshot_writer_data(w), snapshot_writer_size(w),
	                             err, sizeof(err));
	EXPECT_TRUE(r != NULL, err);

	rc = snapshot_reader_next_chunk(r, &id, &version, &payload, &payload_size,
	                                err, sizeof(err));
	EXPECT_EQ_INT(rc, 1, "manifest chunk read");
	EXPECT_EQ_INT(version, ARCSNAP_MNFT_VERSION, "chunk version is v1");

	memset(&out, 0, sizeof(out));
	EXPECT_TRUE(snapshot_decode_manifest(payload, payload_size, &out, err, sizeof(err)),
	            "decode v1 manifest still works");

	EXPECT_EQ_INT(out.version, ARCSNAP_MNFT_VERSION, "version is v1");
	EXPECT_EQ_INT(out.hd_count, 0, "hd_count is 0 for v1");
	EXPECT_EQ_INT(out.floppy_count, in.floppy_count, "floppy_count preserved");

	snapshot_reader_close(r);
	snapshot_writer_destroy(w);
}

static void test_manifest_rejects_v3(void)
{
	snapshot_writer_t *w;
	snapshot_reader_t *r;
	arcsnap_manifest_t in, out;
	uint32_t id, version;
	const uint8_t *payload;
	uint64_t payload_size;
	int rc;
	char err[256] = {0};

	g_current_test = "manifest_rejects_v3";

	fill_test_manifest(&in);
	in.version = 3;

	w = make_writer_with_header();
	EXPECT_TRUE(snapshot_writer_write_manifest(w, &in), "write v3 manifest");

	r = snapshot_reader_open_mem(snapshot_writer_data(w), snapshot_writer_size(w),
	                             err, sizeof(err));
	EXPECT_TRUE(r != NULL, err);

	rc = snapshot_reader_next_chunk(r, &id, &version, &payload, &payload_size,
	                                err, sizeof(err));
	EXPECT_EQ_INT(rc, 1, "manifest chunk read");

	memset(&out, 0, sizeof(out));
	EXPECT_EQ_INT(snapshot_decode_manifest(payload, payload_size, &out, err, sizeof(err)),
	              0, "v3 manifest should be rejected");
	EXPECT_TRUE(strstr(err, "unsupported manifest version") != NULL,
	            "error should mention unsupported version");

	snapshot_reader_close(r);
	snapshot_writer_destroy(w);
}

/* ----- META writer round-trip ----------------------------------------- */

static void fill_test_meta(arcsnap_meta_t *m)
{
	memset(m, 0, sizeof(*m));
	m->version = ARCSNAP_META_VERSION;
	snprintf(m->name, sizeof(m->name), "Snapshot 42");
	snprintf(m->description, sizeof(m->description),
	         "A test snapshot with a multi-line\ndescription.");
	m->created_at_unix_ms_utc = 1700000000000ull;
	m->property_count = 3;
	snprintf(m->properties[0].key,   sizeof(m->properties[0].key),   "host_os_name");
	snprintf(m->properties[0].value, sizeof(m->properties[0].value), "macOS");
	snprintf(m->properties[1].key,   sizeof(m->properties[1].key),   "host_os_version");
	snprintf(m->properties[1].value, sizeof(m->properties[1].value), "15.4");
	snprintf(m->properties[2].key,   sizeof(m->properties[2].key),   "emulator_version_string");
	snprintf(m->properties[2].value, sizeof(m->properties[2].value), "2.2-dev");
}

static void test_meta_round_trip(void)
{
	snapshot_writer_t *w;
	snapshot_reader_t *r;
	arcsnap_meta_t in_meta, out_meta;
	uint32_t id, version;
	const uint8_t *payload;
	uint64_t payload_size;
	int rc;
	char err[256] = {0};
	uint32_t i;

	g_current_test = "meta_round_trip";

	fill_test_meta(&in_meta);
	w = make_writer_with_header();
	EXPECT_TRUE(snapshot_writer_write_meta(w, &in_meta), "write meta");

	r = snapshot_reader_open_mem(snapshot_writer_data(w),
	                             snapshot_writer_size(w),
	                             err, sizeof(err));
	EXPECT_TRUE(r != NULL, err);

	rc = snapshot_reader_next_chunk(r, &id, &version, &payload, &payload_size,
	                                err, sizeof(err));
	EXPECT_EQ_INT(rc, 1, "next_chunk returns META chunk");
	EXPECT_EQ_INT(id, ARCSNAP_CHUNK_META, "first chunk is META");
	EXPECT_EQ_INT(version, ARCSNAP_META_VERSION, "META chunk version");

	EXPECT_TRUE(snapshot_decode_meta(payload, payload_size, &out_meta, err, sizeof(err)),
	            "decode meta");
	EXPECT_EQ_INT(out_meta.version, in_meta.version, "meta version");
	EXPECT_EQ_STR(out_meta.name, in_meta.name, "meta name");
	EXPECT_EQ_STR(out_meta.description, in_meta.description, "meta description");
	EXPECT_TRUE(out_meta.created_at_unix_ms_utc == in_meta.created_at_unix_ms_utc,
	            "meta created_at");
	EXPECT_EQ_INT(out_meta.property_count, in_meta.property_count, "meta property_count");
	for (i = 0; i < in_meta.property_count; i++)
	{
		char where[64];
		snprintf(where, sizeof(where), "meta.properties[%u].key", (unsigned)i);
		EXPECT_EQ_STR(out_meta.properties[i].key, in_meta.properties[i].key, where);
		snprintf(where, sizeof(where), "meta.properties[%u].value", (unsigned)i);
		EXPECT_EQ_STR(out_meta.properties[i].value, in_meta.properties[i].value, where);
	}

	snapshot_reader_close(r);
	snapshot_writer_destroy(w);
}

static void test_meta_rejects_unknown_version(void)
{
	/* Construct a META payload with version=2 and decode it. */
	uint8_t payload[32];
	arcsnap_meta_t out;
	char err[256] = {0};
	size_t p = 0;

	g_current_test = "meta_rejects_unknown_version";

	/* version */
	payload[p++] = 0x02; payload[p++] = 0x00; payload[p++] = 0x00; payload[p++] = 0x00;
	/* name length = 0 */
	payload[p++] = 0x00; payload[p++] = 0x00; payload[p++] = 0x00; payload[p++] = 0x00;
	/* description length = 0 */
	payload[p++] = 0x00; payload[p++] = 0x00; payload[p++] = 0x00; payload[p++] = 0x00;
	/* created_at = 0 */
	memset(payload + p, 0, 8); p += 8;
	/* property_count = 0 */
	payload[p++] = 0x00; payload[p++] = 0x00; payload[p++] = 0x00; payload[p++] = 0x00;

	EXPECT_TRUE(!snapshot_decode_meta(payload, p, &out, err, sizeof(err)),
	            "decode should reject unknown META version");
	EXPECT_TRUE(strstr(err, "version") != NULL, "error should mention version");
}

static void test_meta_rejects_trailing_bytes(void)
{
	snapshot_writer_t *w;
	arcsnap_meta_t in_meta, out_meta;
	size_t payload_size;
	uint8_t *payload_copy;
	char err[256] = {0};

	g_current_test = "meta_rejects_trailing_bytes";

	/* Write a valid META chunk, then extract just the payload bytes
	 * (skip the 24-byte header) and append one trailing byte. */
	fill_test_meta(&in_meta);
	w = make_writer_with_header();
	EXPECT_TRUE(snapshot_writer_write_meta(w, &in_meta), "write meta");

	/* The writer buffer contains: [file header 24B][chunk header 24B][META payload][...]
	 * The chunk header encodes payload size at offset +8. */
	{
		const uint8_t *buf = snapshot_writer_data(w);
		const uint8_t *chunk_hdr = buf + ARCSNAP_HEADER_DISK_SIZE;
		size_t orig_size = (size_t)(
		     (uint64_t)chunk_hdr[ 8]        |
		    ((uint64_t)chunk_hdr[ 9] <<  8) |
		    ((uint64_t)chunk_hdr[10] << 16) |
		    ((uint64_t)chunk_hdr[11] << 24) |
		    ((uint64_t)chunk_hdr[12] << 32) |
		    ((uint64_t)chunk_hdr[13] << 40) |
		    ((uint64_t)chunk_hdr[14] << 48) |
		    ((uint64_t)chunk_hdr[15] << 56));
		payload_size = orig_size + 1;
		payload_copy = (uint8_t *)malloc(payload_size);
		EXPECT_TRUE(payload_copy != NULL, "malloc");
		memcpy(payload_copy, chunk_hdr + ARCSNAP_CHUNK_HEADER_DISK_SIZE, orig_size);
		payload_copy[orig_size] = 0xff;
	}

	EXPECT_TRUE(!snapshot_decode_meta(payload_copy, payload_size, &out_meta, err, sizeof(err)),
	            "decode should reject trailing bytes");
	EXPECT_TRUE(strstr(err, "trailing") != NULL, "error should mention trailing bytes");

	free(payload_copy);
	snapshot_writer_destroy(w);
}

/* ----- main ----------------------------------------------------------- */

int main(void)
{
	test_header_round_trip();
	test_header_bad_magic();
	test_header_bad_version();
	test_header_bad_crc();
	test_chunk_round_trip();
	test_chunk_corruption_detected();
	test_truncated_header();
	test_truncated_chunk_header();
	test_truncated_chunk_payload();
	test_manifest_round_trip();
	test_file_save_round_trip();
	test_end_to_end_roundtrip();

	test_can_save_clean_floppy_only();
	test_can_save_allows_arculator_rom();
	test_can_save_allows_unpaused();
	test_can_save_allows_st506_without_drive_image();
	test_can_save_allows_ide_hd_when_idle();
	test_can_save_rejects_busy_ide_hd();
	test_can_save_rejects_st506_hd();
	test_can_save_rejects_unknown_podule();
	test_can_save_rejects_5th_column();
	test_can_save_allows_joystick_none_literal();
	test_can_save_rejects_joystick();
	test_can_save_rejects_busy_floppy();

	test_open_accepts_clean_manifest();
	test_open_accepts_hd_scope();
	test_open_rejects_podule_scope();

	test_manifest_v2_hd_round_trip();
	test_manifest_v1_still_works_after_v2();
	test_manifest_rejects_v3();

	test_meta_round_trip();
	test_meta_rejects_unknown_version();
	test_meta_rejects_trailing_bytes();

	if (g_failures)
	{
		fprintf(stderr, "snapshot_format_tests: %d failure(s)\n", g_failures);
		return 1;
	}
	printf("snapshot_format_tests: OK\n");
	return 0;
}

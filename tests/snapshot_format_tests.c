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

	if (g_failures)
	{
		fprintf(stderr, "snapshot_format_tests: %d failure(s)\n", g_failures);
		return 1;
	}
	printf("snapshot_format_tests: OK\n");
	return 0;
}

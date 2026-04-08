/*
 * snapshot_peek_summary() tests.
 *
 * Exercises the read-only summary accessor used by the snapshot
 * browser. Builds fixture .arcsnap files in memory (via the public
 * writer API) and then peeks them back through the public
 * snapshot_peek_summary() entry point.
 *
 * Links only src/snapshot.c. No emulation core, no platform code.
 */

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "snapshot.h"
#include "snapshot_chunks.h"

/* ----- tiny test runner ---------------------------------------------- */

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

/* snapshot.c's scope guard pulls in arc_is_paused / floppy_is_idle /
 * config globals via extern declarations. snapshot_peek_summary() does
 * not invoke snapshot_can_save(), but the linker still needs symbols. */
int  st506_present       = 0;
char hd_fn[2][512]       = {{0}, {0}};
char podule_names[4][16] = {{0}, {0}, {0}, {0}};
char joystick_if[16]     = {0};
char _5th_column_fn[512] = {0};

int arc_is_paused(void) { return 1; }
int floppy_is_idle(void) { return 1; }

/* ----- helpers -------------------------------------------------------- */

static char g_tmp_dir[512];

static void tmp_setup(void)
{
	snprintf(g_tmp_dir, sizeof(g_tmp_dir), "/tmp/arcsnap_summary_tests.XXXXXX");
	if (!mkdtemp(g_tmp_dir))
	{
		fprintf(stderr, "mkdtemp failed\n");
		exit(2);
	}
}

static void tmp_teardown(void)
{
	char cmd[640];
	snprintf(cmd, sizeof(cmd), "rm -rf '%s'", g_tmp_dir);
	if (system(cmd) != 0)
		fprintf(stderr, "warning: cleanup of '%s' failed\n", g_tmp_dir);
}

static void make_tmp_path(char *out, size_t out_size, const char *name)
{
	snprintf(out, out_size, "%s/%s", g_tmp_dir, name);
}

static void fill_test_manifest(arcsnap_manifest_t *m, uint32_t scope_flags)
{
	memset(m, 0, sizeof(*m));
	m->version = ARCSNAP_MNFT_VERSION;
	snprintf(m->original_config_name, sizeof(m->original_config_name), "Test Machine");
	snprintf(m->machine, sizeof(m->machine), "a3000");
	m->fdctype       = 0;
	m->romset        = 5;
	m->memsize       = 4096;
	m->machine_type  = 0;
	m->scope_flags   = scope_flags;
	m->preview_width  = 640;
	m->preview_height = 512;
	m->floppy_count  = 0;
}

static void fill_test_meta(arcsnap_meta_t *m)
{
	memset(m, 0, sizeof(*m));
	m->version = ARCSNAP_META_VERSION;
	snprintf(m->name, sizeof(m->name), "Quick save");
	snprintf(m->description, sizeof(m->description), "Before the tricky bit");
	m->created_at_unix_ms_utc = 1710000000000ull;
	m->property_count = 2;
	snprintf(m->properties[0].key,   sizeof(m->properties[0].key),   "host_os_name");
	snprintf(m->properties[0].value, sizeof(m->properties[0].value), "macOS");
	snprintf(m->properties[1].key,   sizeof(m->properties[1].key),   "emulator_version_string");
	snprintf(m->properties[1].value, sizeof(m->properties[1].value), "2.2-dev");
}

/* Append raw bytes as an `id` chunk. Used for unknown/state chunks. */
static int write_raw_chunk(snapshot_writer_t *w, uint32_t id,
                           const void *data, size_t size)
{
	if (!snapshot_writer_begin_chunk(w, id, 1u))
		return 0;
	if (size && !snapshot_writer_append(w, data, size))
		return 0;
	return snapshot_writer_end_chunk(w);
}

/* Builds a snapshot fixture with MNFT, optional PREV, optional META,
 * optional sentinel end chunks, in that order. `preview_bytes` may be
 * NULL. `meta` may be NULL. If `include_end` is set, writes an END
 * chunk so the peek loop sees a terminator. */
static int write_fixture(const char *path,
                         const arcsnap_manifest_t *manifest,
                         const uint8_t *preview_bytes, size_t preview_size,
                         int second_preview,
                         const arcsnap_meta_t *meta,
                         int second_meta,
                         int include_cpu_state,
                         int include_end)
{
	snapshot_writer_t *w = snapshot_writer_create();
	if (!w) return 0;
	if (!snapshot_writer_write_header(w)) goto fail;
	if (!snapshot_writer_write_manifest(w, manifest)) goto fail;
	if (preview_bytes && preview_size)
	{
		if (!write_raw_chunk(w, ARCSNAP_CHUNK_PREV, preview_bytes, preview_size)) goto fail;
		if (second_preview)
			if (!write_raw_chunk(w, ARCSNAP_CHUNK_PREV, preview_bytes, preview_size)) goto fail;
	}
	if (meta)
	{
		if (!snapshot_writer_write_meta(w, meta)) goto fail;
		if (second_meta)
			if (!snapshot_writer_write_meta(w, meta)) goto fail;
	}
	if (include_cpu_state)
	{
		uint8_t state[16];
		memset(state, 0xab, sizeof(state));
		if (!write_raw_chunk(w, ARCSNAP_CHUNK_CPU, state, sizeof(state))) goto fail;
	}
	if (include_end)
	{
		if (!write_raw_chunk(w, ARCSNAP_CHUNK_END, NULL, 0)) goto fail;
	}
	if (!snapshot_writer_save_to_file(w, path)) goto fail;
	snapshot_writer_destroy(w);
	return 1;

fail:
	snapshot_writer_destroy(w);
	return 0;
}

/* ----- tests ---------------------------------------------------------- */

static void test_peek_mnft_only(void)
{
	char path[600];
	arcsnap_manifest_t m;
	arcsnap_summary_t summary;
	char err[256] = {0};

	g_current_test = "peek_mnft_only";
	make_tmp_path(path, sizeof(path), "mnft_only.arcsnap");
	fill_test_manifest(&m, 0);

	EXPECT_TRUE(write_fixture(path, &m, NULL, 0, 0, NULL, 0, 0, 1),
	            "build mnft-only fixture");

	memset(&summary, 0, sizeof(summary));
	EXPECT_TRUE(snapshot_peek_summary(path, &summary, err, sizeof(err)), err);
	EXPECT_EQ_INT(summary.has_meta, 0, "no meta");
	EXPECT_EQ_INT(summary.has_preview, 0, "no preview");
	EXPECT_EQ_STR(summary.manifest.original_config_name, "Test Machine", "manifest name");
	EXPECT_EQ_STR(summary.manifest.machine, "a3000", "manifest machine");

	snapshot_summary_dispose(&summary);
	remove(path);
}

static void test_peek_mnft_prev(void)
{
	char path[600];
	arcsnap_manifest_t m;
	arcsnap_summary_t summary;
	uint8_t fake_png[32];
	char err[256] = {0};
	size_t i;

	g_current_test = "peek_mnft_prev";
	make_tmp_path(path, sizeof(path), "mnft_prev.arcsnap");
	fill_test_manifest(&m, ARCSNAP_SCOPE_HAS_PREV);

	for (i = 0; i < sizeof(fake_png); i++)
		fake_png[i] = (uint8_t)(i * 3 + 1);

	EXPECT_TRUE(write_fixture(path, &m, fake_png, sizeof(fake_png), 0, NULL, 0, 0, 1),
	            "build mnft+prev fixture");

	memset(&summary, 0, sizeof(summary));
	EXPECT_TRUE(snapshot_peek_summary(path, &summary, err, sizeof(err)), err);
	EXPECT_EQ_INT(summary.has_preview, 1, "has_preview");
	EXPECT_EQ_INT((int)summary.preview_png_size, (int)sizeof(fake_png), "preview size");
	EXPECT_EQ_INT(summary.preview_width, 640, "preview width");
	EXPECT_EQ_INT(summary.preview_height, 512, "preview height");
	EXPECT_TRUE(summary.preview_png != NULL, "preview bytes allocated");
	EXPECT_TRUE(memcmp(summary.preview_png, fake_png, sizeof(fake_png)) == 0,
	            "preview bytes round-trip");
	EXPECT_EQ_INT(summary.has_meta, 0, "no meta");

	snapshot_summary_dispose(&summary);
	remove(path);
}

static void test_peek_mnft_meta(void)
{
	char path[600];
	arcsnap_manifest_t m;
	arcsnap_meta_t    meta;
	arcsnap_summary_t summary;
	char err[256] = {0};

	g_current_test = "peek_mnft_meta";
	make_tmp_path(path, sizeof(path), "mnft_meta.arcsnap");
	fill_test_manifest(&m, 0);
	fill_test_meta(&meta);

	EXPECT_TRUE(write_fixture(path, &m, NULL, 0, 0, &meta, 0, 0, 1),
	            "build mnft+meta fixture");

	memset(&summary, 0, sizeof(summary));
	EXPECT_TRUE(snapshot_peek_summary(path, &summary, err, sizeof(err)), err);
	EXPECT_EQ_INT(summary.has_meta, 1, "has_meta");
	EXPECT_EQ_INT(summary.has_preview, 0, "no preview");
	EXPECT_EQ_STR(summary.meta.name, "Quick save", "meta name");
	EXPECT_EQ_STR(summary.meta.description, "Before the tricky bit", "meta description");
	EXPECT_TRUE(summary.meta.created_at_unix_ms_utc == 1710000000000ull, "meta created_at");
	EXPECT_EQ_INT(summary.meta.property_count, 2, "meta property_count");
	EXPECT_EQ_STR(summary.meta.properties[0].key, "host_os_name", "prop[0].key");
	EXPECT_EQ_STR(summary.meta.properties[0].value, "macOS", "prop[0].value");
	EXPECT_EQ_STR(summary.meta.properties[1].key, "emulator_version_string", "prop[1].key");
	EXPECT_EQ_STR(summary.meta.properties[1].value, "2.2-dev", "prop[1].value");

	snapshot_summary_dispose(&summary);
	remove(path);
}

static void test_peek_mnft_meta_prev(void)
{
	char path[600];
	arcsnap_manifest_t m;
	arcsnap_meta_t    meta;
	arcsnap_summary_t summary;
	uint8_t fake_png[48];
	char err[256] = {0};
	size_t i;

	g_current_test = "peek_mnft_meta_prev";
	make_tmp_path(path, sizeof(path), "mnft_meta_prev.arcsnap");
	fill_test_manifest(&m, ARCSNAP_SCOPE_HAS_PREV);
	fill_test_meta(&meta);
	for (i = 0; i < sizeof(fake_png); i++)
		fake_png[i] = (uint8_t)(i + 9);

	EXPECT_TRUE(write_fixture(path, &m, fake_png, sizeof(fake_png), 0, &meta, 0, 0, 1),
	            "build mnft+meta+prev fixture");

	memset(&summary, 0, sizeof(summary));
	EXPECT_TRUE(snapshot_peek_summary(path, &summary, err, sizeof(err)), err);
	EXPECT_EQ_INT(summary.has_meta, 1, "has_meta");
	EXPECT_EQ_INT(summary.has_preview, 1, "has_preview");
	EXPECT_EQ_STR(summary.meta.name, "Quick save", "meta name");
	EXPECT_EQ_INT((int)summary.preview_png_size, (int)sizeof(fake_png), "preview size");

	snapshot_summary_dispose(&summary);
	remove(path);
}

static void test_peek_stops_at_state_chunk(void)
{
	char path[600];
	arcsnap_manifest_t m;
	arcsnap_meta_t    meta;
	arcsnap_summary_t summary;
	char err[256] = {0};

	g_current_test = "peek_stops_at_state_chunk";
	make_tmp_path(path, sizeof(path), "mnft_meta_cpu.arcsnap");
	fill_test_manifest(&m, 0);
	fill_test_meta(&meta);

	/* MNFT + META + CPU state + END. Peek should stop at CPU. */
	EXPECT_TRUE(write_fixture(path, &m, NULL, 0, 0, &meta, 0, 1, 1),
	            "build mnft+meta+state fixture");

	memset(&summary, 0, sizeof(summary));
	EXPECT_TRUE(snapshot_peek_summary(path, &summary, err, sizeof(err)), err);
	EXPECT_EQ_INT(summary.has_meta, 1, "has_meta");

	snapshot_summary_dispose(&summary);
	remove(path);
}

static void test_peek_rejects_duplicate_meta(void)
{
	char path[600];
	arcsnap_manifest_t m;
	arcsnap_meta_t    meta;
	arcsnap_summary_t summary;
	char err[256] = {0};

	g_current_test = "peek_rejects_duplicate_meta";
	make_tmp_path(path, sizeof(path), "dup_meta.arcsnap");
	fill_test_manifest(&m, 0);
	fill_test_meta(&meta);

	/* MNFT + META + META. */
	EXPECT_TRUE(write_fixture(path, &m, NULL, 0, 0, &meta, 1, 0, 1),
	            "build duplicate-meta fixture");

	memset(&summary, 0, sizeof(summary));
	EXPECT_TRUE(!snapshot_peek_summary(path, &summary, err, sizeof(err)),
	            "peek should reject duplicate META");
	EXPECT_TRUE(strstr(err, "duplicate") != NULL, "error mentions duplicate");

	snapshot_summary_dispose(&summary);
	remove(path);
}

static void test_peek_rejects_duplicate_prev(void)
{
	char path[600];
	arcsnap_manifest_t m;
	arcsnap_summary_t summary;
	uint8_t fake_png[16];
	char err[256] = {0};

	g_current_test = "peek_rejects_duplicate_prev";
	make_tmp_path(path, sizeof(path), "dup_prev.arcsnap");
	fill_test_manifest(&m, ARCSNAP_SCOPE_HAS_PREV);
	memset(fake_png, 0xcd, sizeof(fake_png));

	/* MNFT + PREV + PREV. */
	EXPECT_TRUE(write_fixture(path, &m, fake_png, sizeof(fake_png), 1, NULL, 0, 0, 1),
	            "build duplicate-prev fixture");

	memset(&summary, 0, sizeof(summary));
	EXPECT_TRUE(!snapshot_peek_summary(path, &summary, err, sizeof(err)),
	            "peek should reject duplicate PREV");
	EXPECT_TRUE(strstr(err, "duplicate") != NULL, "error mentions duplicate");

	snapshot_summary_dispose(&summary);
	remove(path);
}

static void test_peek_rejects_missing_file(void)
{
	arcsnap_summary_t summary;
	char err[256] = {0};

	g_current_test = "peek_rejects_missing_file";
	memset(&summary, 0, sizeof(summary));
	EXPECT_TRUE(!snapshot_peek_summary("/nonexistent/path/nope.arcsnap",
	                                   &summary, err, sizeof(err)),
	            "peek should fail on missing file");
	EXPECT_TRUE(err[0] != 0, "error populated");

	snapshot_summary_dispose(&summary);
}

static void test_summary_dispose_is_idempotent(void)
{
	arcsnap_summary_t summary;

	g_current_test = "summary_dispose_is_idempotent";
	memset(&summary, 0, sizeof(summary));

	/* Dispose on zeroed struct. */
	snapshot_summary_dispose(&summary);

	/* Dispose on NULL. */
	snapshot_summary_dispose(NULL);

	/* Dispose twice. */
	summary.preview_png = (uint8_t *)malloc(16);
	summary.preview_png_size = 16;
	summary.has_preview = 1;
	snapshot_summary_dispose(&summary);
	EXPECT_TRUE(summary.preview_png == NULL, "preview_png cleared");
	EXPECT_EQ_INT(summary.has_preview, 0, "has_preview cleared");
	snapshot_summary_dispose(&summary);
}

/* ----- main ----------------------------------------------------------- */

int main(void)
{
	tmp_setup();

	test_peek_mnft_only();
	test_peek_mnft_prev();
	test_peek_mnft_meta();
	test_peek_mnft_meta_prev();
	test_peek_stops_at_state_chunk();
	test_peek_rejects_duplicate_meta();
	test_peek_rejects_duplicate_prev();
	test_peek_rejects_missing_file();
	test_summary_dispose_is_idempotent();

	tmp_teardown();

	if (g_failures)
	{
		fprintf(stderr, "snapshot_summary_tests: %d failure(s)\n", g_failures);
		return 1;
	}
	printf("snapshot_summary_tests: OK\n");
	return 0;
}

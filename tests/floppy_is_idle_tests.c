/*
 * Truth-table tests for floppy_is_idle() (src/disc.c).
 *
 * snapshot_can_save() calls floppy_is_idle() as its final guard before
 * allowing a save to proceed. The function returns 1 iff the floppy
 * controller is accepting commands: it rejects outright if the FDC is
 * overridden (e.g. by a podule swap), if no fdc_funcs vtable is
 * installed, or if the vtable has no is_idle callback. Otherwise it
 * delegates to the vtable.
 *
 * This test builds a tiny fake fdc_funcs_t, wires it into the globals
 * that disc.c owns, and verifies each row of the truth table.
 *
 * Build: tests/run_snapshot_tests.sh (via a dedicated clang invocation).
 * Links the real src/disc.c + src/timer.c + src/snapshot.c, with
 * shims for the rest of disc.c's transitive dependencies.
 */

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "disc.h"
#include "timer.h"

/* ----- tiny test runner ----------------------------------------------- */

static int g_failures = 0;
static const char *g_current_test = "(none)";

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

/* ----- controllable fake FDC ------------------------------------------ */

static int g_fake_is_idle_result = 1;
static int g_fake_is_idle_calls  = 0;

static int fake_is_idle(void *p)
{
	(void)p;
	g_fake_is_idle_calls++;
	return g_fake_is_idle_result;
}

static void fake_data(uint8_t dat, void *p) { (void)dat; (void)p; }
static void fake_void_p(void *p)             { (void)p; }
static int  fake_getdata(int last, void *p)  { (void)last; (void)p; return 0; }
static void fake_sectorid(uint8_t t, uint8_t s, uint8_t sec, uint8_t sz,
                          uint8_t c1, uint8_t c2, void *p)
{
	(void)t; (void)s; (void)sec; (void)sz; (void)c1; (void)c2; (void)p;
}

static fdc_funcs_t fake_fdc_funcs_full =
{
	.data           = fake_data,
	.spindown       = fake_void_p,
	.finishread     = fake_void_p,
	.notfound       = fake_void_p,
	.datacrcerror   = fake_void_p,
	.headercrcerror = fake_void_p,
	.writeprotect   = fake_void_p,
	.getdata        = fake_getdata,
	.sectorid       = fake_sectorid,
	.indexpulse     = fake_void_p,
	.is_idle        = fake_is_idle,
};

static fdc_funcs_t fake_fdc_funcs_no_is_idle =
{
	.data           = fake_data,
	.spindown       = fake_void_p,
	.finishread     = fake_void_p,
	.notfound       = fake_void_p,
	.datacrcerror   = fake_void_p,
	.headercrcerror = fake_void_p,
	.writeprotect   = fake_void_p,
	.getdata        = fake_getdata,
	.sectorid       = fake_sectorid,
	.indexpulse     = fake_void_p,
	.is_idle        = NULL,
};

/* These are the globals disc.c expects callers to populate. */
extern fdc_funcs_t *fdc_funcs;
extern void        *fdc_p;
extern int          fdc_overridden;

static int dummy_fdc_context;

static void reset_fdc(void)
{
	fdc_funcs            = &fake_fdc_funcs_full;
	fdc_p                = &dummy_fdc_context;
	fdc_overridden       = 0;
	g_fake_is_idle_result = 1;
	g_fake_is_idle_calls  = 0;
}

/* ----- truth table ---------------------------------------------------- *
 *
 * row | fdc_overridden | fdc_funcs | is_idle | is_idle() | expected
 * ----|----------------|-----------|---------|-----------|---------
 *  1  |       0        |   set     |  set    |     1     |    1
 *  2  |       0        |   set     |  set    |     0     |    0
 *  3  |       1        |   set     |  set    |     1     |    0
 *  4  |       0        |   NULL    |   —     |     —     |    0
 *  5  |       0        |   set     |  NULL   |     —     |    0
 */

static void test_row1_idle_fdc_reports_idle(void)
{
	g_current_test = "row1_idle_fdc_reports_idle";
	reset_fdc();
	g_fake_is_idle_result = 1;

	EXPECT_EQ_INT(floppy_is_idle(), 1, "idle delegates to is_idle");
	EXPECT_EQ_INT(g_fake_is_idle_calls, 1, "is_idle should be called exactly once");
}

static void test_row2_busy_fdc_reports_not_idle(void)
{
	g_current_test = "row2_busy_fdc_reports_not_idle";
	reset_fdc();
	g_fake_is_idle_result = 0;

	EXPECT_EQ_INT(floppy_is_idle(), 0, "busy propagates from is_idle");
	EXPECT_EQ_INT(g_fake_is_idle_calls, 1, "is_idle should be called exactly once");
}

static void test_row3_fdc_overridden_blocks(void)
{
	g_current_test = "row3_fdc_overridden_blocks";
	reset_fdc();
	g_fake_is_idle_result = 1;
	fdc_overridden = 1;

	EXPECT_EQ_INT(floppy_is_idle(), 0, "overridden FDC should never be idle");
	EXPECT_EQ_INT(g_fake_is_idle_calls, 0,
	              "is_idle should NOT be consulted when overridden");
}

static void test_row4_null_fdc_funcs_blocks(void)
{
	g_current_test = "row4_null_fdc_funcs_blocks";
	reset_fdc();
	fdc_funcs = NULL;

	EXPECT_EQ_INT(floppy_is_idle(), 0, "no FDC installed -> not idle");
}

static void test_row5_missing_is_idle_blocks(void)
{
	g_current_test = "row5_missing_is_idle_blocks";
	reset_fdc();
	fdc_funcs = &fake_fdc_funcs_no_is_idle;

	EXPECT_EQ_INT(floppy_is_idle(), 0,
	              "FDC with NULL is_idle should be treated as busy");
}

/* ----- main ----------------------------------------------------------- */

int main(void)
{
	test_row1_idle_fdc_reports_idle();
	test_row2_busy_fdc_reports_not_idle();
	test_row3_fdc_overridden_blocks();
	test_row4_null_fdc_funcs_blocks();
	test_row5_missing_is_idle_blocks();

	if (g_failures)
	{
		fprintf(stderr, "floppy_is_idle_tests: %d failure(s)\n", g_failures);
		return 1;
	}
	printf("floppy_is_idle_tests: OK\n");
	return 0;
}

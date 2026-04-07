/*
 * Linker stubs for tests/floppy_is_idle_tests.c.
 *
 * The floppy_is_idle truth-table test compiles src/disc.c, src/timer.c,
 * and src/snapshot.c directly. Those files reference symbols that live
 * in other emulator subsystems (disc format loaders, ddnoise, ioc, the
 * config globals the scope guard inspects, etc.). This file provides
 * zero-value definitions for every such symbol so the test binary
 * links without dragging in the entire emulator.
 *
 * None of these stubs are exercised by the test itself — the test only
 * calls floppy_is_idle() against a controllable fake FDC vtable.
 */

#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* --- arc.h logging --- */
void rpclog(const char *format, ...)
{
	(void)format;
}

void fatal(const char *format, ...)
{
	(void)format;
	/* Should never be reached by this test. If it is, abort so the
	 * failure is obvious. */
	fprintf(stderr, "floppy_is_idle_tests: unexpected fatal()\n");
	exit(1);
}

void error(const char *format, ...)
{
	(void)format;
}

/* --- timer.c externs --- */
int speed_mhz = 1;

/* --- snapshot.c scope-guard externs ---
 *
 * These are inspected by snapshot_can_save() — we never call it from
 * this test, but the linker still needs definitions because snapshot.c
 * references them unconditionally. */
int  st506_present       = 0;
char hd_fn[2][512]       = {{0}, {0}};
char podule_names[4][16] = {{0}, {0}, {0}, {0}};
char joystick_if[16]     = {0};
char _5th_column_fn[512] = {0};

int arc_is_paused(void) { return 1; }

/* --- disc.c dependencies --- */
char *get_extension(char *p)
{
	char *last = NULL;
	while (*p)
	{
		if (*p == '.')
			last = p + 1;
		p++;
	}
	return last;
}

/* Disc image loaders — all no-ops. */
void adf_load(int drive, char *fn)            { (void)drive; (void)fn; }
void adf_loadex(int drive, char *fn, int sectors_per_track, int sector_size,
                int double_density, int single_sided, int sides, int use_ibm)
{
	(void)drive; (void)fn; (void)sectors_per_track; (void)sector_size;
	(void)double_density; (void)single_sided; (void)sides; (void)use_ibm;
}
void adf_arcdd_load(int drive, char *fn)      { (void)drive; (void)fn; }
void adf_archd_load(int drive, char *fn)      { (void)drive; (void)fn; }
void adl_load(int drive, char *fn)            { (void)drive; (void)fn; }
void apd_load(int drive, char *fn)            { (void)drive; (void)fn; }
void dsd_load(int drive, char *fn)            { (void)drive; (void)fn; }
void fdi_load(int drive, char *fn)            { (void)drive; (void)fn; }
void hfe_load(int drive, char *fn)            { (void)drive; (void)fn; }
void scp_load(int drive, char *fn)            { (void)drive; (void)fn; }
void ssd_load(int drive, char *fn)            { (void)drive; (void)fn; }

/* ddnoise + ioc — no-ops. */
void ddnoise_seek(int tracks)                 { (void)tracks; }
void ioc_discchange_clear(int drive)          { (void)drive; }

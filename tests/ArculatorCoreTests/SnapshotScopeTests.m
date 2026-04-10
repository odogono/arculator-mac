#import <XCTest/XCTest.h>
#include <string.h>
#include <unistd.h>

#include "snapshot.h"
#include "snapshot_chunks.h"
#include "config.h"

/* Scope-guard globals. hd_fn / joystick_if / _5th_column_fn come from
 * config.c; st506_present / podule_names from core_test_stubs.c. */
extern int  st506_present;
extern char hd_fn[2][512];
extern char podule_names[4][16];
extern char joystick_if[16];
extern char _5th_column_fn[512];

/* Test-controllable gates from core_test_stubs.c. */
extern int g_test_arc_is_paused;
extern int g_test_floppy_is_idle;
extern int g_test_ide_is_idle;

@interface SnapshotScopeTests : XCTestCase
{
	char _tmpDir[512];
}
@end

@implementation SnapshotScopeTests

- (void)setUp
{
	/* Baseline: clean, floppy-only, paused, idle. */
	g_test_arc_is_paused  = 1;
	g_test_floppy_is_idle = 1;
	g_test_ide_is_idle    = 1;
	st506_present         = 0;
	fdctype               = FDC_WD1770;
	hd_fn[0][0]           = 0;
	hd_fn[1][0]           = 0;
	for (int i = 0; i < 4; i++)
		podule_names[i][0] = 0;
	joystick_if[0]        = 0;
	_5th_column_fn[0]     = 0;

	/* Per-test temp dir so parallel runs don't collide on file paths. */
	snprintf(_tmpDir, sizeof(_tmpDir), "%s/SnapshotScopeTests_XXXXXX",
		NSTemporaryDirectory().fileSystemRepresentation);
	XCTAssertNotEqual(mkdtemp(_tmpDir), NULL, @"mkdtemp failed");
}

- (void)tearDown
{
	if (_tmpDir[0])
		[[NSFileManager defaultManager] removeItemAtPath:@(_tmpDir) error:nil];
}

- (void)testAllowsCleanFloppyOnlyConfig
{
	char err[256] = {0};
	XCTAssertEqual(snapshot_can_save(err, sizeof(err)), 1,
		@"clean floppy-only config should be savable, got err='%s'", err);
	XCTAssertEqual(err[0], 0,
		@"no error message expected on success, got '%s'", err);
}

- (void)testAllowsArculatorRomPodule
{
	/* The arculator_rom support podule is whitelisted in v1 because
	 * it's treated as static/stateless. */
	snprintf(podule_names[2], sizeof(podule_names[2]), "arculator_rom");

	char err[256] = {0};
	XCTAssertEqual(snapshot_can_save(err, sizeof(err)), 1,
		@"arculator_rom podule should be allowed, got err='%s'", err);
}

- (void)testRejectsWhenNotPaused
{
	g_test_arc_is_paused = 0;

	char err[256] = {0};
	XCTAssertEqual(snapshot_can_save(err, sizeof(err)), 0);
	XCTAssertTrue(strstr(err, "paused") != NULL,
		@"expected a 'paused' rejection, got '%s'", err);
}

- (void)testRejectsInternalHardDiscViaST506
{
	st506_present = 1;

	char err[256] = {0};
	XCTAssertEqual(snapshot_can_save(err, sizeof(err)), 1,
		@"empty ST506 controller should still be savable, got err='%s'", err);
}

- (void)testAllowsIDEHardDiscWhenIdle
{
	fdctype = FDC_82C711;
	snprintf(hd_fn[0], sizeof(hd_fn[0]), "/tmp/drive0.hdf");
	g_test_ide_is_idle = 1;

	char err[256] = {0};
	XCTAssertEqual(snapshot_can_save(err, sizeof(err)), 1,
		@"IDE HD should be allowed when idle, got err='%s'", err);
}

- (void)testRejectsBusyIDEHardDisc
{
	fdctype = FDC_82C711;
	snprintf(hd_fn[0], sizeof(hd_fn[0]), "/tmp/drive0.hdf");
	g_test_ide_is_idle = 0;

	char err[256] = {0};
	XCTAssertEqual(snapshot_can_save(err, sizeof(err)), 0);
	XCTAssertTrue(strstr(err, "IDE") != NULL,
		@"expected an 'IDE' rejection, got '%s'", err);
	XCTAssertTrue(strstr(err, "busy") != NULL,
		@"expected a 'busy' rejection, got '%s'", err);
}

- (void)testRejectsST506HardDisc
{
	st506_present = 1;
	snprintf(hd_fn[0], sizeof(hd_fn[0]), "/tmp/drive0.hdf");

	char err[256] = {0};
	XCTAssertEqual(snapshot_can_save(err, sizeof(err)), 0);
	XCTAssertTrue(strstr(err, "ST506") != NULL,
		@"expected an 'ST506' rejection, got '%s'", err);
}

- (void)testRejectsUnknownPodule
{
	snprintf(podule_names[1], sizeof(podule_names[1]), "ether3");

	char err[256] = {0};
	XCTAssertEqual(snapshot_can_save(err, sizeof(err)), 0);
	XCTAssertTrue(strstr(err, "ether3") != NULL,
		@"expected the podule name in the error, got '%s'", err);
	XCTAssertTrue(strstr(err, "slot 1") != NULL,
		@"expected the slot number in the error, got '%s'", err);
}

- (void)testRejects5thColumnROM
{
	snprintf(_5th_column_fn, sizeof(_5th_column_fn), "/tmp/support.rom");

	char err[256] = {0};
	XCTAssertEqual(snapshot_can_save(err, sizeof(err)), 0);
	XCTAssertTrue(strstr(err, "5th-column") != NULL,
		@"expected a '5th-column' rejection, got '%s'", err);
}

- (void)testRejectsJoystickInterface
{
	snprintf(joystick_if, sizeof(joystick_if), "fcc");

	char err[256] = {0};
	XCTAssertEqual(snapshot_can_save(err, sizeof(err)), 0);
	XCTAssertTrue(strstr(err, "joystick") != NULL,
		@"expected a 'joystick' rejection, got '%s'", err);
}

- (void)testAllowsJoystickInterfaceNoneLiteral
{
	snprintf(joystick_if, sizeof(joystick_if), "none");

	char err[256] = {0};
	XCTAssertEqual(snapshot_can_save(err, sizeof(err)), 1,
		@"'none' joystick interface should be allowed, got err='%s'", err);
}

- (void)testRejectsBusyFloppy
{
	g_test_floppy_is_idle = 0;

	char err[256] = {0};
	XCTAssertEqual(snapshot_can_save(err, sizeof(err)), 0);
	XCTAssertTrue(strstr(err, "floppy") != NULL && strstr(err, "busy") != NULL,
		@"expected a 'floppy busy' rejection, got '%s'", err);
}

- (void)testOpenAcceptsCleanManifest
{
	char path[512];
	snprintf(path, sizeof(path), "%s/clean.arcsnap", _tmpDir);
	if (![self writeManifestSnapshotAtPath:path scopeFlags:ARCSNAP_SCOPE_HAS_PREV])
		return;

	char err[256] = {0};
	snapshot_load_ctx_t *ctx = snapshot_open(path, err, sizeof(err));
	XCTAssertTrue(ctx != NULL, @"clean manifest should open, got err='%s'", err);
	if (ctx)
	{
		const char *name = snapshot_original_config_name(ctx);
		XCTAssertTrue(name != NULL, @"original name should be set");
		if (name)
			XCTAssertEqual(strcmp(name, "Test Machine"), 0,
				@"expected 'Test Machine', got '%s'", name);
		snapshot_close(ctx);
	}
}

- (void)testOpenAcceptsHardDiscScope
{
	char path[512];
	snprintf(path, sizeof(path), "%s/hd.arcsnap", _tmpDir);
	if (![self writeManifestSnapshotAtPath:path scopeFlags:ARCSNAP_SCOPE_HAS_HD])
		return;

	char err[256] = {0};
	snapshot_load_ctx_t *ctx = snapshot_open(path, err, sizeof(err));
	XCTAssertTrue(ctx != NULL, @"hard-disc scope flag should be accepted, got err='%s'", err);
	if (ctx)
		snapshot_close(ctx);
}

- (void)testOpenRejectsPoduleScope
{
	char path[512];
	snprintf(path, sizeof(path), "%s/podule.arcsnap", _tmpDir);
	if (![self writeManifestSnapshotAtPath:path scopeFlags:ARCSNAP_SCOPE_HAS_PODULE])
		return;

	char err[256] = {0};
	snapshot_load_ctx_t *ctx = snapshot_open(path, err, sizeof(err));
	XCTAssertTrue(ctx == NULL, @"podule scope flag should be rejected by loader");
	XCTAssertTrue(strstr(err, "podule") != NULL,
		@"expected a 'podule' rejection, got '%s'", err);
}

/* ----- helpers --------------------------------------------------------- */

- (BOOL)writeManifestSnapshotAtPath:(const char *)path
                         scopeFlags:(uint32_t)scopeFlags
{
	arcsnap_manifest_t m;
	memset(&m, 0, sizeof(m));
	m.version = ARCSNAP_MNFT_VERSION;
	snprintf(m.original_config_name, sizeof(m.original_config_name), "Test Machine");
	snprintf(m.machine, sizeof(m.machine), "a3000");
	m.romset       = 5;
	m.memsize      = 4096;
	m.scope_flags  = scopeFlags;
	m.floppy_count = 0;

	snapshot_writer_t *w = snapshot_writer_create();
	XCTAssertTrue(w != NULL, @"writer create");
	if (!w)
		return NO;

	BOOL ok = snapshot_writer_write_header(w)
	       && snapshot_writer_write_manifest(w, &m)
	       && snapshot_writer_save_to_file(w, path);
	snapshot_writer_destroy(w);

	XCTAssertTrue(ok, @"failed to build snapshot at %s", path);
	return ok;
}

@end

#import <XCTest/XCTest.h>
#include "cmos.h"
#include "config.h"
#include "platform_paths.h"
#include <string.h>
#include <sys/stat.h>

extern int romset;
extern int fdctype;

@interface CMOSLoadTests : XCTestCase
{
	char _supportDir[512];
	char _resourceDir[512];
}
@end

@implementation CMOSLoadTests

- (void)setUp
{
	snprintf(_supportDir, sizeof(_supportDir), "%s/arculator_cmos_sup_XXXXXX",
		NSTemporaryDirectory().fileSystemRepresentation);
	XCTAssertNotEqual(mkdtemp(_supportDir), NULL);

	snprintf(_resourceDir, sizeof(_resourceDir), "%s/arculator_cmos_res_XXXXXX",
		NSTemporaryDirectory().fileSystemRepresentation);
	XCTAssertNotEqual(mkdtemp(_resourceDir), NULL);

	/* Create cmos subdirectories in both roots. */
	char path[512];
	snprintf(path, sizeof(path), "%s/cmos", _supportDir);
	mkdir(path, 0777);
	snprintf(path, sizeof(path), "%s/cmos", _resourceDir);
	mkdir(path, 0777);

	platform_paths_init_test(_supportDir, _resourceDir);

	/* Default state: riscos311, FDC_82C711, "Test Machine" */
	romset = 6;  /* ROM_RISCOS_311 */
	fdctype = 1; /* FDC_82C711 */
	strncpy(machine_config_name, "Test Machine", sizeof(machine_config_name) - 1);
}

- (void)tearDown
{
	platform_paths_reset();
	[[NSFileManager defaultManager] removeItemAtPath:@(_supportDir) error:nil];
	[[NSFileManager defaultManager] removeItemAtPath:@(_resourceDir) error:nil];
}

- (void)testCMOSGetRamPtrReturnsNonNull
{
	const uint8_t *ptr = cmos_get_ram_ptr();
	XCTAssertTrue(ptr != NULL, @"cmos_get_ram_ptr() must not return NULL");
}

- (void)testCMOSLoadsPerMachineFile
{
	/* Copy the CMOS fixture into the support cmos directory with the expected name.
	   For riscos311 + FDC_82C711, config_get_cmos_name returns "riscos3_new",
	   so the file is "cmos/Test Machine.riscos3_new.cmos.bin". */

	NSBundle *bundle = [NSBundle bundleForClass:[self class]];
	NSString *fixturePath = [bundle pathForResource:@"Test Machine.riscos3_new.cmos"
		ofType:@"bin" inDirectory:@"fixtures/cmos"];

	NSData *data = [NSData dataWithContentsOfFile:fixturePath];
	XCTAssertNotNil(data, @"Could not read CMOS fixture at %@", fixturePath);
	XCTAssertEqual(data.length, 256u, @"CMOS fixture must be 256 bytes");

	char destPath[512];
	snprintf(destPath, sizeof(destPath),
		"%s/cmos/Test Machine.riscos3_new.cmos.bin", _supportDir);
	[data writeToFile:@(destPath) atomically:YES];

	cmos_load();

	const uint8_t *ram = cmos_get_ram_ptr();
	/* Byte 0 in fixture is 0xAA. */
	XCTAssertEqual(ram[0], 0xAA, @"Expected byte 0 = 0xAA, got 0x%02X", ram[0]);
	/* Bytes 1-6 are overwritten by host clock — skip them. */
	/* Byte 7 in fixture is 0x42. */
	XCTAssertEqual(ram[7], 0x42, @"Expected byte 7 = 0x42, got 0x%02X", ram[7]);
	XCTAssertEqual(ram[8], 0x01, @"Expected byte 8 = 0x01, got 0x%02X", ram[8]);
	XCTAssertEqual(ram[11], 0xFF, @"Expected byte 11 = 0xFF, got 0x%02X", ram[11]);
	XCTAssertEqual(ram[15], 0x40, @"Expected byte 15 = 0x40, got 0x%02X", ram[15]);
}

- (void)testCMOSFallsBackToZeroWhenNoFiles
{
	/* Neither support nor resource directories contain a CMOS file. */
	cmos_load();

	const uint8_t *ram = cmos_get_ram_ptr();
	/* Bytes 1-6 are set from host clock, so skip them.
	   Byte 0 and bytes 7+ should all be zero. */
	XCTAssertEqual(ram[0], 0, @"Expected byte 0 = 0 when no CMOS file, got 0x%02X", ram[0]);
	for (int i = 7; i < 256; i++) {
		XCTAssertEqual(ram[i], 0,
			@"Expected byte %d = 0 when no CMOS file, got 0x%02X", i, ram[i]);
	}
}

/*
 * cmos_save() used to crash with EXC_BAD_ACCESS when fopen() returned
 * NULL (e.g. non-writable directory).  Verify the NULL guard works.
 */
- (void)testCMOSSaveDoesNotCrashWhenDirectoryMissing
{
	/* Point paths at a non-existent directory so fopen fails. */
	platform_paths_reset();
	platform_paths_init_test("/nonexistent_dir_XXXXXX", "/nonexistent_dir_XXXXXX");

	/* This must not crash — previously it dereferenced a NULL FILE*. */
	cmos_save();
}

@end

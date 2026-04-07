#import <XCTest/XCTest.h>
#include "config.h"
#include "platform_paths.h"
#include <string.h>
#include <sys/stat.h>

/* Globals set by loadconfig() — defined in stubs or config.c */
extern int romset;
extern int fdctype;
extern int memsize;
extern int arm_cpu_type;
extern int memc_type;
extern int fpaena;
extern int dblscan;
extern int video_scale;
extern int soundena;

@interface ConfigLoadTests : XCTestCase
{
	char _tmpDir[512];
}
@end

@implementation ConfigLoadTests

- (void)setUp
{
	snprintf(_tmpDir, sizeof(_tmpDir), "%s/arculator_config_test_XXXXXX",
		NSTemporaryDirectory().fileSystemRepresentation);
	XCTAssertNotEqual(mkdtemp(_tmpDir), NULL, @"mkdtemp failed");

	/* Create configs subdirectory and copy fixture. */
	char configsDir[512];
	snprintf(configsDir, sizeof(configsDir), "%s/configs", _tmpDir);
	mkdir(configsDir, 0777);

	/* Find the fixture in the test bundle resources. */
	NSBundle *bundle = [NSBundle bundleForClass:[self class]];
	NSString *fixturePath = [bundle pathForResource:@"Test Machine" ofType:@"cfg"
		inDirectory:@"fixtures/configs"];

	char destPath[512];
	snprintf(destPath, sizeof(destPath), "%s/configs/Test Machine.cfg", _tmpDir);

	NSData *data = [NSData dataWithContentsOfFile:fixturePath];
	XCTAssertNotNil(data, @"Could not read fixture at %@", fixturePath);
	[data writeToFile:@(destPath) atomically:YES];

	/* Also create an empty arc.cfg so config_load(CFG_GLOBAL, ...) doesn't fail. */
	char globalCfg[512];
	snprintf(globalCfg, sizeof(globalCfg), "%s/arc.cfg", _tmpDir);
	[@"" writeToFile:@(globalCfg) atomically:YES encoding:NSUTF8StringEncoding error:nil];

	platform_paths_init_test(_tmpDir, _tmpDir);

	strncpy(machine_config_name, "Test Machine", sizeof(machine_config_name) - 1);
	snprintf(machine_config_file, sizeof(machine_config_file),
		"%s/configs/Test Machine.cfg", _tmpDir);
}

- (void)tearDown
{
	platform_paths_reset();
	[[NSFileManager defaultManager] removeItemAtPath:@(_tmpDir) error:nil];
}

- (void)testConfigLoadsRomSet
{
	loadconfig();
	/* Test Machine.cfg: rom_set = riscos311 → ROM_RISCOS_311 (enum value 6) */
	XCTAssertEqual(romset, 6, @"Expected ROM_RISCOS_311 (6), got %d", romset);
}

- (void)testConfigLoadsMonitorType
{
	loadconfig();
	/* Test Machine.cfg: monitor_type = standard → MONITOR_STANDARD (0) */
	XCTAssertEqual(monitor_type, 0, @"Expected MONITOR_STANDARD (0), got %d", monitor_type);
}

- (void)testConfigLoadsMemSize
{
	loadconfig();
	XCTAssertEqual(memsize, 2048, @"Expected 2048, got %d", memsize);
}

- (void)testConfigLoadsMachineType
{
	loadconfig();
	/* a3010 → MACHINE_TYPE_NORMAL (0) */
	XCTAssertEqual(machine_type, 0, @"Expected MACHINE_TYPE_NORMAL (0), got %d", machine_type);
}

- (void)testConfigLoadsFDCType
{
	loadconfig();
	/* fdc_type = 1 → FDC_82C711 */
	XCTAssertEqual(fdctype, 1, @"Expected FDC_82C711 (1), got %d", fdctype);
}

- (void)testConfigLoadsCPUType
{
	loadconfig();
	XCTAssertEqual(arm_cpu_type, 0, @"Expected cpu_type 0, got %d", arm_cpu_type);
}

- (void)testConfigLoadsDoubleScan
{
	loadconfig();
	XCTAssertEqual(dblscan, 1, @"Expected double_scan 1, got %d", dblscan);
}

@end

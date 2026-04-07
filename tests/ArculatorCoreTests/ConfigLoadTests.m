#import <XCTest/XCTest.h>
#include "config.h"
#include "platform_paths.h"
#include <string.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

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

- (NSString *)writeTempDiskImageNamed:(NSString *)name size:(off_t)size fillByte:(uint8_t)fillByte
{
	char path[512];
	snprintf(path, sizeof(path), "%s/%s", _tmpDir, name.fileSystemRepresentation);

	int fd = open(path, O_CREAT | O_TRUNC | O_RDWR, 0666);
	XCTAssertTrue(fd >= 0, @"open() failed for %s", path);
	if (fd < 0)
		return @"";

	XCTAssertEqual(ftruncate(fd, size), 0, @"ftruncate() failed for %s", path);
	if (fillByte != 0)
	{
		uint8_t byte = fillByte;
		XCTAssertEqual(write(fd, &byte, 1), 1, @"write() failed for %s", path);
	}

	close(fd);
	return @(path);
}

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

- (void)testInternalDiskImageStateDetectsBlankRawImage
{
	NSString *path = [self writeTempDiskImageNamed:@"blank.hdf" size:512 fillByte:0];
	int state = config_internal_disk_image_state(path.fileSystemRepresentation, 1, 1, 1, 0);
	XCTAssertEqual(state, INTERNAL_DISK_IMAGE_BLANK_RAW);
}

- (void)testInternalDiskImageStateDetectsInitializedImage
{
	NSString *path = [self writeTempDiskImageNamed:@"initialized.hdf" size:512 fillByte:0x5A];
	int state = config_internal_disk_image_state(path.fileSystemRepresentation, 1, 1, 1, 0);
	XCTAssertEqual(state, INTERNAL_DISK_IMAGE_INITIALIZED);
}

- (void)testInternalDiskImageStateDetectsUnknownImage
{
	NSString *path = [self writeTempDiskImageNamed:@"unknown.hdf" size:777 fillByte:0x5A];
	int state = config_internal_disk_image_state(path.fileSystemRepresentation, 1, 1, 1, 0);
	XCTAssertEqual(state, INTERNAL_DISK_IMAGE_UNKNOWN);
}

- (void)testBundledIDEReadyTemplateUses101CylinderLegacyHeaderLayout
{
	NSBundle *bundle = [NSBundle bundleForClass:[self class]];
	NSString *templatePath = [bundle pathForResource:@"ide_101x16x63.hdf" ofType:@"zlib"
		inDirectory:@"templates"];
	XCTAssertNotNil(templatePath, @"Missing bundled IDE ready template fixture");
	if (!templatePath)
		return;

	NSString *readyPath = [NSString stringWithFormat:@"%s/ready-ide.hdf", _tmpDir];
	NSError *readError = nil;
	NSData *compressedData = [NSData dataWithContentsOfFile:templatePath
							options:0
							  error:&readError];
	XCTAssertNotNil(compressedData, @"Could not read compressed template: %@", readError);
	if (!compressedData)
		return;

	NSError *decompressError = nil;
	NSData *templateData = [compressedData decompressedDataUsingAlgorithm:NSDataCompressionAlgorithmZlib
								 error:&decompressError];
	XCTAssertNotNil(templateData, @"Could not decompress template: %@", decompressError);
	if (!templateData)
		return;

	NSError *writeError = nil;
	BOOL wroteTemplate = [templateData writeToFile:readyPath options:0 error:&writeError];
	XCTAssertTrue(wroteTemplate, @"Could not write decompressed template: %@", writeError);
	if (!wroteTemplate)
		return;

	struct stat st;
	XCTAssertEqual(stat(readyPath.fileSystemRepresentation, &st), 0);
	XCTAssertEqual(st.st_size, (off_t)101 * 16 * 63 * 512);

	FILE *file = fopen(readyPath.fileSystemRepresentation, "rb");
	XCTAssertNotEqual(file, NULL);
	if (!file)
		return;

	uint8_t discRecordPrefix[4] = {0};
	XCTAssertEqual(fseek(file, 0xFC0, SEEK_SET), 0);
	XCTAssertEqual(fread(discRecordPrefix, 1, sizeof(discRecordPrefix), file), sizeof(discRecordPrefix));
	fclose(file);

	XCTAssertEqual(discRecordPrefix[0], 0x09);
	XCTAssertEqual(discRecordPrefix[1], 0x3f);
	XCTAssertEqual(discRecordPrefix[2], 0x10);
	XCTAssertEqual(discRecordPrefix[3], 0x00);

	int state = config_internal_disk_image_state(readyPath.fileSystemRepresentation, 101, 16, 63, 0);
	XCTAssertEqual(state, INTERNAL_DISK_IMAGE_INITIALIZED);
}

@end

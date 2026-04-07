#import <XCTest/XCTest.h>
#include "platform_paths.h"
#include <string.h>

@interface PlatformPathTests : XCTestCase
@end

@implementation PlatformPathTests

- (void)tearDown
{
	platform_paths_reset();
}

- (void)testInitTestSetsSupportPath
{
	platform_paths_init_test("/tmp/test_support", "/tmp/test_resources");

	char buf[512];
	platform_path_join_support(buf, "foo", sizeof(buf));
	XCTAssertTrue(strncmp(buf, "/tmp/test_support/foo", 512) == 0,
		@"Expected support path rooted at /tmp/test_support, got %s", buf);
}

- (void)testInitTestSetsResourcePath
{
	platform_paths_init_test("/tmp/test_support", "/tmp/test_resources");

	char buf[512];
	platform_path_join_resource(buf, "bar", sizeof(buf));
	XCTAssertTrue(strncmp(buf, "/tmp/test_resources/bar", 512) == 0,
		@"Expected resource path rooted at /tmp/test_resources, got %s", buf);
}

- (void)testResetAllowsReinit
{
	platform_paths_init_test("/tmp/first_support", "/tmp/first_resources");
	platform_paths_reset();
	platform_paths_init_test("/tmp/second_support", "/tmp/second_resources");

	char buf[512];
	platform_path_join_support(buf, "x", sizeof(buf));
	XCTAssertTrue(strncmp(buf, "/tmp/second_support/x", 512) == 0,
		@"After reset and reinit, expected second support root, got %s", buf);
}

- (void)testGlobalConfigPath
{
	platform_paths_init_test("/tmp/support", "/tmp/resources");

	char buf[512];
	platform_path_global_config(buf, sizeof(buf));
	XCTAssertTrue(strcmp(buf, "/tmp/support/arc.cfg") == 0,
		@"Expected /tmp/support/arc.cfg, got %s", buf);
}

- (void)testMachineConfigPath
{
	platform_paths_init_test("/tmp/support", "/tmp/resources");

	char buf[512];
	platform_path_machine_config(buf, sizeof(buf), "My Machine");
	XCTAssertTrue(strcmp(buf, "/tmp/support/configs/My Machine.cfg") == 0,
		@"Expected /tmp/support/configs/My Machine.cfg, got %s", buf);
}

- (void)testConfigsDirPath
{
	platform_paths_init_test("/tmp/support", "/tmp/resources");

	char buf[512];
	platform_path_configs_dir(buf, sizeof(buf));
	XCTAssertTrue(strcmp(buf, "/tmp/support/configs") == 0,
		@"Expected /tmp/support/configs, got %s", buf);
}

- (void)testDrivesDirPath
{
	platform_paths_init_test("/tmp/support", "/tmp/resources");

	char buf[512];
	platform_path_drives_dir(buf, sizeof(buf));
	XCTAssertTrue(strcmp(buf, "/tmp/support/drives") == 0,
		@"Expected /tmp/support/drives, got %s", buf);
}

@end

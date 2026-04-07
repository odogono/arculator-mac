//
//  ConfigBridge.mm
//  Arculator
//
//  Config state management and list operations bridge.
//

#import "ConfigBridge.h"
#import "dialog_util.h"

extern "C" {
#include "arc.h"
#include "arm.h"
#include "config.h"
#include "fpa.h"
#include "joystick.h"
#include "memc.h"
#include "platform_paths.h"
#include "platform_shell.h"
#include "podules.h"
#include "st506.h"
}

#include "MachinePresetData.h"

static NSMutableSet<NSString *> *gShownBlankDiskWarnings;

#pragma mark - Setting key constants

NSString *const ARCSettingDisc            = @"disc";
NSString *const ARCSettingDisplayMode     = @"display_mode";
NSString *const ARCSettingDoubleScanning  = @"dblscan";
NSString *const ARCSettingSoundGain       = @"sound_gain";
NSString *const ARCSettingStereo          = @"stereo";
NSString *const ARCSettingDiscNoise       = @"disc_noise";
NSString *const ARCSettingCPU             = @"cpu";
NSString *const ARCSettingMEMC            = @"memc";
NSString *const ARCSettingMemory          = @"memory";
NSString *const ARCSettingFPU             = @"fpu";
NSString *const ARCSettingROM             = @"rom";
NSString *const ARCSettingMonitor         = @"monitor";
NSString *const ARCSettingJoystickInterface = @"joystick_if";
NSString *const ARCSettingSupportROM      = @"support_rom";
NSString *const ARCSettingMachinePreset   = @"machine_preset";
NSString *const ARCSettingIOType          = @"io_type";
NSString *const ARCSettingPodules         = @"podules";
NSString *const ARCSettingHDPaths         = @"hd_paths";
NSString *const ARCSettingUniqueID        = @"unique_id";
NSString *const ARCSetting5thColumnROM    = @"5th_column_rom";

#pragma mark - ARCMachineConfig

@implementation ARCMachineConfig

+ (instancetype)configFromGlobals
{
	ARCMachineConfig *cfg = [[ARCMachineConfig alloc] init];

	cfg.preset  = preset_from_config_name(machine);
	cfg.cpu     = arm_cpu_type;
	cfg.memc    = memc_type;
	cfg.rom     = romset;
	cfg.monitor = monitor_type;
	cfg.uniqueId = unique_id;

	// Reverse-map FPU
	if (!fpaena)
		cfg.fpu = FPU_NONE;
	else
		cfg.fpu = fpu_type ? FPU_FPPC : FPU_FPA10;

	// Reverse-map IO type
	if (fdctype >= FDC_82C711 && fdctype != FDC_WD1793_A500)
		cfg.io = IO_NEW;
	else if (st506_present)
		cfg.io = IO_OLD_ST506;
	else
		cfg.io = IO_OLD;

	// Reverse-map memory size
	switch (memsize)
	{
		case 512:   cfg.mem = MEM_512K; break;
		case 1024:  cfg.mem = MEM_1M; break;
		case 2048:  cfg.mem = MEM_2M; break;
		case 4096:  cfg.mem = MEM_4M; break;
		case 8192:  cfg.mem = MEM_8M; break;
		case 12288: cfg.mem = MEM_12M; break;
		default:    cfg.mem = MEM_16M; break;
	}

	// Podules
	cfg.podule0 = arc_nsstring(podule_names[0]);
	cfg.podule1 = arc_nsstring(podule_names[1]);
	cfg.podule2 = arc_nsstring(podule_names[2]);
	cfg.podule3 = arc_nsstring(podule_names[3]);

	// Joystick
	cfg.joystickInterface = arc_nsstring(joystick_if);

	// Hard drives
	cfg.hdPath0 = arc_nsstring(hd_fn[0]);
	cfg.hdPath1 = arc_nsstring(hd_fn[1]);
	cfg.hdCyl0 = hd_cyl[0]; cfg.hdHpc0 = hd_hpc[0]; cfg.hdSpt0 = hd_spt[0];
	cfg.hdCyl1 = hd_cyl[1]; cfg.hdHpc1 = hd_hpc[1]; cfg.hdSpt1 = hd_spt[1];

	// 5th Column ROM and support ROM
	cfg.fifthColumnPath = arc_nsstring(_5th_column_fn);
	cfg.supportRomEnabled = support_rom_enabled != 0;

	return cfg;
}

+ (instancetype)configFromPresetIndex:(int)presetIndex
{
	if (presetIndex < 0 || presetIndex >= preset_count())
		presetIndex = 0;

	ARCMachineConfig *cfg = [[ARCMachineConfig alloc] init];

	cfg.preset  = presetIndex;
	cfg.cpu     = presets[presetIndex].default_cpu;
	cfg.mem     = presets[presetIndex].default_mem;
	cfg.memc    = presets[presetIndex].default_memc;
	cfg.io      = presets[presetIndex].io;
	cfg.fpu     = FPU_NONE;
	cfg.monitor = MONITOR_MULTISYNC;
	cfg.rom     = (presetIndex != preset_from_config_name("a500")) ? ROM_RISCOS_311 : ROM_RISCOS_310_A500;

	// Generate random unique ID for New IO machines
	if (cfg.io == IO_NEW)
	{
		cfg.uniqueId = arc4random();
	}
	else
	{
		cfg.uniqueId = 0;
	}

	// Default podule: arculator_rom in slot 0
	cfg.podule0 = @"arculator_rom";
	cfg.podule1 = @"";
	cfg.podule2 = @"";
	cfg.podule3 = @"";

	cfg.joystickInterface = @"none";
	cfg.hdPath0 = @"";
	cfg.hdPath1 = @"";
	cfg.hdCyl0 = 0; cfg.hdHpc0 = 0; cfg.hdSpt0 = 0;
	cfg.hdCyl1 = 0; cfg.hdHpc1 = 0; cfg.hdSpt1 = 0;
	cfg.fifthColumnPath = @"";
	cfg.supportRomEnabled = YES;

	return cfg;
}

- (void)applyToGlobals
{
	// MEMC
	switch (self.memc)
	{
		case MEMC_MEMC1:    memc_is_memc1 = 1; arm_mem_speed = 8; break;
		case MEMC_MEMC1A_8: memc_is_memc1 = 0; arm_mem_speed = 8; break;
		case MEMC_MEMC1A_12: memc_is_memc1 = 0; arm_mem_speed = 12; break;
		default:            memc_is_memc1 = 0; arm_mem_speed = 16; break;
	}
	memc_type = self.memc;

	// CPU
	switch (self.cpu)
	{
		case CPU_ARM2:    arm_has_swp = arm_has_cp15 = 0; arm_cpu_speed = arm_mem_speed; break;
		case CPU_ARM250:  arm_has_swp = 1; arm_has_cp15 = 0; arm_cpu_speed = arm_mem_speed; break;
		case CPU_ARM3_20: arm_has_swp = arm_has_cp15 = 1; arm_cpu_speed = 20; break;
		case CPU_ARM3_24: arm_has_swp = arm_has_cp15 = 1; arm_cpu_speed = 24; break;
		case CPU_ARM3_25: arm_has_swp = arm_has_cp15 = 1; arm_cpu_speed = 25; break;
		case CPU_ARM3_26: arm_has_swp = arm_has_cp15 = 1; arm_cpu_speed = 26; break;
		case CPU_ARM3_30: arm_has_swp = arm_has_cp15 = 1; arm_cpu_speed = 30; break;
		case CPU_ARM3_33: arm_has_swp = arm_has_cp15 = 1; arm_cpu_speed = 33; break;
		case CPU_ARM3_35: arm_has_swp = arm_has_cp15 = 1; arm_cpu_speed = 35; break;
		case CPU_ARM3_36: arm_has_swp = arm_has_cp15 = 1; arm_cpu_speed = 36; break;
		default:          arm_has_swp = arm_has_cp15 = 1; arm_cpu_speed = 40; break;
	}
	arm_cpu_type = self.cpu;

	// FPU
	fpaena = (self.fpu == FPU_NONE) ? 0 : 1;
	fpu_type = (self.cpu >= CPU_ARM3_20) ? 0 : 1;

	// FDC and ST506 (derived from ROM + IO type)
	romset = self.rom;
	if (romset == ROM_ARTHUR_120_A500 || romset == ROM_RISCOS_200_A500 || romset == ROM_RISCOS_310_A500)
		fdctype = FDC_WD1793_A500;
	else
		fdctype = (self.io >= IO_NEW) ? 1 : 0;
	st506_present = (fdctype == FDC_WD1770 || fdctype == FDC_WD1793_A500) ? 1 : 0;

	// Memory
	switch (self.mem)
	{
		case MEM_512K: memsize = 512; break;
		case MEM_1M:   memsize = 1024; break;
		case MEM_2M:   memsize = 2048; break;
		case MEM_4M:   memsize = 4096; break;
		case MEM_8M:   memsize = 8192; break;
		case MEM_12M:  memsize = 12288; break;
		default:       memsize = 16384; break;
	}

	// Monitor
	monitor_type = self.monitor;

	// Hard drives
	arc_copy_string(hd_fn[0], sizeof(hd_fn[0]), self.hdPath0);
	arc_copy_string(hd_fn[1], sizeof(hd_fn[1]), self.hdPath1);
	hd_cyl[0] = self.hdCyl0; hd_hpc[0] = self.hdHpc0; hd_spt[0] = self.hdSpt0;
	hd_cyl[1] = self.hdCyl1; hd_hpc[1] = self.hdHpc1; hd_spt[1] = self.hdSpt1;

	// Podules
	arc_copy_string(podule_names[0], sizeof(podule_names[0]), self.podule0);
	arc_copy_string(podule_names[1], sizeof(podule_names[1]), self.podule1);
	arc_copy_string(podule_names[2], sizeof(podule_names[2]), self.podule2);
	arc_copy_string(podule_names[3], sizeof(podule_names[3]), self.podule3);

	// Unique ID
	unique_id = self.uniqueId;

	// Joystick interface
	arc_copy_string(joystick_if, sizeof(joystick_if),
		(self.joystickInterface.length > 0) ? self.joystickInterface : @"none");

	// Machine preset name
	strncpy(machine, presets[self.preset].config_name, sizeof(machine) - 1);
	machine[sizeof(machine) - 1] = 0;

	// 5th Column ROM
	arc_copy_string(_5th_column_fn, sizeof(_5th_column_fn), self.fifthColumnPath);

	// Support ROM
	support_rom_enabled = self.supportRomEnabled ? 1 : 0;

	saveconfig();
}

- (void)applyToGlobalsAndResetIfRunning
{
	[self applyToGlobals];
	if (arc_is_session_active())
		arc_do_reset();
}

@end

#pragma mark - ConfigBridge

@implementation ConfigBridge

+ (NSArray<NSString *> *)listConfigNames
{
	char config_dir[512];
	platform_path_configs_dir(config_dir, sizeof(config_dir));

	NSMutableArray<NSString *> *names = [NSMutableArray array];
	NSArray<NSString *> *files = [[NSFileManager defaultManager]
		contentsOfDirectoryAtPath:arc_nsstring(config_dir) error:nil];

	for (NSString *file in files)
	{
		if ([[file pathExtension] isEqualToString:@"cfg"])
			[names addObject:[file stringByDeletingPathExtension]];
	}

	[names sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
	return names;
}

+ (NSString *)configPathForName:(NSString *)name
{
	char path[512];
	platform_path_machine_config(path, sizeof(path), name.UTF8String);
	return arc_nsstring(path);
}

+ (BOOL)configExists:(NSString *)name
{
	return [[NSFileManager defaultManager] fileExistsAtPath:[self configPathForName:name]];
}

+ (BOOL)loadConfigNamed:(NSString *)name
{
	NSString *path = [self configPathForName:name];
	if (![[NSFileManager defaultManager] fileExistsAtPath:path])
		return NO;

	arc_copy_string(machine_config_file, sizeof(machine_config_file), path);
	arc_copy_string(machine_config_name, sizeof(machine_config_name), name);
	loadconfig();
	return YES;
}

+ (ARCInternalDiskImageState)stateForInternalDiskImageAtPath:(NSString *)path
						  cylinders:(int)cylinders
						       heads:(int)heads
						     sectors:(int)sectors
						     isST506:(BOOL)isST506
{
	switch (config_internal_disk_image_state(path.fileSystemRepresentation,
						 cylinders,
						 heads,
						 sectors,
						 isST506 ? 1 : 0))
	{
		case INTERNAL_DISK_IMAGE_BLANK_RAW:
			return ARCInternalDiskImageStateBlankRaw;
		case INTERNAL_DISK_IMAGE_INITIALIZED:
			return ARCInternalDiskImageStateInitialized;
		default:
			return ARCInternalDiskImageStateUnknown;
	}
}

+ (void)showStartupWarningsForLoadedConfigIfNeeded
{
	if (!gShownBlankDiskWarnings)
		gShownBlankDiskWarnings = [[NSMutableSet alloc] init];

	struct drive_info_t
	{
		const char *path;
		int cylinders;
		int heads;
		int sectors;
		const char *label;
	} drives[] = {
		{ hd_fn[0], hd_cyl[0], hd_hpc[0], hd_spt[0], "Hard Drive 4" },
		{ hd_fn[1], hd_cyl[1], hd_hpc[1], hd_spt[1], "Hard Drive 5" },
	};

	BOOL isST506 = (fdctype != FDC_82C711) && st506_present;

	for (int i = 0; i < 2; i++)
	{
		NSString *path = arc_nsstring(drives[i].path);
		if (path.length == 0 || [gShownBlankDiskWarnings containsObject:path])
			continue;

		ARCInternalDiskImageState state = [self stateForInternalDiskImageAtPath:path
									 cylinders:drives[i].cylinders
									      heads:drives[i].heads
									    sectors:drives[i].sectors
									    isST506:isST506];
		if (state != ARCInternalDiskImageStateBlankRaw)
			continue;

		[gShownBlankDiskWarnings addObject:path];

		BOOL hasTemplate = [self hasTemplateForCylinders:drives[i].cylinders
							  heads:drives[i].heads
							sectors:drives[i].sectors
							isST506:isST506];

		if (hasTemplate)
		{
			NSString *message = [NSString stringWithFormat:
				@"%s is blank. Would you like to initialize it with a ready-to-use formatted image?\n\n"
				@"This will replace the blank image with a pre-formatted template so the drive is immediately usable in RISC OS.",
				drives[i].label];

			if (arc_confirm(@"Initialize Hard Drive?", message))
			{
				NSString *error = [self createReadyHDFAtPath:path
								  cylinders:drives[i].cylinders
								      heads:drives[i].heads
								    sectors:drives[i].sectors
								    isST506:isST506];
				if (error)
					arc_show_message(@"Arculator", [NSString stringWithFormat:
						@"Could not initialize %s: %@", drives[i].label, error]);
			}
		}
		else
		{
			NSString *message = [NSString stringWithFormat:
				@"%s is attached to this config, but the image is still blank.\n\n"
				@"Arculator will expose the internal drive at startup, so it should appear in RISC OS, "
				@"but the image still needs to be partitioned/formatted inside the guest before it can be used.",
				drives[i].label];
			arc_show_message(@"Arculator", message);
		}
	}
}

+ (BOOL)renameConfig:(NSString *)oldName to:(NSString *)newName
{
	if ([self configExists:newName])
		return NO;
	NSString *oldPath = [self configPathForName:oldName];
	NSString *newPath = [self configPathForName:newName];
	return [[NSFileManager defaultManager] moveItemAtPath:oldPath toPath:newPath error:nil];
}

+ (BOOL)copyConfig:(NSString *)sourceName to:(NSString *)destName
{
	if ([self configExists:destName])
		return NO;
	NSString *srcPath = [self configPathForName:sourceName];
	NSString *dstPath = [self configPathForName:destName];
	return [[NSFileManager defaultManager] copyItemAtPath:srcPath toPath:dstPath error:nil];
}

+ (BOOL)deleteConfig:(NSString *)name
{
	NSString *path = [self configPathForName:name];
	return [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

+ (BOOL)createConfig:(NSString *)name withPresetIndex:(int)presetIndex
{
	if ([self configExists:name])
		return NO;

	NSString *path = [self configPathForName:name];
	arc_copy_string(machine_config_file, sizeof(machine_config_file), path);
	arc_copy_string(machine_config_name, sizeof(machine_config_name), name);

	ARCMachineConfig *cfg = [ARCMachineConfig configFromPresetIndex:presetIndex];
	[cfg applyToGlobals];
	return YES;
}

+ (NSDictionary *)internalDriveInfoForIndex:(int)index
{
	if (index < 0 || index > 1)
		return @{};

	NSString *path = arc_nsstring(hd_fn[index]);
	int cylinders = hd_cyl[index];
	int heads = hd_hpc[index];
	int sectors = hd_spt[index];

	BOOL isST506 = (fdctype != FDC_82C711) && st506_present;
	NSString *controllerKind = isST506 ? @"st506" : @"ide";

	NSString *imageState = @"unknown";
	if (path.length > 0)
	{
		ARCInternalDiskImageState state = [self stateForInternalDiskImageAtPath:path
									 cylinders:cylinders
									      heads:heads
									    sectors:sectors
									    isST506:isST506];
		switch (state)
		{
			case ARCInternalDiskImageStateBlankRaw:
				imageState = @"blank raw";
				break;
			case ARCInternalDiskImageStateInitialized:
				imageState = @"initialized";
				break;
			default:
				imageState = @"unknown";
				break;
		}
	}

	return @{
		@"path": path ?: @"",
		@"cylinders": @(cylinders),
		@"heads": @(heads),
		@"sectors": @(sectors),
		@"controllerKind": controllerKind,
		@"imageState": imageState
	};
}

+ (NSString *)setInternalDriveIndex:(int)index
                               path:(NSString *)path
                          cylinders:(int)cylinders
                              heads:(int)heads
                            sectors:(int)sectors
{
	if (index < 0 || index > 1)
		return @"Invalid drive index (must be 0 or 1, for drives 4 and 5)";

	if (!path.length)
		return @"Path cannot be empty";

	if (cylinders <= 0 || heads <= 0 || sectors <= 0)
		return @"Geometry values must be positive";

	arc_copy_string(hd_fn[index], sizeof(hd_fn[index]), path);
	hd_cyl[index] = cylinders;
	hd_hpc[index] = heads;
	hd_spt[index] = sectors;
	saveconfig();
	return nil;
}

+ (NSString *)ejectInternalDriveIndex:(int)index
{
	if (index < 0 || index > 1)
		return @"Invalid drive index (must be 0 or 1, for drives 4 and 5)";

	hd_fn[index][0] = '\0';
	hd_cyl[index] = 0;
	hd_hpc[index] = 0;
	hd_spt[index] = 0;
	saveconfig();
	return nil;
}

+ (NSString *)createBlankHDFAtPath:(NSString *)path
                         cylinders:(int)cylinders
                             heads:(int)heads
                           sectors:(int)sectors
                           isST506:(BOOL)isST506
{
	if (!path.length)
		return @"Path cannot be empty";

	if (cylinders <= 0 || heads <= 0 || sectors <= 0)
		return @"Geometry values must be positive";

	int sectorSize = isST506 ? 256 : 512;
	long long totalBytes = (long long)cylinders * heads * sectors * sectorSize;

	FILE *file = fopen(path.fileSystemRepresentation, "wb");
	if (!file)
		return [NSString stringWithFormat:@"Could not create file at '%@'", path];

	uint8_t zeroBuf[4096];
	memset(zeroBuf, 0, sizeof(zeroBuf));

	long long remaining = totalBytes;
	while (remaining > 0)
	{
		size_t chunk = (remaining < (long long)sizeof(zeroBuf)) ? (size_t)remaining : sizeof(zeroBuf);
		size_t written = fwrite(zeroBuf, 1, chunk, file);
		if (written != chunk)
		{
			fclose(file);
			return @"Write error while creating image file";
		}
		remaining -= (long long)written;
	}

	fclose(file);
	return nil;
}

+ (NSString *)templatePathForCylinders:(int)cylinders
                                 heads:(int)heads
                               sectors:(int)sectors
                               isST506:(BOOL)isST506
{
	NSString *kind = isST506 ? @"st506" : @"ide";
	NSString *name = [NSString stringWithFormat:@"%@_%dx%dx%d", kind, cylinders, heads, sectors];
	return [[NSBundle mainBundle] pathForResource:name ofType:@"hdf" inDirectory:@"templates"];
}

+ (BOOL)hasTemplateForCylinders:(int)cylinders
                          heads:(int)heads
                        sectors:(int)sectors
                        isST506:(BOOL)isST506
{
	return [self templatePathForCylinders:cylinders heads:heads sectors:sectors isST506:isST506] != nil;
}

+ (NSString *)createReadyHDFAtPath:(NSString *)path
                         cylinders:(int)cylinders
                             heads:(int)heads
                           sectors:(int)sectors
                           isST506:(BOOL)isST506
{
	if (!path.length)
		return @"Path cannot be empty";

	NSString *templatePath = [self templatePathForCylinders:cylinders
							 heads:heads
						       sectors:sectors
						       isST506:isST506];
	if (!templatePath)
		return [NSString stringWithFormat:
			@"No bundled template for %s geometry %dx%dx%d",
			isST506 ? "ST-506" : "IDE", cylinders, heads, sectors];

	NSError *copyError = nil;
	if (![[NSFileManager defaultManager] copyItemAtPath:templatePath toPath:path error:&copyError])
		return [NSString stringWithFormat:@"Failed to clone template: %@",
			copyError.localizedDescription ?: @"unknown error"];

	return nil;
}

+ (ARCSettingMutability)mutabilityForSetting:(NSString *)settingKey
{
	// Live: takes effect immediately while running
	if ([settingKey isEqualToString:ARCSettingDisc] ||
	    [settingKey isEqualToString:ARCSettingDisplayMode] ||
	    [settingKey isEqualToString:ARCSettingDoubleScanning] ||
	    [settingKey isEqualToString:ARCSettingSoundGain] ||
	    [settingKey isEqualToString:ARCSettingStereo] ||
	    [settingKey isEqualToString:ARCSettingDiscNoise])
		return ARCSettingMutabilityLive;

	// Stop: only editable when fully stopped
	if ([settingKey isEqualToString:ARCSettingMachinePreset] ||
	    [settingKey isEqualToString:ARCSettingIOType] ||
	    [settingKey isEqualToString:ARCSettingPodules] ||
	    [settingKey isEqualToString:ARCSettingHDPaths] ||
	    [settingKey isEqualToString:ARCSettingUniqueID] ||
	    [settingKey isEqualToString:ARCSetting5thColumnROM])
		return ARCSettingMutabilityStop;

	// Reset: requires reset to take effect (default for machine settings)
	return ARCSettingMutabilityReset;
}

@end

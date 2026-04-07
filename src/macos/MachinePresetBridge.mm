//
//  MachinePresetBridge.mm
//  Arculator
//
//  ObjC bridge for preset queries and validation.
//

#import "MachinePresetBridge.h"

extern "C" {
#include "config.h"
}

#include "MachinePresetData.h"

@implementation MachinePresetBridge

#pragma mark - Preset access

+ (NSInteger)presetCount
{
	return preset_count();
}

+ (NSString *)presetNameAtIndex:(NSInteger)index
{
	if (index < 0 || index >= preset_count())
		return @"";
	return [NSString stringWithUTF8String:presets[index].name];
}

+ (NSString *)presetConfigNameAtIndex:(NSInteger)index
{
	if (index < 0 || index >= preset_count())
		return @"";
	return [NSString stringWithUTF8String:presets[index].config_name];
}

+ (NSString *)presetDescriptionAtIndex:(NSInteger)index
{
	if (index < 0 || index >= preset_count())
		return @"";
	return [NSString stringWithUTF8String:presets[index].description];
}

+ (NSInteger)presetIndexForConfigName:(NSString *)configName
{
	return preset_from_config_name(configName.UTF8String);
}

+ (NSInteger)presetIndexForDisplayName:(NSString *)displayName
{
	return preset_from_display_name(displayName.UTF8String);
}

+ (BOOL)presetAllowedByRom:(NSInteger)presetIndex
{
	if (presetIndex < 0 || presetIndex >= preset_count())
		return NO;
	return preset_allowed_by_rom((int)presetIndex) != 0;
}

#pragma mark - Constraint queries

+ (unsigned int)allowedCpuMaskForPreset:(NSInteger)presetIndex
{
	if (presetIndex < 0 || presetIndex >= preset_count())
		return 0;
	return presets[presetIndex].allowed_cpu_mask;
}

+ (unsigned int)allowedMemMaskForPreset:(NSInteger)presetIndex
{
	if (presetIndex < 0 || presetIndex >= preset_count())
		return 0;
	return presets[presetIndex].allowed_mem_mask;
}

+ (unsigned int)allowedMemcMaskForPreset:(NSInteger)presetIndex
{
	if (presetIndex < 0 || presetIndex >= preset_count())
		return 0;
	return presets[presetIndex].allowed_memc_mask;
}

+ (unsigned int)allowedRomsetMaskForPreset:(NSInteger)presetIndex
{
	if (presetIndex < 0 || presetIndex >= preset_count())
		return 0;
	return presets[presetIndex].allowed_romset_mask;
}

+ (unsigned int)allowedMonitorMaskForPreset:(NSInteger)presetIndex
{
	if (presetIndex < 0 || presetIndex >= preset_count())
		return 0;
	return presets[presetIndex].allowed_monitor_mask;
}

+ (int)defaultCpuForPreset:(NSInteger)presetIndex
{
	if (presetIndex < 0 || presetIndex >= preset_count())
		return CPU_ARM2;
	return presets[presetIndex].default_cpu;
}

+ (int)defaultMemForPreset:(NSInteger)presetIndex
{
	if (presetIndex < 0 || presetIndex >= preset_count())
		return MEM_1M;
	return presets[presetIndex].default_mem;
}

+ (int)defaultMemcForPreset:(NSInteger)presetIndex
{
	if (presetIndex < 0 || presetIndex >= preset_count())
		return MEMC_MEMC1;
	return presets[presetIndex].default_memc;
}

+ (int)ioTypeForPreset:(NSInteger)presetIndex
{
	if (presetIndex < 0 || presetIndex >= preset_count())
		return IO_OLD;
	return presets[presetIndex].io;
}

+ (int)machineTypeForPreset:(NSInteger)presetIndex
{
	if (presetIndex < 0 || presetIndex >= preset_count())
		return MACHINE_TYPE_NORMAL;
	return presets[presetIndex].machine_type;
}

+ (int)poduleTypeForPreset:(NSInteger)presetIndex slot:(int)slot
{
	if (presetIndex < 0 || presetIndex >= preset_count() || slot < 0 || slot > 3)
		return PODULE_NONE;
	return presets[presetIndex].podule_type[slot];
}

+ (BOOL)presetHas5thColumn:(NSInteger)presetIndex
{
	if (presetIndex < 0 || presetIndex >= preset_count())
		return NO;
	return presets[presetIndex].has_5th_column;
}

#pragma mark - Validation helpers

+ (BOOL)fppcAvailableForCpu:(int)cpu memc:(int)memc
{
	return cpu == CPU_ARM2 && memc != MEMC_MEMC1;
}

+ (BOOL)fpa10AvailableForCpu:(int)cpu
{
	return cpu != CPU_ARM2 && cpu != CPU_ARM250;
}

+ (BOOL)supportRomAvailableForRom:(int)rom
{
	return rom >= ROM_RISCOS_300;
}

+ (BOOL)isA3010Preset:(NSInteger)presetIndex
{
	if (presetIndex < 0 || presetIndex >= preset_count())
		return NO;
	return strcmp(presets[presetIndex].config_name, "a3010") == 0;
}

#pragma mark - Cascade logic

+ (int)adjustFpuAfterCpuChange:(int)currentFpu newCpu:(int)newCpu
{
	if (currentFpu == FPU_NONE)
		return FPU_NONE;
	if (newCpu == CPU_ARM2)
		return FPU_FPPC;
	return FPU_FPA10;
}

+ (int)adjustMemcAfterCpuChange:(int)currentMemc newCpu:(int)newCpu
{
	if (newCpu != CPU_ARM2 && newCpu != CPU_ARM250 && currentMemc == MEMC_MEMC1)
		return MEMC_MEMC1A_8;
	return currentMemc;
}

@end

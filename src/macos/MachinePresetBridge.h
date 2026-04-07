//
//  MachinePresetBridge.h
//  Arculator
//
//  ObjC interface for preset queries and validation, callable from Swift.
//  Wraps the shared preset data in MachinePresetData.h.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MachinePresetBridge : NSObject

// Preset access
+ (NSInteger)presetCount;
+ (NSString *)presetNameAtIndex:(NSInteger)index;
+ (NSString *)presetConfigNameAtIndex:(NSInteger)index;
+ (NSString *)presetDescriptionAtIndex:(NSInteger)index;
+ (NSInteger)presetIndexForConfigName:(NSString *)configName;
+ (NSInteger)presetIndexForDisplayName:(NSString *)displayName;
+ (BOOL)presetAllowedByRom:(NSInteger)presetIndex;

// Constraint queries for a given preset
+ (unsigned int)allowedCpuMaskForPreset:(NSInteger)presetIndex;
+ (unsigned int)allowedMemMaskForPreset:(NSInteger)presetIndex;
+ (unsigned int)allowedMemcMaskForPreset:(NSInteger)presetIndex;
+ (unsigned int)allowedRomsetMaskForPreset:(NSInteger)presetIndex;
+ (unsigned int)allowedMonitorMaskForPreset:(NSInteger)presetIndex;
+ (int)defaultCpuForPreset:(NSInteger)presetIndex;
+ (int)defaultMemForPreset:(NSInteger)presetIndex;
+ (int)defaultMemcForPreset:(NSInteger)presetIndex;
+ (int)ioTypeForPreset:(NSInteger)presetIndex;
+ (int)machineTypeForPreset:(NSInteger)presetIndex;
+ (int)poduleTypeForPreset:(NSInteger)presetIndex slot:(int)slot;
+ (BOOL)presetHas5thColumn:(NSInteger)presetIndex;

// Validation helpers
+ (BOOL)fppcAvailableForCpu:(int)cpu memc:(int)memc;
+ (BOOL)fpa10AvailableForCpu:(int)cpu;
+ (BOOL)supportRomAvailableForRom:(int)rom;
+ (BOOL)isA3010Preset:(NSInteger)presetIndex;

// Cascade logic (returns adjusted values after a change)
+ (int)adjustFpuAfterCpuChange:(int)currentFpu newCpu:(int)newCpu;
+ (int)adjustMemcAfterCpuChange:(int)currentMemc newCpu:(int)newCpu;

@end

NS_ASSUME_NONNULL_END

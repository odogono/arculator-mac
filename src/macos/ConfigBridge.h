//
//  ConfigBridge.h
//  Arculator
//
//  ObjC facade for config list management, config state application,
//  and setting mutability classification.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Mutability classification for settings
typedef NS_ENUM(NSInteger, ARCSettingMutability) {
	ARCSettingMutabilityLive,       // Takes effect immediately while running
	ARCSettingMutabilityPauseApply, // Editable while paused, no reset needed
	ARCSettingMutabilityReset,      // Requires reset to take effect
	ARCSettingMutabilityStop        // Only editable when fully stopped
};

typedef NS_ENUM(NSInteger, ARCInternalDiskImageState) {
	ARCInternalDiskImageStateUnknown = 0,
	ARCInternalDiskImageStateBlankRaw,
	ARCInternalDiskImageStateInitialized
};

// Intermediate config state (mirrors the dialog's configXxx variables).
// Used to read/write config state without coupling to a UI dialog.
@interface ARCMachineConfig : NSObject

@property (nonatomic) int preset;
@property (nonatomic) int cpu;
@property (nonatomic) int mem;
@property (nonatomic) int memc;
@property (nonatomic) int fpu;
@property (nonatomic) int io;
@property (nonatomic) int rom;
@property (nonatomic) int monitor;
@property (nonatomic) uint32_t uniqueId;
@property (nonatomic, copy) NSString *podule0;
@property (nonatomic, copy) NSString *podule1;
@property (nonatomic, copy) NSString *podule2;
@property (nonatomic, copy) NSString *podule3;
@property (nonatomic, copy) NSString *joystickInterface;
@property (nonatomic, copy) NSString *hdPath0;
@property (nonatomic, copy) NSString *hdPath1;
@property (nonatomic) int hdCyl0, hdHpc0, hdSpt0;
@property (nonatomic) int hdCyl1, hdHpc1, hdSpt1;
@property (nonatomic, copy) NSString *fifthColumnPath;
@property (nonatomic) BOOL supportRomEnabled;

// Factory: populate from current C globals (for editing existing config)
+ (instancetype)configFromGlobals;

// Factory: populate from preset defaults (for creating new config)
+ (instancetype)configFromPresetIndex:(int)presetIndex;

// Apply this config state to C globals and call saveconfig()
- (void)applyToGlobals;

// Apply to globals and reset emulation if a session is active
- (void)applyToGlobalsAndResetIfRunning;

@end

// Config list management and file operations
@interface ConfigBridge : NSObject

// Returns sorted list of config names (without .cfg extension)
+ (NSArray<NSString *> *)listConfigNames;

// Returns full path for a config name
+ (NSString *)configPathForName:(NSString *)name;

// Check if a config file exists
+ (BOOL)configExists:(NSString *)name;

// Load a named config: sets machine_config_file/name globals and calls loadconfig()
+ (BOOL)loadConfigNamed:(NSString *)name;

// Inspect an attached internal disc image to determine whether it looks blank
// or already initialized for guest use.
+ (ARCInternalDiskImageState)stateForInternalDiskImageAtPath:(NSString *)path
						  cylinders:(int)cylinders
						       heads:(int)heads
						     sectors:(int)sectors
						     isST506:(BOOL)isST506;

// Show one-shot startup guidance for attached blank internal disc images.
+ (void)showStartupWarningsForLoadedConfigIfNeeded;

// File operations (return YES on success)
+ (BOOL)renameConfig:(NSString *)oldName to:(NSString *)newName;
+ (BOOL)copyConfig:(NSString *)sourceName to:(NSString *)destName;
+ (BOOL)deleteConfig:(NSString *)name;

// Create a new config file with preset defaults
+ (BOOL)createConfig:(NSString *)name withPresetIndex:(int)presetIndex;

// Mutability matrix lookup
+ (ARCSettingMutability)mutabilityForSetting:(NSString *)settingKey;

// Internal hard-drive info record (drive index 0 = hd4, 1 = hd5)
+ (NSDictionary *)internalDriveInfoForIndex:(int)index;

// Set internal drive path and geometry (while idle). Returns nil on success, error string on failure.
+ (NSString *_Nullable)setInternalDriveIndex:(int)index
                                        path:(NSString *)path
                                   cylinders:(int)cylinders
                                       heads:(int)heads
                                     sectors:(int)sectors;

// Eject internal drive (while idle). Returns nil on success, error string on failure.
+ (NSString *_Nullable)ejectInternalDriveIndex:(int)index;

// Create a blank HDF image file. Returns nil on success, error string on failure.
+ (NSString *_Nullable)createBlankHDFAtPath:(NSString *)path
                                  cylinders:(int)cylinders
                                      heads:(int)heads
                                    sectors:(int)sectors
                                    isST506:(BOOL)isST506;

// Create a ready (pre-formatted) HDF by cloning a bundled template.
// Returns nil on success, error string on failure.
+ (NSString *_Nullable)createReadyHDFAtPath:(NSString *)path
                                  cylinders:(int)cylinders
                                      heads:(int)heads
                                    sectors:(int)sectors
                                    isST506:(BOOL)isST506;

// Returns YES if a bundled template exists for the given default geometry.
+ (BOOL)hasTemplateForCylinders:(int)cylinders
                          heads:(int)heads
                        sectors:(int)sectors
                        isST506:(BOOL)isST506;

// Returns the bundle path for a template matching the given geometry, or nil.
+ (NSString *_Nullable)templatePathForCylinders:(int)cylinders
                                          heads:(int)heads
                                        sectors:(int)sectors
                                        isST506:(BOOL)isST506;

@end

// Setting key constants for the mutability matrix
extern NSString *const ARCSettingDisc;
extern NSString *const ARCSettingDisplayMode;
extern NSString *const ARCSettingDoubleScanning;
extern NSString *const ARCSettingSoundGain;
extern NSString *const ARCSettingStereo;
extern NSString *const ARCSettingDiscNoise;
extern NSString *const ARCSettingCPU;
extern NSString *const ARCSettingMEMC;
extern NSString *const ARCSettingMemory;
extern NSString *const ARCSettingFPU;
extern NSString *const ARCSettingROM;
extern NSString *const ARCSettingMonitor;
extern NSString *const ARCSettingJoystickInterface;
extern NSString *const ARCSettingSupportROM;
extern NSString *const ARCSettingMachinePreset;
extern NSString *const ARCSettingIOType;
extern NSString *const ARCSettingPodules;
extern NSString *const ARCSettingHDPaths;
extern NSString *const ARCSettingUniqueID;
extern NSString *const ARCSetting5thColumnROM;

NS_ASSUME_NONNULL_END

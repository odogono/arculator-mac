//
//  ConfigEditorBridge.h
//  Arculator
//
//  ObjC bridge for launching existing modal sub-dialogs (HD, podule config,
//  joystick config) from SwiftUI. Wraps the C++ dialog functions that
//  Swift cannot call directly.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Result from an HD dialog (new or configure).
@interface ARCHDDialogResult : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic) int cylinders;
@property (nonatomic) int heads;
@property (nonatomic) int sectors;
@end

@interface ConfigEditorBridge : NSObject

/// Show the podule configuration dialog for a given slot.
/// The podule is identified by its short name (e.g. "ide").
/// @param shortName Internal podule identifier
/// @param running Whether emulation is currently running/paused
/// @param slot Slot number (0-3)
+ (void)showPoduleConfigForShortName:(NSString *)shortName running:(BOOL)running slot:(int)slot;

/// Show the "Configure existing HD" dialog. Returns result or nil if cancelled.
/// @param path Current HD image path
/// @param isST506 YES for Old IO + ST-506 drives
+ (nullable ARCHDDialogResult *)showConfHDWithPath:(NSString *)path isST506:(BOOL)isST506;

/// Show the "New HD" dialog. Returns result or nil if cancelled.
/// @param isST506 YES for Old IO + ST-506 drives
+ (nullable ARCHDDialogResult *)showNewHDWithST506:(BOOL)isST506;

/// Show the joystick configuration dialog.
/// @param playerIndex 0 or 1 (Joy 1 / Joy 2)
/// @param joystickType Index of the joystick interface type
+ (void)showJoystickConfigForPlayer:(int)playerIndex type:(int)joystickType;

/// Returns the joystick type index for a given config name.
+ (int)joystickTypeIndexForConfigName:(NSString *)configName;

@end

NS_ASSUME_NONNULL_END

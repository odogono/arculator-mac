//
//  NewWindowBridge.h
//  Arculator
//
//  ObjC bridge between app_macos.mm (ObjC++) and Swift UI classes.
//  app_macos.mm cannot import Arculator-Swift.h due to -fno-modules
//  and extern "C" header conflicts, so this pure ObjC file mediates.
//

#import <Cocoa/Cocoa.h>
#import <MetalKit/MetalKit.h>

@interface NewWindowBridge : NSObject

+ (NSWindow *)createMainWindowWithDelegate:(nullable id<NSWindowDelegate>)delegate;
+ (nullable MTKView *)installEmulatorViewInWindow:(NSWindow *)window;
+ (void)removeEmulatorViewFromWindow:(NSWindow *)window;
+ (void)preselectAndRunConfig:(NSString *)configName inWindow:(NSWindow *)window;
+ (void)enterFullscreenForWindow:(NSWindow *)window;
+ (void)exitFullscreenForWindow:(NSWindow *)window;
+ (void)navigateToConfigEditorInWindow:(NSWindow *)window;

// Show the snapshot browser page in the given window's split view.
// Called from app_macos.mm when the Load Snapshot menu item fires.
+ (void)navigateToSnapshotBrowserInWindow:(NSWindow *)window;

// Recent snapshots accessors, bridging AppSettings so app_macos.mm's
// File menu code can read and mutate the recent list without needing
// to import Arculator-Swift.h.
+ (NSArray<NSString *> *)recentSnapshotPaths;
+ (void)recordRecentSnapshot:(NSString *)path;
+ (void)removeRecentSnapshot:(NSString *)path;
+ (void)pruneMissingRecentSnapshots;

// Name of the NSNotification posted when the recent snapshots list
// changes. app_macos.mm subscribes to this to rebuild the submenu.
+ (NSNotificationName)recentSnapshotsChangedNotificationName;

@end

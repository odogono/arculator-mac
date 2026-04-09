//
//  EmulatorBridge.h
//  Arculator
//
//  Pure ObjC facade wrapping C/C++ emulation control functions.
//  Swift cannot call C++ directly, so this provides an ObjC interface
//  to the emulation lifecycle, disc operations, and video view management.
//

#import <Foundation/Foundation.h>
#import <MetalKit/MetalKit.h>

@class NSImage;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ARCSessionState) {
	ARCSessionStateIdle,
	ARCSessionStateRunning,
	ARCSessionStatePaused
};

@interface EmulatorBridge : NSObject

// Lifecycle
+ (void)startEmulation;
+ (void)stopEmulation;
+ (void)pauseEmulation;
+ (void)resumeEmulation;
+ (void)resetEmulation;

// High-level: load config by name and start emulation
+ (BOOL)startEmulationForConfig:(NSString *)configName;
+ (nullable NSString *)lastStartError;

// Disc operations
+ (void)changeDisc:(int)drive path:(NSString *)path;
+ (void)ejectDisc:(int)drive;

// State queries
+ (BOOL)isSessionActive;
+ (BOOL)isPaused;
+ (ARCSessionState)sessionState;
+ (NSString *)activeConfigName;

// Video view
+ (void)setVideoView:(MTKView *)view;
+ (nullable MTKView *)videoView;

// Installs an emulator video view in the current main window if one
// isn't already present. Returns YES on success. Used by both the
// normal start flow and the snapshot-load flow.
+ (BOOL)ensureVideoViewInstalled;

// Capture a screenshot of the emulation view to a PNG file.
// Returns nil on success, or an error string on failure.
+ (nullable NSString *)captureScreenshotToPath:(NSString *)path;

// Capture a screenshot of the emulation view to the system clipboard.
// Returns nil on success, or an error string on failure.
+ (nullable NSString *)copyScreenshotToPasteboard;

// Snapshot save: queue a save-snapshot command for the emulation
// thread. Returns YES if the queue accepted the command; errors from
// the actual save are delivered asynchronously via arc_print_error().
+ (BOOL)saveSnapshotToPath:(NSString *)path error:(NSString * _Nullable * _Nullable)error;

// Snapshot load: open a .arcsnap file and start a fresh emulation
// session from it. Session must be idle. Returns YES on success, NO
// on failure with `error` populated.
+ (BOOL)startSnapshotSessionFromPath:(NSString *)path error:(NSString * _Nullable * _Nullable)error;

// Returns YES if the currently paused session is in a state where a
// snapshot can be saved right now. On NO, populates `error` with the
// rejection reason.
+ (BOOL)canSaveSnapshotWithError:(NSString * _Nullable * _Nullable)error;

// Convenience wrapper that returns YES if snapshot_can_save() approves
// right now, and drops any error message. Used for reactive Swift UI
// gating.
+ (BOOL)canSaveSnapshot;

@end

// ----- Snapshot browser summary data ----------------------------------
//
// A Swift-visible snapshot summary for the browser UI. One per .arcsnap
// file that peeked successfully. Built from the core `arcsnap_summary_t`
// by +[EmulatorBridge peekSnapshotSummaryAtPath:error:].
@interface SnapshotSummaryData : NSObject
@property (nonatomic, copy)   NSString                *filePath;
@property (nonatomic, copy)   NSString                *displayName;       // META.name or fallback
@property (nonatomic, copy, nullable) NSString        *descriptionText;   // META.description, may be nil/empty
@property (nonatomic, copy)   NSString                *machineConfigName; // manifest.original_config_name
@property (nonatomic, copy)   NSString                *machine;           // manifest.machine (e.g. "a3000")
@property (nonatomic, strong, nullable) NSDate        *createdAt;         // from META or file mtime
@property (nonatomic, copy)   NSArray<NSString *>     *floppyPaths;
@property (nonatomic, strong, nullable) NSImage       *preview;           // from PREV chunk
@property (nonatomic, assign) unsigned long long       fileSize;
@end

@interface EmulatorBridge (SnapshotBrowser)

// Opens a .arcsnap file in read-only mode, parses MNFT + optional META
// and PREV, and returns a populated SnapshotSummaryData. Returns nil on
// failure with `error` set to a human-readable message.
+ (nullable SnapshotSummaryData *)peekSnapshotSummaryAtPath:(NSString *)path
                                                      error:(NSString * _Nullable * _Nullable)error;

// Returns the absolute path of `<support>/snapshots/` as a string.
+ (NSString *)snapshotsDirectoryPath;

@end

NS_ASSUME_NONNULL_END

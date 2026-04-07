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

// Capture a screenshot of the emulation view to a PNG file.
// Returns nil on success, or an error string on failure.
+ (nullable NSString *)captureScreenshotToPath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END

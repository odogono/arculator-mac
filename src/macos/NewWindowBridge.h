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

@end

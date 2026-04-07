//
//  EmulatorBridge.mm
//  Arculator
//
//  Pure ObjC facade wrapping C/C++ emulation control functions.
//

#import "EmulatorBridge.h"
#import "ConfigBridge.h"

extern "C" {
#include "config.h"
#include "platform_shell.h"
}

#import <MetalKit/MetalKit.h>

// Defined in app_macos.mm
extern void arc_set_video_view(MTKView *view);
extern MTKView *arc_get_video_view(void);

@implementation EmulatorBridge

+ (void)startEmulation {
    [ConfigBridge showStartupWarningsForLoadedConfigIfNeeded];
    arc_start_main_thread(NULL, NULL);
}

+ (void)stopEmulation {
    arc_stop_main_thread();
}

+ (void)pauseEmulation {
    arc_pause_main_thread();
}

+ (void)resumeEmulation {
    arc_resume_main_thread();
}

+ (void)resetEmulation {
    arc_do_reset();
}

+ (BOOL)startEmulationForConfig:(NSString *)configName {
    if (![ConfigBridge loadConfigNamed:configName])
        return NO;
    [ConfigBridge showStartupWarningsForLoadedConfigIfNeeded];
    arc_start_main_thread(NULL, NULL);
    return YES;
}

+ (void)changeDisc:(int)drive path:(NSString *)path {
    arc_disc_change(drive, (char *)[path fileSystemRepresentation]);
}

+ (void)ejectDisc:(int)drive {
    arc_disc_eject(drive);
}

+ (BOOL)isSessionActive {
    return arc_is_session_active() != 0;
}

+ (BOOL)isPaused {
    return arc_is_paused() != 0;
}

+ (ARCSessionState)sessionState {
    if (!arc_is_session_active())
        return ARCSessionStateIdle;
    if (arc_is_paused())
        return ARCSessionStatePaused;
    return ARCSessionStateRunning;
}

+ (NSString *)activeConfigName {
    if (machine_config_name[0] == '\0')
        return @"";
    return [NSString stringWithUTF8String:machine_config_name] ?: @"";
}

+ (void)setVideoView:(MTKView *)view {
    arc_set_video_view(view);
}

+ (MTKView *)videoView {
    return arc_get_video_view();
}

+ (NSString *)captureScreenshotToPath:(NSString *)path
{
    __block NSString *error = nil;

    void (^captureBlock)(void) = ^{
        MTKView *view = arc_get_video_view();
        if (!view)
        {
            error = @"No emulation view available";
            return;
        }

        NSWindow *window = view.window;
        if (!window)
        {
            error = @"Emulation view has no window";
            return;
        }

        NSRect rectInWindow = [view convertRect:view.bounds toView:nil];
        NSRect rectInScreen = [window convertRectToScreen:rectInWindow];
        CGImageRef imageRef = CGWindowListCreateImage(
            rectInScreen,
            kCGWindowListOptionIncludingWindow,
            (CGWindowID)window.windowNumber,
            kCGWindowImageBoundsIgnoreFraming | kCGWindowImageNominalResolution);

        if (!imageRef)
        {
            error = @"Failed to capture window image";
            return;
        }

        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:imageRef];
        CGImageRelease(imageRef);

        NSData *pngData = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        if (!pngData)
        {
            error = @"Failed to encode PNG";
            return;
        }

        if (![pngData writeToFile:path atomically:YES])
            error = [NSString stringWithFormat:@"Failed to write file: %@", path];
    };

    if ([NSThread isMainThread])
        captureBlock();
    else
        dispatch_sync(dispatch_get_main_queue(), captureBlock);

    return error;
}

@end

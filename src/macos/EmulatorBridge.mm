//
//  EmulatorBridge.mm
//  Arculator
//
//  Pure ObjC facade wrapping C/C++ emulation control functions.
//

#import "EmulatorBridge.h"
#import "ConfigBridge.h"
#import "NewWindowBridge.h"
#import "macos_util.h"

extern "C" {
#include "config.h"
#include "platform_shell.h"
#include "snapshot.h"
}

#import <MetalKit/MetalKit.h>

// Defined in app_macos.mm
extern void arc_set_video_view(MTKView *view);
extern MTKView *arc_get_video_view(void);
extern "C" NSString *video_renderer_capture_screenshot(NSString *path);

static NSString *sLastStartError = nil;

@implementation EmulatorBridge

+ (BOOL)ensureVideoViewInstalled
{
    if (arc_get_video_view() != nil)
    {
        sLastStartError = nil;
        return YES;
    }

    __block BOOL installed = NO;
    run_on_main_thread(^{
        NSWindow *targetWindow = NSApp.mainWindow;
        if (!targetWindow)
        {
            for (NSWindow *window in NSApp.orderedWindows)
            {
                if (window.contentViewController)
                {
                    targetWindow = window;
                    break;
                }
            }
        }

        if (!targetWindow)
            return;

        installed = ([NewWindowBridge installEmulatorViewInWindow:targetWindow] != nil);
    });

    if (!(installed && arc_get_video_view() != nil))
    {
        sLastStartError = @"Cannot start emulation because no emulator window/view is available";
        return NO;
    }

    sLastStartError = nil;
    return YES;
}

+ (void)startEmulation {
    if (![self ensureVideoViewInstalled])
        return;
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
    {
        sLastStartError = [NSString stringWithFormat:@"Failed to load config: '%@'", configName];
        return NO;
    }
    if (![self ensureVideoViewInstalled])
        return NO;
    [ConfigBridge showStartupWarningsForLoadedConfigIfNeeded];
    arc_start_main_thread(NULL, NULL);
    return YES;
}

+ (NSString *)lastStartError
{
    return sLastStartError;
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

+ (BOOL)saveSnapshotToPath:(NSString *)path error:(NSString **)error
{
    if (error)
        *error = nil;
    if (path.length == 0)
    {
        if (error)
            *error = @"No snapshot path";
        return NO;
    }
    if (!arc_is_session_active())
    {
        if (error)
            *error = @"No active emulation session";
        return NO;
    }
    if (!arc_is_paused())
    {
        if (error)
            *error = @"Pause emulation before saving a snapshot";
        return NO;
    }

    char err_buf[256];
    if (!snapshot_can_save(err_buf, sizeof(err_buf)))
    {
        if (error)
            *error = [NSString stringWithUTF8String:err_buf];
        return NO;
    }

    arc_save_snapshot([path fileSystemRepresentation]);
    return YES;
}

+ (BOOL)startSnapshotSessionFromPath:(NSString *)path error:(NSString **)error
{
    if (error)
        *error = nil;
    if (path.length == 0)
    {
        if (error)
            *error = @"No snapshot path";
        return NO;
    }

    char err_buf[512];
    err_buf[0] = 0;
    if (!arc_start_snapshot_session([path fileSystemRepresentation],
                                    err_buf, sizeof(err_buf)))
    {
        if (error)
        {
            *error = err_buf[0]
                ? [NSString stringWithUTF8String:err_buf]
                : @"Failed to start snapshot session";
        }
        return NO;
    }
    return YES;
}

+ (BOOL)canSaveSnapshotWithError:(NSString **)error
{
    if (error)
        *error = nil;

    char err_buf[256];
    if (!snapshot_can_save(err_buf, sizeof(err_buf)))
    {
        if (error)
            *error = [NSString stringWithUTF8String:err_buf];
        return NO;
    }
    return YES;
}

+ (BOOL)canSaveSnapshot
{
    return snapshot_can_save(NULL, 0) != 0;
}

+ (NSString *)captureScreenshotToPath:(NSString *)path
{
    __block NSString *error = nil;

    run_on_main_thread(^{
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

        NSTask *task = [[NSTask alloc] init];
        task.launchPath = @"/usr/sbin/screencapture";
        task.arguments = @[
            @"-x",
            @"-o",
            @"-l", [NSString stringWithFormat:@"%ld", (long)window.windowNumber],
            path
        ];

        @try
        {
            [task launch];
            [task waitUntilExit];
            if (task.terminationStatus == 0)
                return;
        }
        @catch (NSException *exception) { }

        if (!video_renderer_capture_screenshot(path))
            return;

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
    });

    return error;
}

@end

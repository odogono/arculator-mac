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
#include "platform_paths.h"
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

/* Captures a PNG screenshot via captureScreenshotToPath: into a temp
 * file, reads it back into memory, removes the temp file, and returns
 * the heap-allocated bytes plus dimensions. Returns NULL on any failure
 * (callers fall back to a snapshot with no preview chunk). */
static uint8_t *capture_preview_png(size_t *out_size, int *out_width, int *out_height)
{
    *out_size   = 0;
    *out_width  = 0;
    *out_height = 0;

    NSString *tempDir = NSTemporaryDirectory();
    NSString *fileName = [NSString stringWithFormat:@"arcsnap_preview_%@.png",
                                                    [[NSUUID UUID] UUIDString]];
    NSString *tempPath = [tempDir stringByAppendingPathComponent:fileName];

    NSString *captureError = [EmulatorBridge captureScreenshotToPath:tempPath];
    if (captureError)
    {
        NSLog(@"Snapshot preview capture failed: %@", captureError);
        return NULL;
    }

    NSData *pngData = [NSData dataWithContentsOfFile:tempPath];
    [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];
    if (!pngData || pngData.length == 0)
    {
        NSLog(@"Snapshot preview capture produced no data");
        return NULL;
    }

    int width = 0;
    int height = 0;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithData:pngData];
    if (rep)
    {
        width  = (int)rep.pixelsWide;
        height = (int)rep.pixelsHigh;
    }

    uint8_t *buf = (uint8_t *)malloc(pngData.length);
    if (!buf)
        return NULL;
    memcpy(buf, pngData.bytes, pngData.length);

    *out_size   = pngData.length;
    *out_width  = width;
    *out_height = height;
    return buf;
}

static void meta_add_property(arcsnap_meta_t *meta, uint32_t *idx,
                              const char *key, const char *value)
{
    if (*idx >= ARCSNAP_META_MAX_PROPS)
        return;
    snprintf(meta->properties[*idx].key,
             sizeof(meta->properties[*idx].key),
             "%s", key ? key : "");
    snprintf(meta->properties[*idx].value,
             sizeof(meta->properties[*idx].value),
             "%s", value ? value : "");
    (*idx)++;
}

/* Returns NULL on allocation failure; callers fall back to a snapshot
 * with no META chunk (save still succeeds). */
static arcsnap_meta_t *build_save_meta(void)
{
    arcsnap_meta_t *meta = (arcsnap_meta_t *)calloc(1, sizeof(*meta));
    if (!meta)
        return NULL;

    meta->version = ARCSNAP_META_VERSION;
    meta->created_at_unix_ms_utc =
        (uint64_t)([[NSDate date] timeIntervalSince1970] * 1000.0);

    NSString *osVersion = [[NSProcessInfo processInfo] operatingSystemVersionString];
    NSString *appVersion = [NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"];

    uint32_t p = 0;
    meta_add_property(meta, &p, "host_os_name",            "macOS");
    meta_add_property(meta, &p, "host_os_version",         osVersion.UTF8String);
    meta_add_property(meta, &p, "emulator_version_string", appVersion.UTF8String);
    meta->property_count = p;
    return meta;
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

    /* Best-effort preview capture: if capture fails, save without a
     * preview chunk rather than blocking the save. */
    size_t   preview_size   = 0;
    int      preview_width  = 0;
    int      preview_height = 0;
    uint8_t *preview_bytes  = capture_preview_png(&preview_size,
                                                  &preview_width,
                                                  &preview_height);

    arcsnap_meta_t *meta = build_save_meta();

    /* Ownership of preview_bytes and meta transfers to arc_save_snapshot;
     * it frees them on queue failure or later on the emulation thread. */
    arc_save_snapshot([path fileSystemRepresentation],
                      preview_bytes, preview_size,
                      preview_width, preview_height,
                      meta);
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

// ----- Snapshot browser bridge --------------------------------------

@implementation SnapshotSummaryData
@end

@implementation EmulatorBridge (SnapshotBrowser)

+ (NSString *)snapshotsDirectoryPath
{
    char buf[4096] = {0};
    platform_path_snapshots_dir(buf, sizeof(buf));
    if (!buf[0])
        return @"";
    return [NSString stringWithUTF8String:buf] ?: @"";
}

+ (nullable SnapshotSummaryData *)peekSnapshotSummaryAtPath:(NSString *)path
                                                      error:(NSString **)error
{
    if (error)
        *error = nil;
    if (path.length == 0)
    {
        if (error)
            *error = @"No snapshot path";
        return nil;
    }

    arcsnap_summary_t summary;
    memset(&summary, 0, sizeof(summary));

    char err_buf[512] = {0};
    if (!snapshot_peek_summary([path fileSystemRepresentation],
                               &summary, err_buf, sizeof(err_buf)))
    {
        if (error)
            *error = err_buf[0]
                ? [NSString stringWithUTF8String:err_buf]
                : @"Failed to read snapshot";
        snapshot_summary_dispose(&summary);
        return nil;
    }

    SnapshotSummaryData *data = [[SnapshotSummaryData alloc] init];
    data.filePath = path;

    NSString *metaName = (summary.has_meta && summary.meta.name[0])
        ? [NSString stringWithUTF8String:summary.meta.name]
        : nil;
    NSString *configName = summary.manifest.original_config_name[0]
        ? [NSString stringWithUTF8String:summary.manifest.original_config_name]
        : nil;
    data.displayName = metaName.length ? metaName
                     : configName.length ? configName
                     : [[path lastPathComponent] stringByDeletingPathExtension];

    if (summary.has_meta && summary.meta.description[0])
        data.descriptionText = [NSString stringWithUTF8String:summary.meta.description];

    data.machineConfigName = configName ?: @"";
    data.machine = summary.manifest.machine[0]
        ? [NSString stringWithUTF8String:summary.manifest.machine]
        : @"";

    if (summary.has_meta && summary.meta.created_at_unix_ms_utc)
    {
        NSTimeInterval secs = (NSTimeInterval)summary.meta.created_at_unix_ms_utc / 1000.0;
        data.createdAt = [NSDate dateWithTimeIntervalSince1970:secs];
    }

    NSMutableArray<NSString *> *floppies = [NSMutableArray array];
    for (int i = 0; i < summary.manifest.floppy_count && i < 4; i++)
    {
        const char *fp = summary.manifest.floppies[i].original_path;
        if (fp && fp[0])
            [floppies addObject:[NSString stringWithUTF8String:fp]];
    }
    data.floppyPaths = [floppies copy];

    if (summary.has_preview && summary.preview_png && summary.preview_png_size > 0)
    {
        NSData *pngData = [NSData dataWithBytes:summary.preview_png
                                         length:summary.preview_png_size];
        data.preview = [[NSImage alloc] initWithData:pngData];
    }

    NSError *fileErr = nil;
    NSDictionary *attrs = [[NSFileManager defaultManager]
        attributesOfItemAtPath:path error:&fileErr];
    if (attrs)
    {
        data.fileSize = [attrs fileSize];
        if (!data.createdAt)
        {
            NSDate *mtime = attrs.fileModificationDate;
            if (mtime) data.createdAt = mtime;
        }
    }

    snapshot_summary_dispose(&summary);
    return data;
}

@end

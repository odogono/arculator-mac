//
//  NewWindowBridge.mm
//  Arculator
//
//  Pure ObjC bridge that imports Arculator-Swift.h to create and manage
//  the new split-view window shell from ObjC++ code in app_macos.mm.
//

#import "NewWindowBridge.h"
#import "EmulatorBridge.h"
#import "ConfigBridge.h"
#import <objc/runtime.h>

// Auto-generated header exposing Swift @objc classes to ObjC
#import "Arculator-Swift.h"

static const void *kToolbarManagerKey = &kToolbarManagerKey;
static NSString *const kMainWindowAutosaveName = @"ArculatorMainWindow";

@implementation NewWindowBridge

+ (MainSplitViewController *)splitVCForWindow:(NSWindow *)window
{
    MainSplitViewController *splitVC = (MainSplitViewController *)window.contentViewController;
    if (![splitVC isKindOfClass:[MainSplitViewController class]])
        return nil;
    return splitVC;
}

+ (NSWindow *)createMainWindowWithDelegate:(id<NSWindowDelegate>)delegate
{
    NSRect frame = NSMakeRect(0.0, 0.0, 1024.0, 700.0);
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                              NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;

    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:style
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"Arculator";
    window.releasedWhenClosed = NO;
    window.minSize = NSMakeSize(640, 480);
    if (![window setFrameUsingName:kMainWindowAutosaveName])
        [window center];
    [window setFrameAutosaveName:kMainWindowAutosaveName];

    if (delegate)
        window.delegate = delegate;

    MainSplitViewController *splitVC = [[MainSplitViewController alloc] init];
    window.contentViewController = splitVC;

    ToolbarManager *toolbarMgr = [[ToolbarManager alloc] init];
    toolbarMgr.splitViewController = splitVC;
    toolbarMgr.configListModel = splitVC.configListModel;
    NSToolbar *toolbar = [toolbarMgr createToolbar];
    window.toolbar = toolbar;

    // Retain the toolbar manager for the lifetime of the window
    objc_setAssociatedObject(window, kToolbarManagerKey, toolbarMgr, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    return window;
}

+ (MTKView *)installEmulatorViewInWindow:(NSWindow *)window
{
    MainSplitViewController *splitVC = [self splitVCForWindow:window];
    if (!splitVC)
        return nil;

    return [splitVC.contentController installEmulatorView];
}

+ (void)removeEmulatorViewFromWindow:(NSWindow *)window
{
    MainSplitViewController *splitVC = [self splitVCForWindow:window];
    if (!splitVC)
        return;

    [splitVC.contentController removeEmulatorView];
}

+ (void)preselectAndRunConfig:(NSString *)configName inWindow:(NSWindow *)window
{
    MainSplitViewController *splitVC = [self splitVCForWindow:window];
    if (!splitVC)
        return;

    // Preselect in sidebar and load config into C globals directly (don't rely
    // on Combine subscription timing for the load).
    [splitVC.configListModel selectConfigNamed:configName];
    [ConfigBridge loadConfigNamed:configName];

    [splitVC.contentController installEmulatorView];
    if (![EmulatorBridge startEmulationForConfig:configName])
        [splitVC.contentController removeEmulatorView];
}

+ (void)enterFullscreenForWindow:(NSWindow *)window
{
    MainSplitViewController *splitVC = [self splitVCForWindow:window];
    if (!splitVC)
        return;

    [splitVC enterFullscreen];
}

+ (void)exitFullscreenForWindow:(NSWindow *)window
{
    MainSplitViewController *splitVC = [self splitVCForWindow:window];
    if (!splitVC)
        return;

    [splitVC exitFullscreen];
}

+ (void)navigateToConfigEditorInWindow:(NSWindow *)window
{
    MainSplitViewController *splitVC = [self splitVCForWindow:window];
    if (!splitVC)
        return;

    [splitVC navigateToConfigEditor];
}

@end

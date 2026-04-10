#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

extern "C"
{
#include "arc.h"
#include "config.h"
#include "debugger.h"
#include "disc.h"
#include "emulation_control.h"
#include "ioc.h"
#include "plat_input.h"
#include "plat_joystick.h"
#include "platform_paths.h"
#include "platform_shell.h"
#include "plat_video.h"
#include "podules.h"
#include "romload.h"
#include "snapshot.h"
#include "sound.h"
#include "video.h"
}

#include "wx-console.h"
#include "macos/release_shortcut_logic.h"

#import "NewWindowBridge.h"
#import "EmulatorBridge.h"

#define MENU_FILE_LOAD_RECENT_SNAPSHOT_MAX 10

enum
{
	MENU_FILE_RESET = 1000,
	MENU_FILE_SAVE_SNAPSHOT,
	MENU_FILE_LOAD_SNAPSHOT,
	MENU_FILE_TAKE_SCREENSHOT,
	MENU_FILE_LOAD_RECENT_SNAPSHOT_BASE,
	MENU_FILE_EXIT = MENU_FILE_LOAD_RECENT_SNAPSHOT_BASE + MENU_FILE_LOAD_RECENT_SNAPSHOT_MAX,
	MENU_DISC_CHANGE_0,
	MENU_DISC_CHANGE_1,
	MENU_DISC_CHANGE_2,
	MENU_DISC_CHANGE_3,
	MENU_DISC_EJECT_0,
	MENU_DISC_EJECT_1,
	MENU_DISC_EJECT_2,
	MENU_DISC_EJECT_3,
	MENU_DISC_NOISE_0,
	MENU_DISC_NOISE_1,
	MENU_DISC_NOISE_2,
	MENU_DISC_NOISE_3,
	MENU_DISC_NOISE_4,
	MENU_VIDEO_FULLSCR,
	MENU_VIDEO_NO_BORDERS,
	MENU_VIDEO_NATIVE_BORDERS,
	MENU_VIDEO_TV,
	MENU_BLIT_SCAN,
	MENU_BLIT_SCALE,
	MENU_BLACK_ACORN,
	MENU_BLACK_NORMAL,
	MENU_DRIVER_AUTO,
	MENU_DRIVER_DIRECT3D,
	MENU_DRIVER_OPENGL,
	MENU_DRIVER_SOFTWARE,
	MENU_VIDEO_SCALE_NEAREST,
	MENU_VIDEO_SCALE_LINEAR,
	MENU_VIDEO_FS_FULL,
	MENU_VIDEO_FS_43,
	MENU_VIDEO_FS_SQ,
	MENU_VIDEO_FS_INT,
	MENU_VIDEO_SCALE_0,
	MENU_VIDEO_SCALE_1,
	MENU_VIDEO_SCALE_2,
	MENU_VIDEO_SCALE_3,
	MENU_VIDEO_SCALE_4,
	MENU_VIDEO_SCALE_5,
	MENU_VIDEO_SCALE_6,
	MENU_VIDEO_SCALE_7,
	MENU_SOUND_ENABLE,
	MENU_SOUND_STEREO,
	MENU_SOUND_GAIN_0,
	MENU_SOUND_GAIN_1,
	MENU_SOUND_GAIN_2,
	MENU_SOUND_GAIN_3,
	MENU_SOUND_GAIN_4,
	MENU_SOUND_GAIN_5,
	MENU_SOUND_GAIN_6,
	MENU_SOUND_GAIN_7,
	MENU_SOUND_GAIN_8,
	MENU_SOUND_GAIN_9,
	MENU_FILTER_ORIGINAL,
	MENU_FILTER_REDUCED,
	MENU_FILTER_MORE_REDUCED,
	MENU_SETTINGS_CONFIGURE,
	MENU_DEBUGGER_ENABLE,
	MENU_DEBUGGER_BREAK
};

@interface ArcAppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate>
- (void)handleMenuCommand:(id)sender;
@end

static ArcAppDelegate *shell_delegate = nil;
static NSWindow *shell_window = nil;
static MTKView *shell_video_view = nil;
static NSTimer *shell_timer = nil;
static NSMenu *shell_context_menu = nil;
static NSMutableDictionary<NSNumber *, NSMutableArray<NSMenuItem *> *> *shell_menu_items = nil;

static void shell_enable_mouse_capture(void);
static void shell_disable_mouse_capture(void);

static pthread_mutex_t shell_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t shell_cond = PTHREAD_COND_INITIALIZER;
static emulation_command_queue_t shell_command_queue;
static pthread_t shell_emulation_thread;
static int shell_emulation_thread_started = 0;

static int winsizex = 0;
static int winsizey = 0;
static int win_doresize = 0;
static int win_dofullscreen = 0;
static int win_renderer_reset = 0;
static volatile int quited = 0;
static volatile int pause_main_thread = 0;
static volatile int emulation_quited = 0;
static int shell_session_active = 0;
static int shell_should_quit_app = 0;
static int shell_stop_pending = 0;
static int shell_release_shortcut_down = 0;
static int shell_fullscreen_shortcut_down = 0;

// Configurable mouse-release shortcut. Loaded from CFPreferences keys
// "ArculatorReleaseShortcutKeyCode" and "ArculatorReleaseShortcutModFlags"
// (written by AppSettings.swift via UserDefaults.standard).
// shell_release_main_keycode is biased by KEYCODE_MACOS() so it can be
// passed straight to input_get_host_key_state. Defaults match the
// historical hardcoded behaviour: CMD-Backspace.
static uint32_t shell_release_modifier_mask = ARC_RELEASE_MODIFIER_COMMAND;
static int  shell_release_main_keycode  = KEYCODE_MACOS(kVK_Delete);
static char shell_release_subtitle[64]  = "CMD-BACKSPACE";
// Start at the polling threshold so the first main-loop tick triggers an
// immediate load from CFPreferences before the defaults above are used.
static int  shell_release_combo_refresh_counter = 1000;

/* Snapshot session state. Populated by arc_start_snapshot_session()
 * before the emulation thread is spawned, consumed by
 * arc_emulation_thread() when it calls arc_init_from_snapshot(). The
 * runtime dir / synthetic config name are retained so arc_shell_shutdown()
 * can clean them up after the session ends. */
static snapshot_load_ctx_t *shell_pending_snapshot_ctx = NULL;
static char shell_snapshot_runtime_dir[512];
static char shell_snapshot_runtime_name[64];
static char shell_snapshot_display_name[256];
static int  shell_snapshot_session = 0;
#ifndef NDEBUG
/* Debug-only UI-test seam: when set, Save Snapshot skips NSSavePanel
 * and writes straight to this path. */
static char shell_test_snapshot_save_path[PATH_MAX];
#endif

static uint64_t monotonic_millis(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ((uint64_t)ts.tv_sec * 1000ULL) + ((uint64_t)ts.tv_nsec / 1000000ULL);
}

static void shell_show_alert(NSString *message_text, NSString *informative_text)
{
	NSAlert *alert = [[NSAlert alloc] init];
	alert.messageText = message_text ?: @"Arculator";
	if (informative_text)
		alert.informativeText = informative_text;
	[alert addButtonWithTitle:@"OK"];
	[alert runModal];
}

static void shell_apply_snapshot_panel_defaults(NSSavePanel *panel)
{
	panel.allowedFileTypes = @[ @"arcsnap" ];

	char support_snapshots[512];
	platform_path_snapshots_dir(support_snapshots, sizeof(support_snapshots));
	NSString *default_dir = [NSString stringWithUTF8String:support_snapshots];
	if (default_dir.length)
		panel.directoryURL = [NSURL fileURLWithPath:default_dir isDirectory:YES];
}

static NSString *shell_choose_snapshot_save_path(void)
{
#ifndef NDEBUG
	if (shell_test_snapshot_save_path[0])
	{
		NSString *path = [NSString stringWithUTF8String:shell_test_snapshot_save_path];
		if (path.length)
		{
			NSString *dir = [path stringByDeletingLastPathComponent];
			if (dir.length)
			{
				[[NSFileManager defaultManager] createDirectoryAtPath:dir
				                          withIntermediateDirectories:YES
				                                           attributes:nil
				                                                error:nil];
			}
			return path;
		}
	}
#endif

	NSSavePanel *panel = [NSSavePanel savePanel];
	panel.nameFieldStringValue = @"snapshot.arcsnap";
	shell_apply_snapshot_panel_defaults(panel);

	if ([panel runModal] != NSModalResponseOK)
		return nil;

	return panel.URL.path;
}

static void shell_register_menu_item(NSInteger command_id, NSMenuItem *item)
{
	NSNumber *key = [NSNumber numberWithInteger:command_id];
	NSMutableArray<NSMenuItem *> *items = [shell_menu_items objectForKey:key];

	if (!items)
	{
		items = [NSMutableArray array];
		[shell_menu_items setObject:items forKey:key];
	}

	[items addObject:item];
}

static void shell_set_menu_state(NSInteger command_id, NSInteger state)
{
	NSArray<NSMenuItem *> *items = [shell_menu_items objectForKey:[NSNumber numberWithInteger:command_id]];

	for (NSMenuItem *item in items)
		item.state = state;
}

static void shell_set_menu_enabled(NSInteger command_id, BOOL enabled)
{
	NSArray<NSMenuItem *> *items = [shell_menu_items objectForKey:[NSNumber numberWithInteger:command_id]];

	for (NSMenuItem *item in items)
		item.enabled = enabled;
}

static NSMenuItem *shell_add_item(NSMenu *menu, NSString *title, NSInteger command_id, SEL action,
				      NSString *key_equivalent = @"", NSEventModifierFlags modifiers = 0)
{
	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key_equivalent ?: @""];
	item.target = shell_delegate;
	item.tag = command_id;
	item.keyEquivalentModifierMask = modifiers;
	[menu addItem:item];
	shell_register_menu_item(command_id, item);
	return item;
}

static NSMenuItem *shell_recent_snapshots_item = nil;
static NSMenu     *shell_recent_snapshots_menu = nil;

static void shell_rebuild_recent_snapshots_menu(void)
{
	if (!shell_recent_snapshots_menu)
		return;

	[shell_recent_snapshots_menu removeAllItems];

	NSArray<NSString *> *paths = [NewWindowBridge recentSnapshotPaths];
	if (paths.count == 0)
	{
		NSMenuItem *empty = [[NSMenuItem alloc] initWithTitle:@"No Recent Snapshots"
		                                                action:nil
		                                         keyEquivalent:@""];
		empty.enabled = NO;
		[shell_recent_snapshots_menu addItem:empty];
		if (shell_recent_snapshots_item)
			shell_recent_snapshots_item.enabled = !shell_session_active;
		return;
	}

	NSUInteger idx = 0;
	for (NSString *path in paths)
	{
		NSString *title = [path lastPathComponent];
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
		                                              action:@selector(handleMenuCommand:)
		                                       keyEquivalent:@""];
		item.target = shell_delegate;
		item.tag = MENU_FILE_LOAD_RECENT_SNAPSHOT_BASE + (NSInteger)idx;
		item.enabled = !shell_session_active;
		item.toolTip = path;
		[shell_recent_snapshots_menu addItem:item];
		idx++;
		if (idx >= MENU_FILE_LOAD_RECENT_SNAPSHOT_MAX) break;
	}

	if (shell_recent_snapshots_item)
		shell_recent_snapshots_item.enabled = !shell_session_active;
}

static NSMenu *shell_create_file_menu(void)
{
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"File"];

	shell_add_item(menu, @"Hard Reset", MENU_FILE_RESET, @selector(handleMenuCommand:));
	[menu addItem:[NSMenuItem separatorItem]];
	shell_add_item(menu, @"Save Snapshot\u2026", MENU_FILE_SAVE_SNAPSHOT, @selector(handleMenuCommand:));
	shell_add_item(menu, @"Load Snapshot\u2026", MENU_FILE_LOAD_SNAPSHOT, @selector(handleMenuCommand:));
	shell_add_item(menu, @"Copy Screenshot", MENU_FILE_TAKE_SCREENSHOT, @selector(handleMenuCommand:));

	shell_recent_snapshots_menu = [[NSMenu alloc] initWithTitle:@"Open Recent Snapshot"];
	shell_recent_snapshots_item = [[NSMenuItem alloc] initWithTitle:@"Open Recent Snapshot"
	                                                         action:nil
	                                                  keyEquivalent:@""];
	shell_recent_snapshots_item.submenu = shell_recent_snapshots_menu;
	[menu addItem:shell_recent_snapshots_item];
	shell_rebuild_recent_snapshots_menu();
	[[NSNotificationCenter defaultCenter]
	    addObserverForName:[NewWindowBridge recentSnapshotsChangedNotificationName]
	                object:nil
	                 queue:[NSOperationQueue mainQueue]
	            usingBlock:^(NSNotification *note) {
	                (void)note;
	                shell_rebuild_recent_snapshots_menu();
	            }];

	[menu addItem:[NSMenuItem separatorItem]];
	shell_add_item(menu, @"Exit", MENU_FILE_EXIT, @selector(handleMenuCommand:));
	return menu;
}

static NSMenu *shell_create_disc_menu(void)
{
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Disc"];
	NSMenu *noise_menu = [[NSMenu alloc] initWithTitle:@"Disc Drive Noise"];
	NSMenuItem *noise_item = [[NSMenuItem alloc] initWithTitle:@"Disc Drive Noise" action:nil keyEquivalent:@""];

	shell_add_item(menu, @"Change Drive 0...", MENU_DISC_CHANGE_0, @selector(handleMenuCommand:));
	shell_add_item(menu, @"Change Drive 1...", MENU_DISC_CHANGE_1, @selector(handleMenuCommand:));
	shell_add_item(menu, @"Change Drive 2...", MENU_DISC_CHANGE_2, @selector(handleMenuCommand:));
	shell_add_item(menu, @"Change Drive 3...", MENU_DISC_CHANGE_3, @selector(handleMenuCommand:));
	[menu addItem:[NSMenuItem separatorItem]];
	shell_add_item(menu, @"Eject Drive 0", MENU_DISC_EJECT_0, @selector(handleMenuCommand:));
	shell_add_item(menu, @"Eject Drive 1", MENU_DISC_EJECT_1, @selector(handleMenuCommand:));
	shell_add_item(menu, @"Eject Drive 2", MENU_DISC_EJECT_2, @selector(handleMenuCommand:));
	shell_add_item(menu, @"Eject Drive 3", MENU_DISC_EJECT_3, @selector(handleMenuCommand:));
	[menu addItem:[NSMenuItem separatorItem]];

	shell_add_item(noise_menu, @"Disabled", MENU_DISC_NOISE_0, @selector(handleMenuCommand:));
	shell_add_item(noise_menu, @"0 dB", MENU_DISC_NOISE_1, @selector(handleMenuCommand:));
	shell_add_item(noise_menu, @"-2 dB", MENU_DISC_NOISE_2, @selector(handleMenuCommand:));
	shell_add_item(noise_menu, @"-4 dB", MENU_DISC_NOISE_3, @selector(handleMenuCommand:));
	shell_add_item(noise_menu, @"-6 dB", MENU_DISC_NOISE_4, @selector(handleMenuCommand:));
	noise_item.submenu = noise_menu;
	[menu addItem:noise_item];
	return menu;
}

static NSMenu *shell_create_video_menu(void)
{
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Video"];
	NSMenu *border_menu = [[NSMenu alloc] initWithTitle:@"Border Size"];
	NSMenu *blit_menu = [[NSMenu alloc] initWithTitle:@"Blit Method"];
	NSMenu *black_menu = [[NSMenu alloc] initWithTitle:@"Black Level"];
	NSMenu *driver_menu = [[NSMenu alloc] initWithTitle:@"Render Driver"];
	NSMenu *filter_menu = [[NSMenu alloc] initWithTitle:@"Scale Filtering"];
	NSMenu *stretch_menu = [[NSMenu alloc] initWithTitle:@"Output Stretch-Mode"];
	NSMenu *scale_menu = [[NSMenu alloc] initWithTitle:@"Output Scale"];

	shell_add_item(menu, @"Fullscreen", MENU_VIDEO_FULLSCR, @selector(handleMenuCommand:), @"\r", NSEventModifierFlagCommand);

	NSMenuItem *border_item = [[NSMenuItem alloc] initWithTitle:@"Border Size" action:nil keyEquivalent:@""];
	shell_add_item(border_menu, @"No Borders", MENU_VIDEO_NO_BORDERS, @selector(handleMenuCommand:));
	shell_add_item(border_menu, @"Native Borders", MENU_VIDEO_NATIVE_BORDERS, @selector(handleMenuCommand:));
	shell_add_item(border_menu, @"Fixed Borders", MENU_VIDEO_TV, @selector(handleMenuCommand:));
	border_item.submenu = border_menu;
	[menu addItem:border_item];

	NSMenuItem *blit_item = [[NSMenuItem alloc] initWithTitle:@"Blit Method" action:nil keyEquivalent:@""];
	shell_add_item(blit_menu, @"Scanlines", MENU_BLIT_SCAN, @selector(handleMenuCommand:));
	shell_add_item(blit_menu, @"Line Doubling", MENU_BLIT_SCALE, @selector(handleMenuCommand:));
	blit_item.submenu = blit_menu;
	[menu addItem:blit_item];

	NSMenuItem *black_item = [[NSMenuItem alloc] initWithTitle:@"Black Level" action:nil keyEquivalent:@""];
	shell_add_item(black_menu, @"Acorn", MENU_BLACK_ACORN, @selector(handleMenuCommand:));
	shell_add_item(black_menu, @"Normal", MENU_BLACK_NORMAL, @selector(handleMenuCommand:));
	black_item.submenu = black_menu;
	[menu addItem:black_item];

	[menu addItem:[NSMenuItem separatorItem]];

	NSMenuItem *driver_item = [[NSMenuItem alloc] initWithTitle:@"Render Driver" action:nil keyEquivalent:@""];
	shell_add_item(driver_menu, @"Auto", MENU_DRIVER_AUTO, @selector(handleMenuCommand:));
	shell_add_item(driver_menu, @"Direct3D", MENU_DRIVER_DIRECT3D, @selector(handleMenuCommand:));
	shell_add_item(driver_menu, @"OpenGL", MENU_DRIVER_OPENGL, @selector(handleMenuCommand:));
	shell_add_item(driver_menu, @"Software", MENU_DRIVER_SOFTWARE, @selector(handleMenuCommand:));
	driver_item.submenu = driver_menu;
	[menu addItem:driver_item];

	NSMenuItem *filter_item = [[NSMenuItem alloc] initWithTitle:@"Scale Filtering" action:nil keyEquivalent:@""];
	shell_add_item(filter_menu, @"Nearest", MENU_VIDEO_SCALE_NEAREST, @selector(handleMenuCommand:));
	shell_add_item(filter_menu, @"Linear", MENU_VIDEO_SCALE_LINEAR, @selector(handleMenuCommand:));
	filter_item.submenu = filter_menu;
	[menu addItem:filter_item];

	NSMenuItem *stretch_item = [[NSMenuItem alloc] initWithTitle:@"Output Stretch-Mode" action:nil keyEquivalent:@""];
	shell_add_item(stretch_menu, @"None", MENU_VIDEO_FS_FULL, @selector(handleMenuCommand:));
	shell_add_item(stretch_menu, @"4:3", MENU_VIDEO_FS_43, @selector(handleMenuCommand:));
	shell_add_item(stretch_menu, @"Square Pixels", MENU_VIDEO_FS_SQ, @selector(handleMenuCommand:));
	shell_add_item(stretch_menu, @"Integer Scale", MENU_VIDEO_FS_INT, @selector(handleMenuCommand:));
	stretch_item.submenu = stretch_menu;
	[menu addItem:stretch_item];

	NSMenuItem *scale_item = [[NSMenuItem alloc] initWithTitle:@"Output Scale" action:nil keyEquivalent:@""];
	shell_add_item(scale_menu, @"0.5x", MENU_VIDEO_SCALE_0, @selector(handleMenuCommand:));
	shell_add_item(scale_menu, @"1x", MENU_VIDEO_SCALE_1, @selector(handleMenuCommand:));
	shell_add_item(scale_menu, @"1.5x", MENU_VIDEO_SCALE_2, @selector(handleMenuCommand:));
	shell_add_item(scale_menu, @"2x", MENU_VIDEO_SCALE_3, @selector(handleMenuCommand:));
	shell_add_item(scale_menu, @"2.5x", MENU_VIDEO_SCALE_4, @selector(handleMenuCommand:));
	shell_add_item(scale_menu, @"3x", MENU_VIDEO_SCALE_5, @selector(handleMenuCommand:));
	shell_add_item(scale_menu, @"3.5x", MENU_VIDEO_SCALE_6, @selector(handleMenuCommand:));
	shell_add_item(scale_menu, @"4x", MENU_VIDEO_SCALE_7, @selector(handleMenuCommand:));
	scale_item.submenu = scale_menu;
	[menu addItem:scale_item];

	return menu;
}

static NSMenu *shell_create_sound_menu(void)
{
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Sound"];
	NSMenu *gain_menu = [[NSMenu alloc] initWithTitle:@"Output Level"];
	NSMenu *filter_menu = [[NSMenu alloc] initWithTitle:@"Output Filter"];

	shell_add_item(menu, @"Sound Enable", MENU_SOUND_ENABLE, @selector(handleMenuCommand:));
	shell_add_item(menu, @"Stereo Sound", MENU_SOUND_STEREO, @selector(handleMenuCommand:));
	[menu addItem:[NSMenuItem separatorItem]];

	NSMenuItem *gain_item = [[NSMenuItem alloc] initWithTitle:@"Output Level" action:nil keyEquivalent:@""];
	shell_add_item(gain_menu, @"Normal", MENU_SOUND_GAIN_0, @selector(handleMenuCommand:));
	shell_add_item(gain_menu, @"+2 dB", MENU_SOUND_GAIN_1, @selector(handleMenuCommand:));
	shell_add_item(gain_menu, @"+4 dB", MENU_SOUND_GAIN_2, @selector(handleMenuCommand:));
	shell_add_item(gain_menu, @"+6 dB", MENU_SOUND_GAIN_3, @selector(handleMenuCommand:));
	shell_add_item(gain_menu, @"+8 dB", MENU_SOUND_GAIN_4, @selector(handleMenuCommand:));
	shell_add_item(gain_menu, @"+10 dB", MENU_SOUND_GAIN_5, @selector(handleMenuCommand:));
	shell_add_item(gain_menu, @"+12 dB", MENU_SOUND_GAIN_6, @selector(handleMenuCommand:));
	shell_add_item(gain_menu, @"+14 dB", MENU_SOUND_GAIN_7, @selector(handleMenuCommand:));
	shell_add_item(gain_menu, @"+16 dB", MENU_SOUND_GAIN_8, @selector(handleMenuCommand:));
	shell_add_item(gain_menu, @"+18 dB", MENU_SOUND_GAIN_9, @selector(handleMenuCommand:));
	gain_item.submenu = gain_menu;
	[menu addItem:gain_item];

	NSMenuItem *filter_item = [[NSMenuItem alloc] initWithTitle:@"Output Filter" action:nil keyEquivalent:@""];
	shell_add_item(filter_menu, @"Original", MENU_FILTER_ORIGINAL, @selector(handleMenuCommand:));
	shell_add_item(filter_menu, @"Reduced", MENU_FILTER_REDUCED, @selector(handleMenuCommand:));
	shell_add_item(filter_menu, @"More Reduced", MENU_FILTER_MORE_REDUCED, @selector(handleMenuCommand:));
	filter_item.submenu = filter_menu;
	[menu addItem:filter_item];

	return menu;
}

static NSMenu *shell_create_settings_menu(void)
{
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Settings"];

	shell_add_item(menu, @"Configure Machine...", MENU_SETTINGS_CONFIGURE, @selector(handleMenuCommand:));
	return menu;
}

static NSMenu *shell_create_debugger_menu(void)
{
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Debugger"];

	shell_add_item(menu, @"Enable Debugger", MENU_DEBUGGER_ENABLE, @selector(handleMenuCommand:));
	shell_add_item(menu, @"Break", MENU_DEBUGGER_BREAK, @selector(handleMenuCommand:));
	return menu;
}

static void shell_attach_menu(NSMenu *bar, NSString *title, NSMenu *submenu)
{
	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
	item.submenu = submenu;
	submenu.delegate = shell_delegate;
	[bar addItem:item];
}

static void shell_update_menu_state(void)
{
	shell_set_menu_state(MENU_SOUND_ENABLE, soundena ? NSControlStateValueOn : NSControlStateValueOff);
	shell_set_menu_state(MENU_SOUND_STEREO, stereo ? NSControlStateValueOn : NSControlStateValueOff);

	shell_set_menu_state(MENU_DISC_NOISE_0, disc_noise_gain == DISC_NOISE_DISABLED ? NSControlStateValueOn : NSControlStateValueOff);
	shell_set_menu_state(MENU_DISC_NOISE_1, disc_noise_gain == 0 ? NSControlStateValueOn : NSControlStateValueOff);
	shell_set_menu_state(MENU_DISC_NOISE_2, disc_noise_gain == -2 ? NSControlStateValueOn : NSControlStateValueOff);
	shell_set_menu_state(MENU_DISC_NOISE_3, disc_noise_gain == -4 ? NSControlStateValueOn : NSControlStateValueOff);
	shell_set_menu_state(MENU_DISC_NOISE_4, disc_noise_gain == -6 ? NSControlStateValueOn : NSControlStateValueOff);

	shell_set_menu_state(MENU_BLIT_SCAN, dblscan ? NSControlStateValueOff : NSControlStateValueOn);
	shell_set_menu_state(MENU_BLIT_SCALE, dblscan ? NSControlStateValueOn : NSControlStateValueOff);

	shell_set_menu_state(MENU_VIDEO_NO_BORDERS, display_mode == DISPLAY_MODE_NO_BORDERS ? NSControlStateValueOn : NSControlStateValueOff);
	shell_set_menu_state(MENU_VIDEO_NATIVE_BORDERS, display_mode == DISPLAY_MODE_NATIVE_BORDERS ? NSControlStateValueOn : NSControlStateValueOff);
	shell_set_menu_state(MENU_VIDEO_TV, display_mode == DISPLAY_MODE_TV ? NSControlStateValueOn : NSControlStateValueOff);

	shell_set_menu_state(MENU_VIDEO_FS_FULL, video_fullscreen_scale == FULLSCR_SCALE_FULL ? NSControlStateValueOn : NSControlStateValueOff);
	shell_set_menu_state(MENU_VIDEO_FS_43, video_fullscreen_scale == FULLSCR_SCALE_43 ? NSControlStateValueOn : NSControlStateValueOff);
	shell_set_menu_state(MENU_VIDEO_FS_SQ, video_fullscreen_scale == FULLSCR_SCALE_SQ ? NSControlStateValueOn : NSControlStateValueOff);
	shell_set_menu_state(MENU_VIDEO_FS_INT, video_fullscreen_scale == FULLSCR_SCALE_INT ? NSControlStateValueOn : NSControlStateValueOff);

	shell_set_menu_state(MENU_VIDEO_SCALE_NEAREST, video_linear_filtering ? NSControlStateValueOff : NSControlStateValueOn);
	shell_set_menu_state(MENU_VIDEO_SCALE_LINEAR, video_linear_filtering ? NSControlStateValueOn : NSControlStateValueOff);

	shell_set_menu_state(MENU_BLACK_ACORN, video_black_level == BLACK_LEVEL_ACORN ? NSControlStateValueOn : NSControlStateValueOff);
	shell_set_menu_state(MENU_BLACK_NORMAL, video_black_level == BLACK_LEVEL_NORMAL ? NSControlStateValueOn : NSControlStateValueOff);

	shell_set_menu_state(MENU_VIDEO_SCALE_0, video_scale == 0 ? NSControlStateValueOn : NSControlStateValueOff);
	shell_set_menu_state(MENU_VIDEO_SCALE_1, video_scale == 1 ? NSControlStateValueOn : NSControlStateValueOff);
	shell_set_menu_state(MENU_VIDEO_SCALE_2, video_scale == 2 ? NSControlStateValueOn : NSControlStateValueOff);
	shell_set_menu_state(MENU_VIDEO_SCALE_3, video_scale == 3 ? NSControlStateValueOn : NSControlStateValueOff);
	shell_set_menu_state(MENU_VIDEO_SCALE_4, video_scale == 4 ? NSControlStateValueOn : NSControlStateValueOff);
	shell_set_menu_state(MENU_VIDEO_SCALE_5, video_scale == 5 ? NSControlStateValueOn : NSControlStateValueOff);
	shell_set_menu_state(MENU_VIDEO_SCALE_6, video_scale == 6 ? NSControlStateValueOn : NSControlStateValueOff);
	shell_set_menu_state(MENU_VIDEO_SCALE_7, video_scale == 7 ? NSControlStateValueOn : NSControlStateValueOff);

	shell_set_menu_enabled(MENU_DRIVER_AUTO, video_renderer_available(RENDERER_AUTO) ? YES : NO);
	shell_set_menu_enabled(MENU_DRIVER_DIRECT3D, video_renderer_available(RENDERER_DIRECT3D) ? YES : NO);
	shell_set_menu_enabled(MENU_DRIVER_OPENGL, video_renderer_available(RENDERER_OPENGL) ? YES : NO);
	shell_set_menu_enabled(MENU_DRIVER_SOFTWARE, video_renderer_available(RENDERER_SOFTWARE) ? YES : NO);

	shell_set_menu_state(MENU_DRIVER_AUTO, selected_video_renderer == RENDERER_AUTO ? NSControlStateValueOn : NSControlStateValueOff);
	shell_set_menu_state(MENU_DRIVER_DIRECT3D, selected_video_renderer == RENDERER_DIRECT3D ? NSControlStateValueOn : NSControlStateValueOff);
	shell_set_menu_state(MENU_DRIVER_OPENGL, selected_video_renderer == RENDERER_OPENGL ? NSControlStateValueOn : NSControlStateValueOff);
	shell_set_menu_state(MENU_DRIVER_SOFTWARE, selected_video_renderer == RENDERER_SOFTWARE ? NSControlStateValueOn : NSControlStateValueOff);

	shell_set_menu_state(MENU_FILTER_ORIGINAL, sound_filter == 0 ? NSControlStateValueOn : NSControlStateValueOff);
	shell_set_menu_state(MENU_FILTER_REDUCED, sound_filter == 1 ? NSControlStateValueOn : NSControlStateValueOff);
	shell_set_menu_state(MENU_FILTER_MORE_REDUCED, sound_filter == 2 ? NSControlStateValueOn : NSControlStateValueOff);

	shell_set_menu_state(MENU_SOUND_GAIN_0, sound_gain == 0 ? NSControlStateValueOn : NSControlStateValueOff);
	shell_set_menu_state(MENU_SOUND_GAIN_1, sound_gain == 2 ? NSControlStateValueOn : NSControlStateValueOff);
	shell_set_menu_state(MENU_SOUND_GAIN_2, sound_gain == 4 ? NSControlStateValueOn : NSControlStateValueOff);
	shell_set_menu_state(MENU_SOUND_GAIN_3, sound_gain == 6 ? NSControlStateValueOn : NSControlStateValueOff);
	shell_set_menu_state(MENU_SOUND_GAIN_4, sound_gain == 8 ? NSControlStateValueOn : NSControlStateValueOff);
	shell_set_menu_state(MENU_SOUND_GAIN_5, sound_gain == 10 ? NSControlStateValueOn : NSControlStateValueOff);
	shell_set_menu_state(MENU_SOUND_GAIN_6, sound_gain == 12 ? NSControlStateValueOn : NSControlStateValueOff);
	shell_set_menu_state(MENU_SOUND_GAIN_7, sound_gain == 14 ? NSControlStateValueOn : NSControlStateValueOff);
	shell_set_menu_state(MENU_SOUND_GAIN_8, sound_gain == 16 ? NSControlStateValueOn : NSControlStateValueOff);
	shell_set_menu_state(MENU_SOUND_GAIN_9, sound_gain == 18 ? NSControlStateValueOn : NSControlStateValueOff);

	shell_set_menu_state(MENU_DEBUGGER_ENABLE, debug ? NSControlStateValueOn : NSControlStateValueOff);

	{
		BOOL can_save = (shell_session_active && arc_is_paused() && snapshot_can_save(NULL, 0));
		BOOL can_load = !shell_session_active;
		BOOL can_screenshot = shell_session_active;
		shell_set_menu_enabled(MENU_FILE_SAVE_SNAPSHOT, can_save);
		shell_set_menu_enabled(MENU_FILE_LOAD_SNAPSHOT, can_load);
		shell_set_menu_enabled(MENU_FILE_TAKE_SCREENSHOT, can_screenshot);

		/* Disabling the parent item is enough — Cocoa won't let the
		 * user open the submenu, so the per-entry items don't need
		 * to be touched here. They are enabled/disabled in
		 * shell_rebuild_recent_snapshots_menu() at build time. */
		if (shell_recent_snapshots_item)
			shell_recent_snapshots_item.enabled = can_load;
	}
}

static void shell_create_menus(void)
{
	NSString *app_name = [[NSProcessInfo processInfo] processName];
	NSMenu *menu_bar = [[NSMenu alloc] initWithTitle:@""];
	NSMenu *app_menu = [[NSMenu alloc] initWithTitle:app_name];
	NSMenuItem *app_menu_item = [[NSMenuItem alloc] initWithTitle:app_name action:nil keyEquivalent:@""];
	NSMenuItem *quit_item = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Quit %@", app_name]
						       action:@selector(terminate:)
						keyEquivalent:@"q"];

	shell_menu_items = [[NSMutableDictionary alloc] init];

	quit_item.keyEquivalentModifierMask = NSEventModifierFlagCommand;
	[app_menu addItem:quit_item];
	app_menu.delegate = shell_delegate;
	app_menu_item.submenu = app_menu;
	[menu_bar addItem:app_menu_item];

	shell_attach_menu(menu_bar, @"File", shell_create_file_menu());
	shell_attach_menu(menu_bar, @"Disc", shell_create_disc_menu());
	shell_attach_menu(menu_bar, @"Video", shell_create_video_menu());
	shell_attach_menu(menu_bar, @"Sound", shell_create_sound_menu());
	shell_attach_menu(menu_bar, @"Settings", shell_create_settings_menu());
	shell_attach_menu(menu_bar, @"Debugger", shell_create_debugger_menu());

	[NSApp setMainMenu:menu_bar];

	shell_context_menu = [[NSMenu alloc] initWithTitle:@"Context"];
	shell_context_menu.delegate = shell_delegate;
	shell_attach_menu(shell_context_menu, @"File", shell_create_file_menu());
	shell_attach_menu(shell_context_menu, @"Disc", shell_create_disc_menu());
	shell_attach_menu(shell_context_menu, @"Video", shell_create_video_menu());
	shell_attach_menu(shell_context_menu, @"Sound", shell_create_sound_menu());
	shell_attach_menu(shell_context_menu, @"Settings", shell_create_settings_menu());
	shell_attach_menu(shell_context_menu, @"Debugger", shell_create_debugger_menu());

	shell_update_menu_state();
}

static void shell_create_window(void);

static void shell_prepare_ui(void)
{
	if (!shell_window)
		shell_create_window();
	if (!shell_menu_items)
		shell_create_menus();
}

// Build a plain-ASCII display string for the configured release combo
// (e.g. "CMD-BACKSPACE", "CTRL-CMD-R", "F12"). Used in the window subtitle.
static void shell_format_release_subtitle(char *dest, size_t size, NSEventModifierFlags flags, int biased_keycode)
{
	const char *parts[6];
	int n = 0;

	if (flags & NSEventModifierFlagControl) parts[n++] = "CTRL";
	if (flags & NSEventModifierFlagOption)  parts[n++] = "OPT";
	if (flags & NSEventModifierFlagShift)   parts[n++] = "SHIFT";
	if (flags & NSEventModifierFlagCommand) parts[n++] = "CMD";

	int raw = KEYCODE_MACOS_TO_RAW(biased_keycode);
	const char *key_name = NULL;
	char key_buf[16];
	switch (raw)
	{
	case kVK_Delete:        key_name = "BACKSPACE"; break;
	case kVK_ForwardDelete: key_name = "DELETE";    break;
	case kVK_Return:        key_name = "RETURN";    break;
	case kVK_Escape:        key_name = "ESC";       break;
	case kVK_Tab:           key_name = "TAB";       break;
	case kVK_Space:         key_name = "SPACE";     break;
	case kVK_LeftArrow:     key_name = "LEFT";      break;
	case kVK_RightArrow:    key_name = "RIGHT";     break;
	case kVK_UpArrow:       key_name = "UP";        break;
	case kVK_DownArrow:     key_name = "DOWN";      break;
	case kVK_F1:  key_name = "F1";  break;
	case kVK_F2:  key_name = "F2";  break;
	case kVK_F3:  key_name = "F3";  break;
	case kVK_F4:  key_name = "F4";  break;
	case kVK_F5:  key_name = "F5";  break;
	case kVK_F6:  key_name = "F6";  break;
	case kVK_F7:  key_name = "F7";  break;
	case kVK_F8:  key_name = "F8";  break;
	case kVK_F9:  key_name = "F9";  break;
	case kVK_F10: key_name = "F10"; break;
	case kVK_F11: key_name = "F11"; break;
	case kVK_F12: key_name = "F12"; break;
	default:
		snprintf(key_buf, sizeof(key_buf), "KEY%d", raw);
		key_name = key_buf;
		break;
	}
	parts[n++] = key_name;

	dest[0] = 0;
	for (int i = 0; i < n; i++)
	{
		if (i > 0)
			strlcat(dest, "-", size);
		strlcat(dest, parts[i], size);
	}
}

// Read configured mouse-release combo from CFPreferences. Called from the
// main-loop polling path so changes from the Settings UI propagate without
// requiring a restart. Falls back to CMD-BACKSPACE if preferences are
// absent or malformed.
static void shell_load_release_combo(void)
{
	NSEventModifierFlags new_flags = NSEventModifierFlagCommand;
	int new_keycode = kVK_Delete;
	CFTypeRef value;

	value = CFPreferencesCopyAppValue(
		CFSTR("ArculatorReleaseShortcutKeyCode"),
		kCFPreferencesCurrentApplication);
	if (value && CFGetTypeID(value) == CFNumberGetTypeID())
		CFNumberGetValue((CFNumberRef)value, kCFNumberIntType, &new_keycode);
	if (value)
		CFRelease(value);

	value = CFPreferencesCopyAppValue(
		CFSTR("ArculatorReleaseShortcutModFlags"),
		kCFPreferencesCurrentApplication);
	if (value && CFGetTypeID(value) == CFNumberGetTypeID())
	{
		long long raw_flags = 0;
		CFNumberGetValue((CFNumberRef)value, kCFNumberLongLongType, &raw_flags);
		new_flags = (NSEventModifierFlags)raw_flags;
	}
	if (value)
		CFRelease(value);

	int new_biased = KEYCODE_MACOS(new_keycode);
	uint32_t new_mask = arc_release_shortcut_modifier_mask_from_flags((uint64_t)new_flags);
	if (new_mask != shell_release_modifier_mask
	 || new_biased != shell_release_main_keycode)
	{
		shell_release_modifier_mask  = new_mask;
		shell_release_main_keycode   = new_biased;
		shell_format_release_subtitle(shell_release_subtitle, sizeof(shell_release_subtitle),
		                              new_flags, new_biased);
		updatemips = 1; // refresh window subtitle
	}
}

// Returns non-zero if every modifier required by `mask` is currently held.
static int shell_release_modifier_held(uint32_t mask)
{
	if ((mask & ARC_RELEASE_MODIFIER_COMMAND) && !(input_get_host_key_state(KEY_LWIN) || input_get_host_key_state(KEY_RWIN)))
		return 0;
	if ((mask & ARC_RELEASE_MODIFIER_CONTROL) && !(input_get_host_key_state(KEY_LCONTROL) || input_get_host_key_state(KEY_RCONTROL)))
		return 0;
	if ((mask & ARC_RELEASE_MODIFIER_OPTION) && !(input_get_host_key_state(KEY_ALT) || input_get_host_key_state(KEY_ALTGR)))
		return 0;
	if ((mask & ARC_RELEASE_MODIFIER_SHIFT) && !(input_get_host_key_state(KEY_LSHIFT) || input_get_host_key_state(KEY_RSHIFT)))
		return 0;
	return 1;
}

static void shell_begin_release_shortcut_suppression(void)
{
	int suppressed_keys[9];
	const int max_keys = (int)(sizeof(suppressed_keys) / sizeof(suppressed_keys[0]));
	int suppressed_count = arc_release_shortcut_fill_suppressed_keys(
		shell_release_modifier_mask,
		shell_release_main_keycode,
		suppressed_keys,
		max_keys);

	if (suppressed_count > max_keys)
		suppressed_count = max_keys;

	input_begin_host_key_suppression(suppressed_keys, suppressed_count);
}

static void shell_trigger_release_shortcut(void)
{
	if (!mousecapture && !fullscreen)
		return;

	shell_release_shortcut_down = 1;
	shell_begin_release_shortcut_suppression();

	if (mousecapture)
		shell_disable_mouse_capture();

	if (fullscreen)
		[shell_window toggleFullScreen:nil];
}

static uint32_t shell_modifier_mask_for_event(NSEvent *event)
{
	NSEventModifierFlags flags = [event modifierFlags] & NSEventModifierFlagDeviceIndependentFlagsMask;
	return arc_release_shortcut_modifier_mask_from_flags((uint64_t)flags);
}

static int shell_event_matches_release_shortcut(NSEvent *event)
{
	if (!event || event.type != NSEventTypeKeyDown)
		return 0;
	if (!mousecapture && !fullscreen)
		return 0;

	return arc_release_shortcut_matches(
		shell_modifier_mask_for_event(event),
		KEYCODE_MACOS((int)event.keyCode),
		shell_release_modifier_mask,
		shell_release_main_keycode);
}

static int shell_should_consume_suppressed_key_event(NSEvent *event)
{
	if (!event)
		return 0;

	switch (event.type)
	{
	case NSEventTypeKeyDown:
	case NSEventTypeKeyUp:
	case NSEventTypeFlagsChanged:
		return input_is_host_key_suppressed(KEYCODE_MACOS((int)event.keyCode));
	default:
		return 0;
	}
}

static void shell_set_window_title(void)
{
	if (!shell_window || fullscreen)
		return;

	const char *display_name = arc_snapshot_session_display_name();
	if (!display_name || !display_name[0])
		display_name = machine_config_name;

	char release_hint[96];
	snprintf(release_hint, sizeof(release_hint),
	         "Press %s to release mouse", shell_release_subtitle);

	char subtitle[200];
	snprintf(subtitle, sizeof(subtitle), "%s - %i%% - %s", display_name, inssec,
		 mousecapture ? release_hint : "Click to capture mouse");
	[shell_window setSubtitle:[NSString stringWithUTF8String:subtitle]];
}

static void shell_enable_mouse_capture(void)
{
	mouse_capture_enable();
	mousecapture = 1;
	updatemips = 1;
}

static void shell_disable_mouse_capture(void)
{
	mouse_capture_disable();
	mousecapture = 0;
	updatemips = 1;
}

static int shell_config_exists(const char *config_name)
{
	char path[512];
	struct stat st;

	platform_path_machine_config(path, sizeof(path), config_name);
	return !stat(path, &st);
}

static void shell_request_app_termination(void);

static int emulation_queue_command(const emulation_command_t *command)
{
	int pushed = 0;

	pthread_mutex_lock(&shell_mutex);
	pushed = emulation_command_queue_push(&shell_command_queue, command);
	if (pushed)
		pthread_cond_signal(&shell_cond);
	pthread_mutex_unlock(&shell_mutex);
	return pushed;
}

static int emulation_dequeue_command(emulation_command_t *command)
{
	int has_command = 0;

	pthread_mutex_lock(&shell_mutex);
	has_command = emulation_command_queue_pop(&shell_command_queue, command);
	pthread_mutex_unlock(&shell_mutex);
	return has_command;
}

static void emulation_execute_command(emulation_command_t *command)
{
	switch (command->type)
	{
		case EMU_COMMAND_RESET:
		debugger_start_reset();
		arc_reset();
		debugger_end_reset();
		break;

		case EMU_COMMAND_DISC_CHANGE:
		rpclog("arc_disc_change: drive=%i fn=%s\n", command->drive, command->path);
		disc_close(command->drive);
		strcpy(discname[command->drive], command->path);
		disc_load(command->drive, discname[command->drive]);
		ioc_discchange(command->drive);
		break;

		case EMU_COMMAND_DISC_EJECT:
		rpclog("arc_disc_eject: drive=%i\n", command->drive);
		ioc_discchange(command->drive);
		disc_close(command->drive);
		discname[command->drive][0] = 0;
		break;

		case EMU_COMMAND_SET_DISPLAY_MODE:
		display_mode = command->value;
		clearbitmap();
		setredrawall();
		break;

		case EMU_COMMAND_SET_DBLSCAN:
		dblscan = command->value;
		clearbitmap();
		break;

		case EMU_COMMAND_SAVE_SNAPSHOT:
		{
			char err[256];
			err[0] = 0;
			rpclog("arc_save_snapshot: path=%s\n", command->path);
			if (!snapshot_save(command->path,
			                   command->preview_png,
			                   command->preview_png_size,
			                   command->preview_width,
			                   command->preview_height,
			                   (const arcsnap_meta_t *)command->meta,
			                   err, sizeof(err)))
			{
				arc_print_error("Failed to save snapshot: %s",
						err[0] ? err : "unknown error");
			}
			else
			{
				/* A successfully written snapshot should be loadable from
				 * recents without requiring a separate open first. */
				NSString *saved_path = [NSString stringWithUTF8String:command->path];
				if (saved_path.length)
				{
					dispatch_async(dispatch_get_main_queue(), ^{
						[NewWindowBridge recordRecentSnapshot:saved_path];
					});
				}
			}
			/* Always release the buffers the UI handed us, whether
			 * the save succeeded or not. */
			free(command->preview_png);
			free(command->meta);
			command->preview_png = NULL;
			command->meta = NULL;
		}
		break;
	}
}

static void *arc_emulation_thread(void *context)
{
	int initialized = 0;
	int init_rc = 0;
	struct timeval tp;
	time_t last_seconds = 0;
	uint64_t last_timer_ticks = 0;
	int timer_offset = 0;
	snapshot_load_ctx_t *snapshot_ctx = NULL;
	char snapshot_err[256] = {0};

	(void)context;
	rpclog("Arculator startup\n");

	pthread_mutex_lock(&shell_mutex);
	snapshot_ctx = shell_pending_snapshot_ctx;
	shell_pending_snapshot_ctx = NULL;
	pthread_mutex_unlock(&shell_mutex);

	if (snapshot_ctx)
		init_rc = arc_init_from_snapshot(snapshot_ctx,
		                                 snapshot_err, sizeof(snapshot_err));
	else
		init_rc = arc_init();

	if (init_rc)
	{
		if (snapshot_ctx)
			arc_print_error("Failed to restore snapshot.\n%s",
			                snapshot_err[0] ? snapshot_err
			                               : "The session could not be started.");
		else
			arc_print_error("Configured ROM set is not available.\nConfiguration could not be run.");
		arc_stop_emulation();

		pthread_mutex_lock(&shell_mutex);
		emulation_quited = 1;
		pthread_cond_broadcast(&shell_cond);
		pthread_mutex_unlock(&shell_mutex);
		return NULL;
	}
	initialized = 1;

	while (!emulation_quited)
	{
		emulation_command_t command;

		if (gettimeofday(&tp, NULL) == -1)
			fatal("gettimeofday failed\n");
		else if (!last_seconds)
		{
			last_seconds = tp.tv_sec;
			rpclog("start time = %d\n", (int)last_seconds);
		}
		else if (last_seconds != tp.tv_sec)
		{
			updateins();
			last_seconds = tp.tv_sec;
		}

		while (emulation_dequeue_command(&command))
			emulation_execute_command(&command);

		pthread_mutex_lock(&shell_mutex);
		while (pause_main_thread && !emulation_quited && emulation_command_queue_is_empty(&shell_command_queue))
			pthread_cond_wait(&shell_cond, &shell_mutex);
		pthread_mutex_unlock(&shell_mutex);

		if (emulation_quited)
			break;

		arc_run();

		uint64_t current_timer_ticks = monotonic_millis();
		uint64_t ticks_since_last = last_timer_ticks ? (current_timer_ticks - last_timer_ticks) : 10;
		last_timer_ticks = current_timer_ticks;
		timer_offset += 10 - (int)ticks_since_last;
		if (timer_offset > 100 || timer_offset < -100)
			timer_offset = 0;
		else if (timer_offset > 0)
			usleep((useconds_t)timer_offset * 1000);
	}

	rpclog("SHUTTING DOWN\n");
	if (initialized)
		arc_close();

	pthread_mutex_lock(&shell_mutex);
	emulation_quited = 1;
	pthread_cond_broadcast(&shell_cond);
	pthread_mutex_unlock(&shell_mutex);
	return NULL;
}

static int arc_shell_init(void)
{
	if (!video_renderer_init((__bridge void *)shell_video_view))
		return 0;

	input_init();
	arc_update_menu();

	if (pthread_create(&shell_emulation_thread, NULL, arc_emulation_thread, NULL))
		return 0;

	shell_emulation_thread_started = 1;
	return 1;
}

static void shell_snapshot_session_cleanup(void)
{
	if (!shell_snapshot_session)
		return;

	/* Delete the per-snapshot CMOS file (written by cmos_save() under
	 * the synthetic config name). Best-effort — any error here is
	 * cosmetic. */
	if (shell_snapshot_runtime_name[0])
	{
		char pattern[PATH_MAX];
		DIR *dir;
		char cmos_dir[PATH_MAX];

		platform_path_join_support(cmos_dir, "cmos", sizeof(cmos_dir));
		dir = opendir(cmos_dir);
		if (dir)
		{
			struct dirent *entry;
			size_t prefix_len = strlen(shell_snapshot_runtime_name);

			while ((entry = readdir(dir)) != NULL)
			{
				if (!strncmp(entry->d_name, shell_snapshot_runtime_name, prefix_len))
				{
					snprintf(pattern, sizeof(pattern),
					         "%s/%s", cmos_dir, entry->d_name);
					if (remove(pattern) != 0)
						rpclog("snapshot cleanup: failed to remove %s: %s\n",
						       pattern, strerror(errno));
				}
			}
			closedir(dir);
		}
	}

	/* Remove the per-snapshot runtime directory contents. Best-effort. */
	if (shell_snapshot_runtime_dir[0])
	{
		DIR *dir = opendir(shell_snapshot_runtime_dir);
		if (dir)
		{
			struct dirent *entry;
			char path[PATH_MAX];

			while ((entry = readdir(dir)) != NULL)
			{
				if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, ".."))
					continue;
				snprintf(path, sizeof(path), "%s/%s",
				         shell_snapshot_runtime_dir, entry->d_name);
				if (remove(path) != 0)
					rpclog("snapshot cleanup: failed to remove %s: %s\n",
					       path, strerror(errno));
			}
			closedir(dir);
			if (rmdir(shell_snapshot_runtime_dir) != 0)
				rpclog("snapshot cleanup: failed to rmdir %s: %s\n",
				       shell_snapshot_runtime_dir, strerror(errno));
		}
	}

	shell_snapshot_runtime_dir[0] = 0;
	shell_snapshot_runtime_name[0] = 0;
	shell_snapshot_display_name[0] = 0;
	shell_snapshot_session = 0;
}

static void arc_shell_shutdown(void)
{
	/*Tell the renderer to bail out of present/update immediately so
	  the emulation thread won't block on [CAMetalLayer nextDrawable]
	  while we hold the main thread waiting for it to exit.*/
	video_renderer_begin_close();

	pthread_mutex_lock(&shell_mutex);
	emulation_quited = 1;
	pthread_cond_broadcast(&shell_cond);
	pthread_mutex_unlock(&shell_mutex);

	if (shell_emulation_thread_started)
	{
		pthread_join(shell_emulation_thread, NULL);
		shell_emulation_thread_started = 0;
	}

	input_close();
	video_renderer_close();
	shell_video_view = nil;
	shell_session_active = 0;

	shell_snapshot_session_cleanup();
}

static void shell_prompt_restart_or_quit(void)
{
	CloseConsoleWindow();
	arc_stop_main_thread();
	debug_end();

	if (shell_should_quit_app)
	{
		shell_stop_pending = 0;
		[NSApp terminate:nil];
		return;
	}

	// Return to idle state. arc_shell_shutdown() already cleaned up
	// shell_video_view; ContentHostingController's Combine subscription
	// handles Metal view removal automatically.
	shell_stop_pending = 0;
}

static void shell_schedule_stop_handling(void)
{
	dispatch_async(dispatch_get_main_queue(), ^{
		if (shell_stop_pending)
			return;
		shell_stop_pending = 1;
		shell_prompt_restart_or_quit();
	});
}

static void shell_request_app_termination(void)
{
	shell_should_quit_app = 1;
	if (shell_session_active)
		shell_schedule_stop_handling();
	else
		[NSApp terminate:nil];
}

#import "ArcMetalView.h"

@implementation ArcMetalView

- (BOOL)acceptsFirstResponder
{
	return YES;
}

- (BOOL)canBecomeKeyView
{
	return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
	(void)event;
	return YES;
}

- (void)mouseUp:(NSEvent *)event
{
	[super mouseUp:event];

	if (event.buttonNumber == 0 && !mousecapture)
	{
		[[self window] makeFirstResponder:self];
		shell_enable_mouse_capture();
	}
}

- (void)keyDown:(NSEvent *)event
{
	if (shell_event_matches_release_shortcut(event))
	{
		if (!shell_release_shortcut_down)
			shell_trigger_release_shortcut();
		return;
	}

	if (shell_should_consume_suppressed_key_event(event))
		return;

	if (!shell_session_active)
		[super keyDown:event];
}

- (BOOL)performKeyEquivalent:(NSEvent *)event
{
	if (shell_event_matches_release_shortcut(event))
	{
		if (!shell_release_shortcut_down)
			shell_trigger_release_shortcut();
		return YES;
	}

	return [super performKeyEquivalent:event];
}

- (void)keyUp:(NSEvent *)event
{
	if (shell_should_consume_suppressed_key_event(event))
		return;

	if (!shell_session_active)
		[super keyUp:event];
}

- (void)flagsChanged:(NSEvent *)event
{
	if (shell_should_consume_suppressed_key_event(event))
		return;

	if (!shell_session_active)
		[super flagsChanged:event];
}

- (NSMenu *)menuForEvent:(NSEvent *)event
{
	(void)event;

	if (mousecapture)
		return nil;

	shell_update_menu_state();
	return shell_context_menu;
}

@end

@implementation ArcAppDelegate

- (void)handleRecentSnapshotCommand:(NSInteger)command_id
{
	NSInteger index = command_id - MENU_FILE_LOAD_RECENT_SNAPSHOT_BASE;
	if (index < 0)
		return;

	NSArray<NSString *> *paths = [NewWindowBridge recentSnapshotPaths];
	if ((NSUInteger)index >= paths.count)
		return;

	NSString *path = paths[index];
	if (!path.length)
		return;

	if (shell_session_active)
		return;

	if (![[NSFileManager defaultManager] fileExistsAtPath:path])
	{
		[NewWindowBridge removeRecentSnapshot:path];
		shell_show_alert(@"Snapshot Not Found",
		                 [NSString stringWithFormat:@"The snapshot file '%@' no longer exists and has been removed from the Recent list.", [path lastPathComponent]]);
		return;
	}

	NSString *start_error = nil;
	if (![EmulatorBridge startSnapshotSessionFromPath:path error:&start_error])
	{
		shell_show_alert(@"Cannot Load Snapshot",
		                 start_error ?: @"Failed to start snapshot session.");
		return;
	}

	/* Move the entry to the top of the recents on successful open. */
	[NewWindowBridge recordRecentSnapshot:path];
}

- (void)handleMenuCommand:(id)sender
{
	NSInteger command_id = [sender tag];

	if (command_id >= MENU_FILE_LOAD_RECENT_SNAPSHOT_BASE &&
	    command_id <  MENU_FILE_LOAD_RECENT_SNAPSHOT_BASE + MENU_FILE_LOAD_RECENT_SNAPSHOT_MAX)
	{
		[self handleRecentSnapshotCommand:command_id];
		return;
	}

	switch (command_id)
	{
		case MENU_FILE_EXIT:
		shell_request_app_termination();
		break;

		case MENU_FILE_RESET:
		arc_do_reset();
		break;

		case MENU_FILE_SAVE_SNAPSHOT:
		{
			NSString *save_error = nil;
			if (![EmulatorBridge canSaveSnapshotWithError:&save_error])
			{
				shell_show_alert(@"Cannot Save Snapshot",
						 save_error ?: @"Snapshots require a paused floppy-only session.");
				break;
			}

			NSString *path = shell_choose_snapshot_save_path();
			if (!path.length)
				break;

			NSString *queue_error = nil;
			if (![EmulatorBridge saveSnapshotToPath:path error:&queue_error])
			{
				shell_show_alert(@"Cannot Save Snapshot",
						 queue_error ?: @"Failed to queue snapshot save.");
			}
		}
		break;

		case MENU_FILE_LOAD_SNAPSHOT:
		{
			if (shell_session_active)
				break;
			/* Browser handles the file selection + load; alert
			 * handling for failed loads happens inside the
			 * MainSplitViewController selection callback. */
			[NewWindowBridge navigateToSnapshotBrowserInWindow:shell_window];
		}
		break;

		case MENU_FILE_TAKE_SCREENSHOT:
		{
			if (!shell_session_active)
				break;

			NSString *error = [EmulatorBridge copyScreenshotToPasteboard];
			if (error)
			{
				shell_show_alert(@"Cannot Copy Screenshot",
						 error ?: @"Failed to copy emulator screenshot.");
			}
		}
		break;

		case MENU_DISC_CHANGE_0:
		case MENU_DISC_CHANGE_1:
		case MENU_DISC_CHANGE_2:
		case MENU_DISC_CHANGE_3:
		{
			int drive = (int)(command_id - MENU_DISC_CHANGE_0);
			NSArray<NSString *> *allowed_extensions = @[ @"adf", @"img", @"fdi", @"apd", @"hfe", @"scp", @"ssd", @"dsd" ];
			NSOpenPanel *panel = [NSOpenPanel openPanel];
			panel.canChooseDirectories = NO;
			panel.canChooseFiles = YES;
			panel.allowsMultipleSelection = NO;
			panel.allowedFileTypes = allowed_extensions;
			if ([panel runModal] == NSModalResponseOK)
			{
				NSString *path = panel.URL.path;
				if (path)
					[EmulatorBridge changeDisc:drive path:path];
			}
		}
		break;

		case MENU_DISC_EJECT_0:
		case MENU_DISC_EJECT_1:
		case MENU_DISC_EJECT_2:
		case MENU_DISC_EJECT_3:
		[EmulatorBridge ejectDisc:(int)(command_id - MENU_DISC_EJECT_0)];
		break;

		case MENU_DISC_NOISE_0: disc_noise_gain = DISC_NOISE_DISABLED; break;
		case MENU_DISC_NOISE_1: disc_noise_gain = 0; break;
		case MENU_DISC_NOISE_2: disc_noise_gain = -2; break;
		case MENU_DISC_NOISE_3: disc_noise_gain = -4; break;
		case MENU_DISC_NOISE_4: disc_noise_gain = -6; break;

		case MENU_SOUND_ENABLE: soundena ^= 1; break;
		case MENU_SOUND_STEREO: stereo ^= 1; break;
		case MENU_SOUND_GAIN_0: sound_gain = 0; break;
		case MENU_SOUND_GAIN_1: sound_gain = 2; break;
		case MENU_SOUND_GAIN_2: sound_gain = 4; break;
		case MENU_SOUND_GAIN_3: sound_gain = 6; break;
		case MENU_SOUND_GAIN_4: sound_gain = 8; break;
		case MENU_SOUND_GAIN_5: sound_gain = 10; break;
		case MENU_SOUND_GAIN_6: sound_gain = 12; break;
		case MENU_SOUND_GAIN_7: sound_gain = 14; break;
		case MENU_SOUND_GAIN_8: sound_gain = 16; break;
		case MENU_SOUND_GAIN_9: sound_gain = 18; break;

		case MENU_FILTER_ORIGINAL:
		sound_filter = 0;
		sound_update_filter();
		break;

		case MENU_FILTER_REDUCED:
		sound_filter = 1;
		sound_update_filter();
		break;

		case MENU_FILTER_MORE_REDUCED:
		sound_filter = 2;
		sound_update_filter();
		break;

		case MENU_SETTINGS_CONFIGURE:
		if (!indebug)
		{
			if (shell_session_active)
				[NewWindowBridge navigateToConfigEditorInWindow:shell_window];
			// else: sidebar + config editor already visible, no action needed
		}
		break;

		case MENU_VIDEO_FULLSCR:
		if (!indebug)
		{
			if (firstfull)
			{
				firstfull = 0;
				arc_pause_main_thread();
				shell_show_alert(@"Arculator", @"Use CMD + BACKSPACE to return to windowed mode");
				arc_resume_main_thread();
			}
			arc_enter_fullscreen();
		}
		break;

		case MENU_VIDEO_NO_BORDERS: arc_set_display_mode(DISPLAY_MODE_NO_BORDERS); break;
		case MENU_VIDEO_NATIVE_BORDERS: arc_set_display_mode(DISPLAY_MODE_NATIVE_BORDERS); break;
		case MENU_VIDEO_TV: arc_set_display_mode(DISPLAY_MODE_TV); break;

		case MENU_DRIVER_AUTO: selected_video_renderer = RENDERER_AUTO; arc_renderer_reset(); break;
		case MENU_DRIVER_DIRECT3D: selected_video_renderer = RENDERER_DIRECT3D; arc_renderer_reset(); break;
		case MENU_DRIVER_OPENGL: selected_video_renderer = RENDERER_OPENGL; arc_renderer_reset(); break;
		case MENU_DRIVER_SOFTWARE: selected_video_renderer = RENDERER_SOFTWARE; arc_renderer_reset(); break;

		case MENU_VIDEO_SCALE_NEAREST: video_linear_filtering = 0; arc_renderer_reset(); break;
		case MENU_VIDEO_SCALE_LINEAR: video_linear_filtering = 1; arc_renderer_reset(); break;

		case MENU_VIDEO_SCALE_0: video_scale = 0; break;
		case MENU_VIDEO_SCALE_1: video_scale = 1; break;
		case MENU_VIDEO_SCALE_2: video_scale = 2; break;
		case MENU_VIDEO_SCALE_3: video_scale = 3; break;
		case MENU_VIDEO_SCALE_4: video_scale = 4; break;
		case MENU_VIDEO_SCALE_5: video_scale = 5; break;
		case MENU_VIDEO_SCALE_6: video_scale = 6; break;
		case MENU_VIDEO_SCALE_7: video_scale = 7; break;

		case MENU_VIDEO_FS_FULL: video_fullscreen_scale = FULLSCR_SCALE_FULL; break;
		case MENU_VIDEO_FS_43: video_fullscreen_scale = FULLSCR_SCALE_43; break;
		case MENU_VIDEO_FS_SQ: video_fullscreen_scale = FULLSCR_SCALE_SQ; break;
		case MENU_VIDEO_FS_INT: video_fullscreen_scale = FULLSCR_SCALE_INT; break;

		case MENU_BLIT_SCAN: arc_set_dblscan(0); break;
		case MENU_BLIT_SCALE: arc_set_dblscan(1); break;

		case MENU_BLACK_ACORN:
		video_black_level = BLACK_LEVEL_ACORN;
		vidc_redopalette();
		break;

		case MENU_BLACK_NORMAL:
		video_black_level = BLACK_LEVEL_NORMAL;
		vidc_redopalette();
		break;

		case MENU_DEBUGGER_ENABLE:
		if (!debugon)
		{
			arc_pause_main_thread();
			debugon = 1;
			debug = 1;
			debug_start();
			ShowConsoleWindow(NULL);
			arc_resume_main_thread();
		}
		else
		{
			debug = 0;
			CloseConsoleWindow();
			debug_end();
		}
		break;

		case MENU_DEBUGGER_BREAK:
		debug = 1;
		break;
	}

	shell_update_menu_state();
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
	(void)notification;
	shell_prepare_ui();

	if (rom_establish_availability())
	{
		shell_show_alert(@"Arculator", @"No ROMs available.\nArculator needs at least one ROM set present to run.");
		[NSApp terminate:nil];
		return;
	}

	[NSApp activateIgnoringOtherApps:YES];
	[shell_window makeKeyAndOrderFront:nil];
	[shell_window orderFrontRegardless];
	[shell_window displayIfNeeded];

	// Start in idle state. If a config was specified on the command line,
	// preselect it in the sidebar and auto-start emulation.
	if (strlen(machine_config_name) != 0)
	{
		NSString *configName = [NSString stringWithUTF8String:machine_config_name];
		dispatch_async(dispatch_get_main_queue(), ^{
			[NewWindowBridge preselectAndRunConfig:configName inWindow:shell_window];
		});
	}
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag
{
	(void)sender;
	if (!flag && shell_window)
	{
		[shell_window makeKeyAndOrderFront:nil];
		[NSApp activateIgnoringOtherApps:YES];
	}
	return YES;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
	(void)sender;
	if (!shell_session_active)
		return NSTerminateNow;

	shell_request_app_termination();
	return NSTerminateCancel;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
	(void)sender;
	return YES;
}

- (void)windowDidResignKey:(NSNotification *)notification
{
	(void)notification;
	if (mousecapture)
		shell_disable_mouse_capture();
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification
{
	(void)notification;
	fullscreen = 1;
	updatemips = 1;
	[NewWindowBridge enterFullscreenForWindow:shell_window];
}

- (void)windowDidExitFullScreen:(NSNotification *)notification
{
	(void)notification;
	[NewWindowBridge exitFullscreenForWindow:shell_window];
	fullscreen = 0;
	if (mousecapture)
		shell_disable_mouse_capture();
	if (fullborders)
		updatewindowsize(800, 600);
	else
		updatewindowsize(672, 544);
	updatemips = 1;
}

- (void)menuNeedsUpdate:(NSMenu *)menu
{
	(void)menu;
	shell_update_menu_state();
}

@end

static void shell_create_window(void)
{
	shell_window = [NewWindowBridge createMainWindowWithDelegate:shell_delegate];
	// shell_video_view stays nil until emulation starts (installed by ContentHostingController)
}

static void shell_apply_pending_resize(void)
{
	// Metal view auto-fills the content area via autoresizingMask.
	// video_renderer_update_layout() reads actual view bounds each frame.
	// Just consume the pending flag.
	if (!win_doresize)
		return;
	pthread_mutex_lock(&shell_mutex);
	win_doresize = 0;
	pthread_mutex_unlock(&shell_mutex);
}

static void shell_apply_pending_fullscreen(void)
{
	int should_toggle = 0;

	if (!win_dofullscreen)
		return;

	pthread_mutex_lock(&shell_mutex);
	if (win_dofullscreen)
	{
		win_dofullscreen = 0;
		should_toggle = 1;
	}
	pthread_mutex_unlock(&shell_mutex);

	if (!should_toggle || fullscreen)
		return;

	[shell_window toggleFullScreen:nil];
	shell_enable_mouse_capture();
}

static void shell_apply_pending_renderer_reset(void)
{
	int needs_reset = 0;

	if (!win_renderer_reset)
		return;

	pthread_mutex_lock(&shell_mutex);
	if (win_renderer_reset)
	{
		win_renderer_reset = 0;
		needs_reset = 1;
	}
	pthread_mutex_unlock(&shell_mutex);

	if (needs_reset && !video_renderer_reinit((__bridge void *)shell_video_view))
		fatal("Video renderer init failed");
}

static void shell_handle_shortcuts(void)
{
	// Periodically pick up settings changes from the Settings UI without
	// requiring a relaunch. ~once per second at the 1ms shell timer. The
	// counter is seeded at the threshold so the first tick does an
	// immediate load in place of a separate startup call.
	if (++shell_release_combo_refresh_counter >= 1000)
	{
		shell_release_combo_refresh_counter = 0;
		shell_load_release_combo();
	}

	int command_down = input_get_host_key_state(KEY_LWIN) || input_get_host_key_state(KEY_RWIN);
	int release_down = shell_release_modifier_held(shell_release_modifier_mask)
	                && input_get_host_key_state(shell_release_main_keycode);
	int fullscreen_down = command_down && input_get_host_key_state(KEY_ENTER);

	if (!release_down)
		shell_release_shortcut_down = 0;
	if (!fullscreen_down)
		shell_fullscreen_shortcut_down = 0;

	if (release_down && !shell_release_shortcut_down)
		shell_trigger_release_shortcut();

	if (fullscreen_down && !shell_fullscreen_shortcut_down)
	{
		shell_fullscreen_shortcut_down = 1;
		if (!fullscreen)
		{
			[shell_window toggleFullScreen:nil];
			shell_enable_mouse_capture();
		}
		else
		{
			[shell_window toggleFullScreen:nil];
			shell_disable_mouse_capture();
		}
	}
}

void updatewindowsize(int x, int y)
{
	pthread_mutex_lock(&shell_mutex);
	winsizex = (x * (video_scale + 1)) / 2;
	winsizey = (y * (video_scale + 1)) / 2;
	win_doresize = 1;
	pthread_mutex_unlock(&shell_mutex);
}

void arc_main_loop(void)
{
	if (!shell_session_active)
		return;

	input_capture_host_snapshot();
	shell_handle_shortcuts();
	shell_apply_pending_resize();
	shell_apply_pending_fullscreen();
	shell_apply_pending_renderer_reset();
	video_renderer_update_layout();

	if (updatemips)
	{
		shell_set_window_title();
		vidc_framecount = 0;
		updatemips = 0;
	}
}

void arc_start_main_thread(void *window, void *menu)
{
	(void)window;
	(void)menu;

	pthread_mutex_lock(&shell_mutex);
	quited = 0;
	emulation_quited = 0;
	pause_main_thread = 0;
	win_doresize = 0;
	win_dofullscreen = 0;
	win_renderer_reset = 0;
	emulation_command_queue_init(&shell_command_queue);
	pthread_mutex_unlock(&shell_mutex);

	shell_release_shortcut_down = 0;
	shell_fullscreen_shortcut_down = 0;
	shell_session_active = 1;

	if (!arc_shell_init())
		fatal("Shell init failed");

	shell_set_window_title();
	shell_update_menu_state();
}

void arc_stop_main_thread(void)
{
	if (!shell_session_active)
		return;

	quited = 1;
	arc_shell_shutdown();
}

void arc_pause_main_thread(void)
{
	pthread_mutex_lock(&shell_mutex);
	pause_main_thread = 1;
	pthread_cond_broadcast(&shell_cond);
	pthread_mutex_unlock(&shell_mutex);
}

void arc_resume_main_thread(void)
{
	pthread_mutex_lock(&shell_mutex);
	pause_main_thread = 0;
	pthread_cond_broadcast(&shell_cond);
	pthread_mutex_unlock(&shell_mutex);
}

void arc_do_reset(void)
{
	emulation_command_t command;

	memset(&command, 0, sizeof(command));
	command.type = EMU_COMMAND_RESET;
	emulation_queue_command(&command);
}

void arc_disc_change(int drive, char *fn)
{
	emulation_command_t command;

	memset(&command, 0, sizeof(command));
	command.type = EMU_COMMAND_DISC_CHANGE;
	command.drive = drive;
	strncpy(command.path, fn, sizeof(command.path) - 1);
	emulation_queue_command(&command);
}

void arc_disc_eject(int drive)
{
	emulation_command_t command;

	memset(&command, 0, sizeof(command));
	command.type = EMU_COMMAND_DISC_EJECT;
	command.drive = drive;
	emulation_queue_command(&command);
}

void arc_enter_fullscreen(void)
{
	pthread_mutex_lock(&shell_mutex);
	win_dofullscreen = 1;
	pthread_mutex_unlock(&shell_mutex);
}

void arc_renderer_reset(void)
{
	pthread_mutex_lock(&shell_mutex);
	win_renderer_reset = 1;
	pthread_mutex_unlock(&shell_mutex);
}

void arc_set_display_mode(int new_display_mode)
{
	emulation_command_t command;

	memset(&command, 0, sizeof(command));
	command.type = EMU_COMMAND_SET_DISPLAY_MODE;
	command.value = new_display_mode;
	emulation_queue_command(&command);
}

void arc_set_dblscan(int new_dblscan)
{
	emulation_command_t command;

	memset(&command, 0, sizeof(command));
	command.type = EMU_COMMAND_SET_DBLSCAN;
	command.value = new_dblscan;
	emulation_queue_command(&command);
}

int arc_is_session_active(void)
{
	return shell_session_active;
}

int arc_is_paused(void)
{
	return pause_main_thread;
}

void arc_save_snapshot(const char *path,
                       uint8_t *preview_png, size_t preview_png_size,
                       int preview_width, int preview_height,
                       void *meta)
{
	emulation_command_t command;

	if (!path || !path[0])
	{
		/* Caller transferred ownership; free on rejection. */
		free(preview_png);
		free(meta);
		return;
	}

	memset(&command, 0, sizeof(command));
	command.type = EMU_COMMAND_SAVE_SNAPSHOT;
	strncpy(command.path, path, sizeof(command.path) - 1);
	command.preview_png      = preview_png;
	command.preview_png_size = preview_png_size;
	command.preview_width    = preview_width;
	command.preview_height   = preview_height;
	command.meta             = meta;
	if (!emulation_queue_command(&command))
	{
		/* Queue was full; free the buffers the caller handed us. */
		free(preview_png);
		free(meta);
		rpclog("arc_save_snapshot: command queue full, dropping save\n");
	}
}

int arc_start_snapshot_session(const char *path, char *err_out, size_t n)
{
	snapshot_load_ctx_t *ctx;
	char runtime_config[PATH_MAX];
	const char *original_name;

	if (err_out && n)
		err_out[0] = 0;

	if (shell_session_active)
	{
		if (err_out && n)
			snprintf(err_out, n,
			         "cannot load snapshot while an emulation session is active");
		return 0;
	}

	/* Check up-front that a video view is (or can be made) available.
	 * Doing this before snapshot_prepare_runtime() keeps the error
	 * path simple — no filesystem state has been committed yet. */
	if (![EmulatorBridge ensureVideoViewInstalled])
	{
		NSString *last = [EmulatorBridge lastStartError];
		if (err_out && n)
			snprintf(err_out, n, "%s",
			         last ? [last UTF8String] : "emulator view not available");
		return 0;
	}

	ctx = snapshot_open(path, err_out, n);
	if (!ctx)
		return 0;

	if (!snapshot_prepare_runtime(ctx,
	                              shell_snapshot_runtime_dir,
	                              sizeof(shell_snapshot_runtime_dir),
	                              runtime_config, sizeof(runtime_config),
	                              shell_snapshot_runtime_name,
	                              sizeof(shell_snapshot_runtime_name),
	                              err_out, n))
	{
		snapshot_close(ctx);
		shell_snapshot_runtime_dir[0] = 0;
		shell_snapshot_runtime_name[0] = 0;
		return 0;
	}

	original_name = snapshot_original_config_name(ctx);
	snprintf(shell_snapshot_display_name,
	         sizeof(shell_snapshot_display_name),
	         "%s", original_name ? original_name : "");
	shell_snapshot_session = 1;

	strncpy(machine_config_file, runtime_config,
	        sizeof(machine_config_file) - 1);
	machine_config_file[sizeof(machine_config_file) - 1] = 0;
	strncpy(machine_config_name, shell_snapshot_runtime_name,
	        sizeof(machine_config_name) - 1);
	machine_config_name[sizeof(machine_config_name) - 1] = 0;

	pthread_mutex_lock(&shell_mutex);
	shell_pending_snapshot_ctx = ctx;
	pthread_mutex_unlock(&shell_mutex);

	arc_start_main_thread(NULL, NULL);
	return 1;
}

const char *arc_snapshot_session_display_name(void)
{
	if (!shell_snapshot_session || !shell_snapshot_display_name[0])
		return NULL;
	return shell_snapshot_display_name;
}

void arc_set_video_view(MTKView *view)
{
	shell_video_view = view;
}

MTKView *arc_get_video_view(void)
{
	return shell_video_view;
}

void arc_stop_emulation(void)
{
	shell_schedule_stop_handling();
}

void arc_popup_menu(void)
{
	dispatch_async(dispatch_get_main_queue(), ^{
		if (!shell_video_view || mousecapture)
			return;

		shell_update_menu_state();
		NSEvent *event = [NSApp currentEvent];
		if (event)
			[NSMenu popUpContextMenu:shell_context_menu withEvent:event forView:shell_video_view];
	});
}

void arc_update_menu(void)
{
	dispatch_async(dispatch_get_main_queue(), ^{
		shell_update_menu_state();
	});
}

void *wx_getnativemenu(void *menu)
{
	(void)menu;
	return NULL;
}

void arc_print_error(const char *format, ...)
{
	char buffer[1024];
	va_list ap;

	va_start(ap, format);
	vsnprintf(buffer, sizeof(buffer), format, ap);
	va_end(ap);

	NSString *message = [NSString stringWithUTF8String:buffer];
	dispatch_async(dispatch_get_main_queue(), ^{
		shell_show_alert(@"Arculator", message);
	});
}

int main(int argc, char **argv)
{
	@autoreleasepool {
		const char *config_arg = NULL;

		strncpy(exname, argv[0], sizeof(exname) - 1);
		exname[sizeof(exname) - 1] = 0;
		{
			char *p = (char *)get_filename(exname);
			*p = 0;
		}

#ifndef NDEBUG
		for (int i = 1; i < argc; i++)
		{
			if (!strcmp(argv[i], "-ArculatorTestSupportPath") && i + 1 < argc)
			{
				setenv("ARCULATOR_SUPPORT_PATH", argv[i + 1], 1);
				i++;
			}
			else if (!strcmp(argv[i], "-ArculatorTestSaveSnapshotPath") && i + 1 < argc)
			{
				strlcpy(shell_test_snapshot_save_path, argv[i + 1], sizeof(shell_test_snapshot_save_path));
				i++;
			}
			else if (!strcmp(argv[i], "-ArculatorTestConfig") && i + 1 < argc)
			{
				strlcpy(machine_config_name, argv[i + 1], sizeof(machine_config_name));
				i++;
			}
		}
#endif

		// Apply persisted user-data location override from app preferences.
		// Swift writes "ArculatorSupportPath" via UserDefaults.standard;
		// CFPreferences for the current app reads from the same plist.
		// Skipped if ARCULATOR_SUPPORT_PATH is already set (env var or
		// debug -ArculatorTestSupportPath flag wins).
		if (!getenv("ARCULATOR_SUPPORT_PATH"))
		{
			CFTypeRef value = CFPreferencesCopyAppValue(
				CFSTR("ArculatorSupportPath"),
				kCFPreferencesCurrentApplication);
			if (value && CFGetTypeID(value) == CFStringGetTypeID())
			{
				char buf[PATH_MAX];
				if (CFStringGetFileSystemRepresentation((CFStringRef)value, buf, sizeof(buf)) && buf[0])
					setenv("ARCULATOR_SUPPORT_PATH", buf, 1);
			}
			if (value)
				CFRelease(value);
		}

		platform_paths_init(argv[0]);

		for (int i = 1; i < argc; i++)
		{
			if (!strncmp(argv[i], "-psn_", 5))
				continue;
			if (argv[i][0] != '-')
			{
				config_arg = argv[i];
				break;
			}
#ifndef NDEBUG
			else if ((!strcmp(argv[i], "-ArculatorTestSupportPath") ||
			          !strcmp(argv[i], "-ArculatorTestSaveSnapshotPath") ||
			          !strcmp(argv[i], "-ArculatorTestConfig")) && i + 1 < argc)
				i++;
#endif
			else if (!strcmp(argv[i], "-NSDocumentRevisionsDebugMode") && i + 1 < argc)
				i++;
		}

		podule_build_list();
		opendlls();

		if (config_arg)
		{
			if (!shell_config_exists(config_arg))
			{
				NSString *message = [NSString stringWithFormat:@"A configuration with the name '%s' does not exist", config_arg];
				[NSApplication sharedApplication];
				shell_show_alert(@"Arculator", message);
				return 1;
			}

			char config_path[512];
			platform_path_machine_config(config_path, sizeof(config_path), config_arg);
			strcpy(machine_config_file, config_path);
			strcpy(machine_config_name, config_arg);
		}

		joystick_init();

		[NSApplication sharedApplication];
		[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
		shell_delegate = [[ArcAppDelegate alloc] init];
		[NSApp setDelegate:shell_delegate];

		shell_timer = [NSTimer timerWithTimeInterval:0.001
					      target:[NSBlockOperation blockOperationWithBlock:^{
						      arc_main_loop();
					      }]
					    selector:@selector(main)
					    userInfo:nil
					     repeats:YES];
		[[NSRunLoop mainRunLoop] addTimer:shell_timer forMode:NSRunLoopCommonModes];

		[NSApp run];

		[shell_timer invalidate];
		shell_timer = nil;
		if (shell_session_active)
			arc_stop_main_thread();
	}

	return 0;
}

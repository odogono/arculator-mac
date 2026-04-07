#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>

#include <pthread.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>

#include "arc.h"
#include "input_snapshot.h"
#include "plat_input.h"
#include "macos/macos_util.h"

static int mouse_buttons;
static int mouse_x;
static int mouse_y;
static int mouse_capture;
static int capture_fallback_mode;
static int capture_forced_fallback;
static pthread_mutex_t input_mutex = PTHREAD_MUTEX_INITIALIZER;
static int input_mutex_ready;
static input_snapshot_state_t input_snapshot;

int mouse[3];
int key[INPUT_MAX_KEYCODES];

static NSWindow *current_window(void)
{
	NSWindow *window = [NSApp keyWindow];
	if (!window)
		window = [NSApp mainWindow];
	return window;
}

static CGPoint current_capture_center(void)
{
	__block CGPoint center = CGPointZero;

	run_on_main_thread(^{
		NSWindow *window = current_window();
		NSView *content_view;
		NSRect view_rect;
		NSRect screen_rect;

		if (!window)
			return;

		content_view = [window contentView];
		if (!content_view)
			return;

		view_rect = [content_view bounds];
		screen_rect = [window convertRectToScreen:[content_view convertRect:view_rect toView:nil]];
		center.x = NSMidX(screen_rect);
		center.y = NSMidY(screen_rect);
	});

	return center;
}

static void warp_cursor_to_capture_center(void)
{
	CGPoint center = current_capture_center();

	if (!CGPointEqualToPoint(center, CGPointZero))
		CGWarpMouseCursorPosition(center);
}

/* macOS virtual key codes range from 0x00 to 0x7E. */
#define MACOS_VK_MAX 0x80

static int capture_key_state_for_code(int code)
{
	if (code < 0 || code >= MACOS_VK_MAX)
		return 0;

	return CGEventSourceKeyState(kCGEventSourceStateHIDSystemState, (CGKeyCode)code) ? 1 : 0;
}

static void capture_host_keys(int *state_copy)
{
	static const int tracked_key_codes[] = {
		KEY_ESC, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0,
		KEY_MINUS, KEY_EQUALS, KEY_BACKSPACE, KEY_TAB, KEY_Q, KEY_W, KEY_E, KEY_R, KEY_T,
		KEY_Y, KEY_U, KEY_I, KEY_O, KEY_P, KEY_OPENBRACE, KEY_CLOSEBRACE, KEY_ENTER,
		KEY_LCONTROL, KEY_A, KEY_S, KEY_D, KEY_F, KEY_G, KEY_H, KEY_J, KEY_K, KEY_L,
		KEY_COLON, KEY_QUOTE, KEY_TILDE, KEY_LSHIFT, KEY_BACKSLASH, KEY_Z, KEY_X, KEY_C,
		KEY_V, KEY_B, KEY_N, KEY_M, KEY_COMMA, KEY_STOP, KEY_SLASH, KEY_RSHIFT,
		KEY_ASTERISK, KEY_ALT, KEY_SPACE, KEY_CAPSLOCK, KEY_F1, KEY_F2, KEY_F3, KEY_F4,
		KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_F9, KEY_F10, KEY_NUMLOCK, KEY_SCRLOCK,
		KEY_HOME, KEY_UP, KEY_PGUP, KEY_MINUS_PAD, KEY_LEFT, KEY_RIGHT, KEY_PLUS_PAD,
		KEY_END, KEY_DOWN, KEY_PGDN, KEY_INSERT, KEY_DEL, KEY_PRTSCR, KEY_F11, KEY_F12,
		KEY_LWIN, KEY_RWIN, KEY_RCONTROL, KEY_ALTGR, KEY_PAUSE, KEY_0_PAD, KEY_1_PAD,
		KEY_2_PAD, KEY_3_PAD, KEY_4_PAD, KEY_5_PAD, KEY_6_PAD, KEY_7_PAD, KEY_8_PAD,
		KEY_9_PAD, KEY_SEMICOLON, KEY_SLASH_PAD, KEY_BACKSLASH2, KEY_DEL_PAD, KEY_ENTER_PAD
	};

	memset(state_copy, 0, sizeof(int) * INPUT_MAX_KEYCODES);

	for (size_t i = 0; i < sizeof(tracked_key_codes) / sizeof(tracked_key_codes[0]); i++)
	{
		int code = tracked_key_codes[i];

		if (code >= 0 && code < INPUT_MAX_KEYCODES)
			state_copy[code] = capture_key_state_for_code(code);
	}
}

static void reset_input_state(void)
{
	mouse_buttons = 0;
	mouse_x = 0;
	mouse_y = 0;
	mouse_capture = 0;
	capture_fallback_mode = 0;
}

void mouse_capture_enable(void)
{
	run_on_main_thread(^{
		NSWindow *window = current_window();

		if (window)
			[window setAcceptsMouseMovedEvents:YES];

		capture_fallback_mode = capture_forced_fallback;
		if (!capture_fallback_mode)
		{
			CGError error = CGAssociateMouseAndMouseCursorPosition(false);

			if (error != kCGErrorSuccess)
			{
				rpclog("Mouse capture: relative mode unavailable, using fallback\n");
				capture_fallback_mode = 1;
			}
		}

		[NSCursor hide];
		if (capture_fallback_mode)
			warp_cursor_to_capture_center();
		else
		{
			int32_t drain_x;
			int32_t drain_y;

			CGGetLastMouseDelta(&drain_x, &drain_y);
		}
	});

	rpclog("Mouse captured%s\n", capture_fallback_mode ? " (fallback)" : "");
	mouse_capture = 1;
}

void mouse_capture_disable(void)
{
	run_on_main_thread(^{
		if (!capture_fallback_mode)
			CGAssociateMouseAndMouseCursorPosition(true);
		[NSCursor unhide];
	});

	rpclog("Mouse released\n");
	mouse_capture = 0;
}

void mouse_get_mickeys(int *x, int *y)
{
	*x = mouse_x;
	*y = mouse_y;
	mouse_x = 0;
	mouse_y = 0;
}

int mouse_get_buttons(void)
{
	return mouse_buttons;
}

void input_capture_host_snapshot(void)
{
	int state_copy[INPUT_MAX_KEYCODES];
	int snapshot_buttons = 0;
	int captured = 0;
	int in_fallback = 0;
	int32_t delta_x = 0;
	int32_t delta_y = 0;

	__block int active = 0;
	__block int buttons = 0;
	__block CGPoint fb_center = CGPointZero;
	__block NSPoint fb_location = NSZeroPoint;

	if (!input_mutex_ready)
		return;

	pthread_mutex_lock(&input_mutex);
	captured = mouse_capture;
	in_fallback = capture_fallback_mode;

	run_on_main_thread(^{
		active = [NSApp isActive] ? 1 : 0;

		if (!captured)
			return;

		NSEventModifierFlags pressed = [NSEvent pressedMouseButtons];
		if (pressed & (1u << 0))
			buttons |= 1;
		if (pressed & (1u << 1))
			buttons |= 2;
		if (pressed & (1u << 2))
			buttons |= 4;

		if (in_fallback)
		{
			NSWindow *window = current_window();

			if (window)
			{
				NSView *content_view = [window contentView];
				if (content_view)
				{
					NSRect view_rect = [content_view bounds];
					NSRect screen_rect = [window convertRectToScreen:[content_view convertRect:view_rect toView:nil]];
					fb_center.x = NSMidX(screen_rect);
					fb_center.y = NSMidY(screen_rect);
				}
			}

			fb_location = [NSEvent mouseLocation];
		}
	});

	if (!active)
	{
		memset(state_copy, 0, sizeof(state_copy));
		captured = 0;
	}
	else
	{
		capture_host_keys(state_copy);
	}

	input_snapshot_capture_keys(&input_snapshot, state_copy, INPUT_MAX_KEYCODES);

	if (captured)
	{
		snapshot_buttons = buttons;

		if (in_fallback)
		{
			delta_x = (int32_t)lrint(fb_location.x - fb_center.x);
			delta_y = (int32_t)lrint(fb_center.y - fb_location.y);
			if ((delta_x || delta_y) && !CGPointEqualToPoint(fb_center, CGPointZero))
				CGWarpMouseCursorPosition(fb_center);
		}
		else
		{
			CGGetLastMouseDelta(&delta_x, &delta_y);
			delta_y = -delta_y;
		}
	}

	input_snapshot_capture_mouse(&input_snapshot, captured, (int)delta_x, (int)delta_y, snapshot_buttons);
	pthread_mutex_unlock(&input_mutex);
}

void input_apply_host_snapshot(void)
{
	if (!input_mutex_ready)
		return;

	pthread_mutex_lock(&input_mutex);
	input_snapshot_apply(&input_snapshot, key, INPUT_MAX_KEYCODES, &mouse_buttons, &mouse_x, &mouse_y);
	pthread_mutex_unlock(&input_mutex);
}

int input_get_host_key_state(int code)
{
	int value = 0;

	if (!input_mutex_ready || code < 0 || code >= INPUT_MAX_KEYCODES)
		return 0;

	pthread_mutex_lock(&input_mutex);
	value = input_snapshot_get_host_key_state(&input_snapshot, code);
	pthread_mutex_unlock(&input_mutex);

	return value;
}

void input_init(void)
{
	if (input_mutex_ready)
		return;

	memset(key, 0, sizeof(key));
	memset(mouse, 0, sizeof(mouse));
	input_snapshot_state_init(&input_snapshot);
	reset_input_state();
	capture_forced_fallback = (getenv("ARCULATOR_MACOS_MOUSE_FALLBACK") != NULL) ? 1 : 0;
	pthread_mutex_init(&input_mutex, NULL);
	input_mutex_ready = 1;
}

void input_close(void)
{
	if (!input_mutex_ready)
		return;

	if (mouse_capture)
		mouse_capture_disable();

	pthread_mutex_destroy(&input_mutex);
	input_mutex_ready = 0;
}

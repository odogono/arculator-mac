/*Arculator 2.2 by Sarah Walker
  Generic SDL-based main window handling*/
#include <sys/time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <SDL.h>
#ifdef __APPLE__
#include <dispatch/dispatch.h>
#include <pthread.h>
#endif
#include <wx/defs.h>
#include "arc.h"
#include "debugger.h"
#include "disc.h"
#include "emulation_control.h"
#include "ioc.h"
#include "plat_input.h"
#include "platform_shell.h"
#include "plat_video.h"
#include "vidc.h"
#include "video.h"
#include "video_sdl2.h"

#ifdef __APPLE__
extern void arc_main_loop(void);

static void sdl_run_on_main_thread(void (*fn)(void *), void *ctx)
{
	if (pthread_main_np())
	{
		fn(ctx);
		return;
	}

	dispatch_sync_f(dispatch_get_main_queue(), ctx, fn);
}
#endif

static int winsizex = 0, winsizey = 0;
static int win_doresize = 0;
static int win_dofullscreen = 0;
static int win_dosetresize = 0;
static int win_renderer_reset = 0;
static emulation_command_queue_t command_queue;
static SDL_mutex *main_thread_mutex = NULL;
static SDL_cond *main_thread_cond = NULL;

#ifdef __APPLE__
typedef struct sdl_window_grab_context_t
{
	SDL_bool grabbed;
} sdl_window_grab_context_t;

typedef struct sdl_window_resize_context_t
{
	int width;
	int height;
} sdl_window_resize_context_t;

typedef struct sdl_window_title_context_t
{
	const char *title;
} sdl_window_title_context_t;

static void sdl_set_window_grab_main(void *ctx)
{
	const sdl_window_grab_context_t *grab_ctx = (const sdl_window_grab_context_t *)ctx;
	SDL_SetWindowGrab(sdl_main_window, grab_ctx->grabbed);
}

static void sdl_resize_window_main(void *ctx)
{
	const sdl_window_resize_context_t *resize_ctx = (const sdl_window_resize_context_t *)ctx;
	SDL_Rect rect;

	SDL_GetWindowSize(sdl_main_window, &rect.w, &rect.h);
	if (rect.w != resize_ctx->width || rect.h != resize_ctx->height)
	{
		rpclog("Resizing window to %d, %d\n", resize_ctx->width, resize_ctx->height);
		SDL_GetWindowPosition(sdl_main_window, &rect.x, &rect.y);
		SDL_SetWindowSize(sdl_main_window, resize_ctx->width, resize_ctx->height);
		SDL_SetWindowPosition(sdl_main_window, rect.x, rect.y);
	}
}

static void sdl_enter_fullscreen_main(void *ctx)
{
	(void)ctx;
	SDL_RaiseWindow(sdl_main_window);
	SDL_SetWindowFullscreen(sdl_main_window, SDL_WINDOW_FULLSCREEN_DESKTOP);
}

static void sdl_exit_fullscreen_main(void *ctx)
{
	(void)ctx;
	SDL_SetWindowFullscreen(sdl_main_window, 0);
}

static void sdl_set_window_title_main(void *ctx)
{
	const sdl_window_title_context_t *title_ctx = (const sdl_window_title_context_t *)ctx;
	SDL_SetWindowTitle(sdl_main_window, title_ctx->title);
}

static void sdl_destroy_window_main(void *ctx)
{
	(void)ctx;
	SDL_DestroyWindow(sdl_main_window);
}
#endif

void updatewindowsize(int x, int y)
{
	if (!main_thread_mutex)
		return;

	SDL_LockMutex(main_thread_mutex);
	winsizex = (x * (video_scale + 1)) / 2;
	winsizey = (y * (video_scale + 1)) / 2;
	win_doresize = 1;
	SDL_UnlockMutex(main_thread_mutex);
}

static void sdl_enable_mouse_capture()
{
	mouse_capture_enable();
#ifdef __APPLE__
	sdl_window_grab_context_t grab_ctx = { SDL_TRUE };
	sdl_run_on_main_thread(sdl_set_window_grab_main, &grab_ctx);
#else
	SDL_SetWindowGrab(sdl_main_window, SDL_TRUE);
#endif
	mousecapture = 1;
	updatemips = 1;
}

static void sdl_disable_mouse_capture()
{
#ifdef __APPLE__
	sdl_window_grab_context_t grab_ctx = { SDL_FALSE };
	sdl_run_on_main_thread(sdl_set_window_grab_main, &grab_ctx);
#else
	SDL_SetWindowGrab(sdl_main_window, SDL_FALSE);
#endif
	mouse_capture_disable();
	mousecapture = 0;
	updatemips = 1;
}

static volatile int quited = 0;
static volatile int pause_main_thread = 0;
static volatile int emulation_quited = 0;

static int emulation_queue_command(const emulation_command_t *command)
{
	if (!main_thread_mutex)
		return 0;

	SDL_LockMutex(main_thread_mutex);
	if (!emulation_command_queue_push(&command_queue, command))
	{
		SDL_UnlockMutex(main_thread_mutex);
		return 0;
	}
	SDL_CondSignal(main_thread_cond);
	SDL_UnlockMutex(main_thread_mutex);
	return 1;
}

static int emulation_dequeue_command(emulation_command_t *command)
{
	int has_command = 0;

	SDL_LockMutex(main_thread_mutex);
	has_command = emulation_command_queue_pop(&command_queue, command);
	SDL_UnlockMutex(main_thread_mutex);

	return has_command;
}

static void emulation_execute_command(const emulation_command_t *command)
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
	}
}

static int arc_emulation_thread(void *p)
{
	int initialized = 0;
	struct timeval tp;
	time_t last_seconds = 0;

	(void)p;
	rpclog("Arculator startup\n");

	if (arc_init())
	{
		arc_print_error("Configured ROM set is not available.\nConfiguration could not be run.");
		arc_stop_emulation();
		SDL_LockMutex(main_thread_mutex);
		emulation_quited = 1;
		SDL_CondBroadcast(main_thread_cond);
		SDL_UnlockMutex(main_thread_mutex);
		return 0;
	}
	initialized = 1;

	while (!emulation_quited)
	{
		emulation_command_t command;
		LOG_EVENT_LOOP("event loop\n");
		if (gettimeofday(&tp, NULL) == -1)
		{
			perror("gettimeofday");
			fatal("gettimeofday failed\n");
		}
		else if (!last_seconds)
		{
			last_seconds = tp.tv_sec;
			rpclog("start time = %d\n", last_seconds);
		}
		else if (last_seconds != tp.tv_sec)
		{
			updateins();
			last_seconds = tp.tv_sec;
		}

		while (emulation_dequeue_command(&command))
			emulation_execute_command(&command);

		SDL_LockMutex(main_thread_mutex);
		while (pause_main_thread && !emulation_quited && emulation_command_queue_is_empty(&command_queue))
		{
			SDL_CondWait(main_thread_cond, main_thread_mutex);
		}
		SDL_UnlockMutex(main_thread_mutex);

		if (emulation_quited)
			break;

		arc_run();

		// Sleep to make it up to 10 ms of real time
		static Uint32 last_timer_ticks = 0;
		static int timer_offset = 0;
		Uint32 current_timer_ticks = SDL_GetTicks();
		Uint32 ticks_since_last = current_timer_ticks - last_timer_ticks;
		last_timer_ticks = current_timer_ticks;
		timer_offset += 10 - (int)ticks_since_last;
		if (timer_offset > 100 || timer_offset < -100)
		{
			timer_offset = 0;
		}
		else if (timer_offset > 0)
		{
			SDL_Delay(timer_offset);
		}
	}

	rpclog("SHUTTING DOWN\n");

	if (initialized)
		arc_close();

	SDL_LockMutex(main_thread_mutex);
	emulation_quited = 1;
	SDL_CondBroadcast(main_thread_cond);
	SDL_UnlockMutex(main_thread_mutex);

	return 0;
}

static SDL_Thread *emulation_thread_handle = NULL;

static int arc_shell_init(void)
{
	if (!video_renderer_init(NULL))
		return 0;
	input_init();
	arc_update_menu();

	emulation_thread_handle = SDL_CreateThread(arc_emulation_thread, "Emulation Thread", NULL);
	if (!emulation_thread_handle)
		return 0;

	return 1;
}

static void arc_shell_pump_once(void)
{
	SDL_Event e;

	while (SDL_PollEvent(&e) != 0)
	{
		if (e.type == SDL_QUIT)
		{
			arc_stop_emulation();
		}
		if (e.type == SDL_MOUSEBUTTONUP)
		{
			if (e.button.button == SDL_BUTTON_LEFT && !mousecapture)
			{
				rpclog("Mouse click -- enabling mouse capture\n");
				sdl_enable_mouse_capture();
			}
			else if (e.button.button == SDL_BUTTON_RIGHT && !mousecapture)
			{
				arc_popup_menu();
			}
		}
		if (e.type == SDL_WINDOWEVENT)
		{
			switch (e.window.event)
			{
			case SDL_WINDOWEVENT_FOCUS_LOST:
				if (mousecapture)
				{
					rpclog("Focus lost -- disabling mouse capture\n");
					sdl_disable_mouse_capture();
				}
				break;

			default:
				break;
			}
		}
	}

	input_capture_host_snapshot();

#ifdef __APPLE__
	if ((input_get_host_key_state(KEY_LWIN) || input_get_host_key_state(KEY_RWIN)) &&
		input_get_host_key_state(KEY_BACKSPACE) && !fullscreen && mousecapture)
	{
		rpclog("CMD-BACKSPACE pressed -- disabling mouse capture\n");
		sdl_disable_mouse_capture();
	}
#else
	if ((input_get_host_key_state(KEY_LCONTROL) || input_get_host_key_state(KEY_RCONTROL)) &&
		input_get_host_key_state(KEY_END) && !fullscreen && mousecapture)
	{
		rpclog("CTRL-END pressed -- disabling mouse capture\n");
		sdl_disable_mouse_capture();
	}
#endif

	SDL_LockMutex(main_thread_mutex);
	if (!fullscreen && win_doresize)
	{
		win_doresize = 0;
#ifdef __APPLE__
		sdl_window_resize_context_t resize_ctx = { winsizex, winsizey };
		sdl_run_on_main_thread(sdl_resize_window_main, &resize_ctx);
#else
		SDL_Rect rect;
		SDL_GetWindowSize(sdl_main_window, &rect.w, &rect.h);
		if (rect.w != winsizex || rect.h != winsizey)
		{
			rpclog("Resizing window to %d, %d\n", winsizex, winsizey);
			SDL_GetWindowPosition(sdl_main_window, &rect.x, &rect.y);
			SDL_SetWindowSize(sdl_main_window, winsizex, winsizey);
			SDL_SetWindowPosition(sdl_main_window, rect.x, rect.y);
		}
#endif
	}
	SDL_UnlockMutex(main_thread_mutex);

	if (win_dofullscreen ||
		(input_get_host_key_state(KEY_RWIN) && input_get_host_key_state(KEY_ENTER) && !fullscreen))
	{
		SDL_LockMutex(main_thread_mutex);
		win_dofullscreen = 0;
		SDL_UnlockMutex(main_thread_mutex);

#ifdef __APPLE__
		sdl_run_on_main_thread(sdl_enter_fullscreen_main, NULL);
#else
		SDL_RaiseWindow(sdl_main_window);
		SDL_SetWindowFullscreen(sdl_main_window, SDL_WINDOW_FULLSCREEN_DESKTOP);
#endif
		sdl_enable_mouse_capture();
		fullscreen = 1;
	}
#ifdef __APPLE__
	else if (fullscreen && (
						   ((input_get_host_key_state(KEY_LWIN) || input_get_host_key_state(KEY_RWIN)) && input_get_host_key_state(KEY_BACKSPACE))
						   || (input_get_host_key_state(KEY_RWIN) && input_get_host_key_state(KEY_ENTER))))
#else
	else if (fullscreen && (
						   ((input_get_host_key_state(KEY_LCONTROL) || input_get_host_key_state(KEY_RCONTROL)) && input_get_host_key_state(KEY_END))
						   || (input_get_host_key_state(KEY_RWIN) && input_get_host_key_state(KEY_ENTER))))
#endif
	{
#ifdef __APPLE__
		sdl_run_on_main_thread(sdl_exit_fullscreen_main, NULL);
#else
		SDL_SetWindowFullscreen(sdl_main_window, 0);
#endif
		sdl_disable_mouse_capture();

		fullscreen = 0;
		if (fullborders)
			updatewindowsize(800, 600);
		else
			updatewindowsize(672, 544);
	}

	SDL_LockMutex(main_thread_mutex);
	if (win_renderer_reset)
	{
		win_renderer_reset = 0;
		SDL_UnlockMutex(main_thread_mutex);

		if (!video_renderer_reinit(NULL))
			fatal("Video renderer init failed");
	}
	else
	{
		SDL_UnlockMutex(main_thread_mutex);
	}

	if (updatemips)
	{
		char s[80];

#ifdef __APPLE__
		sprintf(s, "Arculator %s - %i%% - %s", VERSION_STRING, inssec, mousecapture ? "Press CMD-BACKSPACE to release mouse" : "Click to capture mouse");
#else
		sprintf(s, "Arculator %s - %i%% - %s", VERSION_STRING, inssec, mousecapture ? "Press CTRL-END to release mouse" : "Click to capture mouse");
#endif
		vidc_framecount = 0;
		if (!fullscreen)
		{
#ifdef __APPLE__
			sdl_window_title_context_t title_ctx = { s };
			sdl_run_on_main_thread(sdl_set_window_title_main, &title_ctx);
#else
			SDL_SetWindowTitle(sdl_main_window, s);
#endif
		}
		updatemips = 0;
	}
}

static void arc_shell_shutdown(void)
{
	SDL_LockMutex(main_thread_mutex);
	emulation_quited = 1;
	SDL_CondBroadcast(main_thread_cond);
	SDL_UnlockMutex(main_thread_mutex);

	if (emulation_thread_handle)
	{
		SDL_WaitThread(emulation_thread_handle, NULL);
		emulation_thread_handle = NULL;
	}

	input_close();
	video_renderer_close();

#ifdef __APPLE__
	sdl_run_on_main_thread(sdl_destroy_window_main, NULL);
#else
	SDL_DestroyWindow(sdl_main_window);
#endif
	sdl_main_window = NULL;
}

#ifndef __APPLE__
static int arc_main_thread(void *p)
{
	(void)p;

	if (!arc_shell_init())
		fatal("Shell init failed");

	while (!quited)
	{
		arc_shell_pump_once();
		SDL_Delay(1);
	}

	arc_shell_shutdown();
	return 0;
}

static SDL_Thread *main_thread;
#endif

void arc_main_loop(void)
{
	if (quited || !main_thread_mutex)
		return;

	arc_shell_pump_once();
}

void arc_start_main_thread(void *wx_window, void *wx_menu)
{
	(void)wx_window;
	(void)wx_menu;
	quited = 0;
	emulation_quited = 0;
	pause_main_thread = 0;
	main_thread_mutex = SDL_CreateMutex();
	main_thread_cond = SDL_CreateCond();
	emulation_command_queue_init(&command_queue);
#ifdef __APPLE__
	if (!arc_shell_init())
		fatal("Shell init failed");
#else
	main_thread = SDL_CreateThread(arc_main_thread, "Main Thread", (void *)NULL);

	if (!main_thread)
		fatal("Could not create shell thread");
#endif
}

void arc_stop_main_thread()
{
	quited = 1;
#ifdef __APPLE__
	if (main_thread_mutex)
		arc_shell_shutdown();
#else
	SDL_LockMutex(main_thread_mutex);
	emulation_quited = 1;
	SDL_CondBroadcast(main_thread_cond);
	SDL_UnlockMutex(main_thread_mutex);
	SDL_WaitThread(main_thread, NULL);
#endif
	SDL_DestroyCond(main_thread_cond);
	main_thread_cond = NULL;
	SDL_DestroyMutex(main_thread_mutex);
	main_thread_mutex = NULL;
}

void arc_pause_main_thread()
{
	SDL_LockMutex(main_thread_mutex);
	pause_main_thread = 1;
	SDL_CondBroadcast(main_thread_cond);
	SDL_UnlockMutex(main_thread_mutex);
}

void arc_resume_main_thread()
{
	SDL_LockMutex(main_thread_mutex);
	pause_main_thread = 0;
	SDL_CondBroadcast(main_thread_cond);
	SDL_UnlockMutex(main_thread_mutex);
}

void arc_do_reset()
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

void arc_renderer_reset()
{
	SDL_LockMutex(main_thread_mutex);
	win_renderer_reset = 1;
	SDL_UnlockMutex(main_thread_mutex);
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

void arc_set_resizeable()
{
	win_dosetresize = 1;
}

void arc_enter_fullscreen()
{
	SDL_LockMutex(main_thread_mutex);
	win_dofullscreen = 1;
	SDL_UnlockMutex(main_thread_mutex);
}

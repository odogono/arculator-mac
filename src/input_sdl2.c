/*Arculator 2.2 by Sarah Walker
  SDL2 input handling*/
#include <SDL.h>
#include <string.h>
#include "arc.h"
#include "input_snapshot.h"
#include "plat_input.h"
#include "video_sdl2.h"

static int mouse_buttons;
static int mouse_x = 0, mouse_y = 0;

static int mouse_capture = 0;
static SDL_mutex *input_mutex;

int mouse[3];
static input_snapshot_state_t input_snapshot;

static void mouse_init()
{
	mouse_buttons = 0;
	mouse_x = 0;
	mouse_y = 0;
	mouse_capture = 0;
}

static void mouse_close()
{
}

void mouse_capture_enable()
{
	rpclog("Mouse captured\n");
	SDL_SetRelativeMouseMode(SDL_TRUE);
	SDL_SetWindowGrab(sdl_main_window, SDL_TRUE);
	mouse_capture = 1;
}

void mouse_capture_disable()
{
	rpclog("Mouse released\n");
	mouse_capture = 0;
	SDL_SetWindowGrab(sdl_main_window, SDL_FALSE);
	SDL_SetRelativeMouseMode(SDL_FALSE);
}

void mouse_get_mickeys(int *x, int *y)
{
	*x = mouse_x;
	*y = mouse_y;
	mouse_x = mouse_y = 0;
}

int mouse_get_buttons()
{
	return mouse_buttons;
}


int key[INPUT_MAX_KEYCODES];

static void keyboard_init()
{
}

static void keyboard_close()
{
}

void input_capture_host_snapshot()
{
	int c;
	int captured;
	int state_copy[INPUT_MAX_KEYCODES];
	const uint8_t *state;
	int snapshot_buttons = 0;
	int snapshot_mouse_x = 0;
	int snapshot_mouse_y = 0;

	if (!input_mutex)
		return;

	SDL_LockMutex(input_mutex);

	captured = mouse_capture;
	state = SDL_GetKeyboardState(NULL);
	for (c = 0; c < INPUT_MAX_KEYCODES; c++)
		state_copy[c] = state[c];
	input_snapshot_capture_keys(&input_snapshot, state_copy, INPUT_MAX_KEYCODES);

	if (captured)
	{
		SDL_Rect rect;
		uint32_t mb = SDL_GetRelativeMouseState(&mouse[0], &mouse[1]);

		if (mb & SDL_BUTTON(SDL_BUTTON_LEFT))
			snapshot_buttons |= 1;
		if (mb & SDL_BUTTON(SDL_BUTTON_RIGHT))
			snapshot_buttons |= 2;
		if (mb & SDL_BUTTON(SDL_BUTTON_MIDDLE))
			snapshot_buttons |= 4;

		snapshot_mouse_x = mouse[0];
		snapshot_mouse_y = mouse[1];

		SDL_GetWindowSize(sdl_main_window, &rect.w, &rect.h);
		SDL_WarpMouseInWindow(sdl_main_window, rect.w / 2, rect.h / 2);
	}

	input_snapshot_capture_mouse(&input_snapshot, captured, snapshot_mouse_x, snapshot_mouse_y, snapshot_buttons);

	SDL_UnlockMutex(input_mutex);
}

void input_apply_host_snapshot()
{
	if (!input_mutex)
		return;

	SDL_LockMutex(input_mutex);
	input_snapshot_apply(&input_snapshot, key, INPUT_MAX_KEYCODES, &mouse_buttons, &mouse_x, &mouse_y);
	SDL_UnlockMutex(input_mutex);
}

int input_get_host_key_state(int code)
{
	int value = 0;

	if (!input_mutex || code < 0 || code >= INPUT_MAX_KEYCODES)
		return 0;

	SDL_LockMutex(input_mutex);
	value = input_snapshot_get_host_key_state(&input_snapshot, code);
	SDL_UnlockMutex(input_mutex);

	return value;
}


void input_init()
{
	input_mutex = SDL_CreateMutex();
	input_snapshot_state_init(&input_snapshot);
	memset(key, 0, sizeof(key));
	mouse_init();
	keyboard_init();
}
void input_close()
{
	keyboard_close();
	mouse_close();
	if (input_mutex)
	{
		SDL_DestroyMutex(input_mutex);
		input_mutex = NULL;
	}
}

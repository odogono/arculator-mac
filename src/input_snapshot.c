#include <string.h>

#include "input_snapshot.h"

void input_snapshot_state_init(input_snapshot_state_t *state)
{
	memset(state, 0, sizeof(*state));
}

void input_snapshot_capture_keys(input_snapshot_state_t *state, const int *keys, int key_count)
{
	if (key_count > INPUT_MAX_KEYCODES)
		key_count = INPUT_MAX_KEYCODES;

	memcpy(state->host_key_state, keys, key_count * sizeof(int));
	memcpy(state->pending_key_state, keys, key_count * sizeof(int));
}

void input_snapshot_capture_mouse(input_snapshot_state_t *state, int captured, int delta_x, int delta_y, int buttons)
{
	if (!captured)
	{
		state->pending_mouse_buttons = 0;
		return;
	}

	state->pending_mouse_buttons = buttons;
	state->pending_mouse_x += delta_x;
	state->pending_mouse_y += delta_y;
}

int input_snapshot_get_host_key_state(const input_snapshot_state_t *state, int code)
{
	if (code < 0 || code >= INPUT_MAX_KEYCODES)
		return 0;

	return state->host_key_state[code];
}

void input_snapshot_apply(input_snapshot_state_t *state, int *keys, int key_count, int *mouse_buttons, int *mouse_x, int *mouse_y)
{
	if (key_count > INPUT_MAX_KEYCODES)
		key_count = INPUT_MAX_KEYCODES;

	memcpy(keys, state->pending_key_state, key_count * sizeof(int));
	*mouse_buttons = state->pending_mouse_buttons;
	*mouse_x += state->pending_mouse_x;
	*mouse_y += state->pending_mouse_y;
	state->pending_mouse_x = 0;
	state->pending_mouse_y = 0;
}

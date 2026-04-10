#include <string.h>

#include "input_snapshot.h"

static void input_snapshot_apply_host_suppression(input_snapshot_state_t *state, int key_count)
{
	int any_still_down = 0;

	if (!state->suppression_active)
		return;

	for (int i = 0; i < key_count; i++)
	{
		if (!state->suppressed_key_active[i])
			continue;
		if (state->host_key_state[i])
			any_still_down = 1;
	}

	if (!any_still_down)
	{
		memset(state->suppressed_key_active, 0, sizeof(state->suppressed_key_active));
		state->suppression_active = 0;
		return;
	}

	for (int i = 0; i < key_count; i++)
	{
		if (!state->suppressed_key_active[i])
			continue;
		state->host_key_state[i] = 0;
		state->pending_key_state[i] = 0;
	}
}

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
	input_snapshot_apply_host_suppression(state, key_count);
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

int input_snapshot_is_host_key_suppressed(const input_snapshot_state_t *state, int code)
{
	if (code < 0 || code >= INPUT_MAX_KEYCODES)
		return 0;

	return state->suppressed_key_active[code];
}

void input_snapshot_apply(input_snapshot_state_t *state, int *keys, int key_count, int *mouse_buttons, int *mouse_x, int *mouse_y)
{
	int i;

	if (key_count > INPUT_MAX_KEYCODES)
		key_count = INPUT_MAX_KEYCODES;

	memcpy(keys, state->pending_key_state, key_count * sizeof(int));

	/* Overlay injected keys on top of host state */
	for (i = 0; i < key_count; i++)
	{
		if (state->injected_key_active[i])
			keys[i] = state->injected_key_state[i];
	}

	/* Overlay injected mouse buttons */
	*mouse_buttons =
		(state->pending_mouse_buttons & ~state->injected_mouse_buttons_active_mask) |
		(state->injected_mouse_buttons & state->injected_mouse_buttons_active_mask);

	/* Absolute mouse injection overrides deltas when pending */
	if (state->injected_mouse_abs_pending)
	{
		*mouse_x = state->injected_mouse_abs_x;
		*mouse_y = state->injected_mouse_abs_y;
		state->injected_mouse_abs_pending = 0;
	}
	else
	{
		/* Host deltas + injected deltas (additive, one-shot) */
		*mouse_x += state->pending_mouse_x + state->injected_mouse_dx;
		*mouse_y += state->pending_mouse_y + state->injected_mouse_dy;
	}

	state->pending_mouse_x = 0;
	state->pending_mouse_y = 0;
	state->injected_mouse_dx = 0;
	state->injected_mouse_dy = 0;
}

void input_snapshot_begin_host_key_suppression(input_snapshot_state_t *state, const int *keys, int key_count)
{
	int suppressed_any = 0;

	if (!keys || key_count <= 0)
		return;

	for (int i = 0; i < key_count; i++)
	{
		int code = keys[i];
		if (code < 0 || code >= INPUT_MAX_KEYCODES)
			continue;

		state->suppressed_key_active[code] = 1;
		state->host_key_state[code] = 0;
		state->pending_key_state[code] = 0;
		suppressed_any = 1;
	}

	if (suppressed_any)
		state->suppression_active = 1;
}

void input_snapshot_inject_key(input_snapshot_state_t *state, int code, int down)
{
	if (code < 0 || code >= INPUT_MAX_KEYCODES)
		return;

	state->injected_key_state[code] = down ? 1 : 0;
	state->injected_key_active[code] = 1;
}

void input_snapshot_clear_injected_key(input_snapshot_state_t *state, int code)
{
	if (code < 0 || code >= INPUT_MAX_KEYCODES)
		return;

	state->injected_key_state[code] = 0;
	state->injected_key_active[code] = 0;
}

void input_snapshot_clear_all_injected_keys(input_snapshot_state_t *state)
{
	memset(state->injected_key_state, 0, sizeof(state->injected_key_state));
	memset(state->injected_key_active, 0, sizeof(state->injected_key_active));
}

void input_snapshot_inject_mouse_button(input_snapshot_state_t *state, int button_mask, int down)
{
	state->injected_mouse_buttons_active_mask |= button_mask;
	if (down)
		state->injected_mouse_buttons |= button_mask;
	else
		state->injected_mouse_buttons &= ~button_mask;
}

void input_snapshot_inject_mouse_move(input_snapshot_state_t *state, int dx, int dy)
{
	state->injected_mouse_dx += dx;
	state->injected_mouse_dy += dy;
}

void input_snapshot_inject_mouse_abs(input_snapshot_state_t *state, int x, int y)
{
	state->injected_mouse_abs_x = x;
	state->injected_mouse_abs_y = y;
	state->injected_mouse_abs_pending = 1;
}

void input_snapshot_clear_injected_mouse(input_snapshot_state_t *state)
{
	state->injected_mouse_buttons = 0;
	state->injected_mouse_buttons_active_mask = 0;
	state->injected_mouse_dx = 0;
	state->injected_mouse_dy = 0;
	state->injected_mouse_abs_x = 0;
	state->injected_mouse_abs_y = 0;
	state->injected_mouse_abs_pending = 0;
}

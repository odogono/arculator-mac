#ifndef INPUT_SNAPSHOT_H
#define INPUT_SNAPSHOT_H

#define INPUT_MAX_KEYCODES 512

typedef struct input_snapshot_state_t
{
	int host_key_state[INPUT_MAX_KEYCODES];
	int pending_key_state[INPUT_MAX_KEYCODES];
	int pending_mouse_buttons;
	int pending_mouse_x;
	int pending_mouse_y;

	/* Injection overlay — merged on top of host state in apply() */
	int injected_key_state[INPUT_MAX_KEYCODES];
	int injected_key_active[INPUT_MAX_KEYCODES];
	int injected_mouse_buttons;
	int injected_mouse_buttons_active_mask;
	int injected_mouse_dx;
	int injected_mouse_dy;
	int injected_mouse_abs_x;
	int injected_mouse_abs_y;
	int injected_mouse_abs_pending;
} input_snapshot_state_t;

void input_snapshot_state_init(input_snapshot_state_t *state);
void input_snapshot_capture_keys(input_snapshot_state_t *state, const int *keys, int key_count);
void input_snapshot_capture_mouse(input_snapshot_state_t *state, int captured, int delta_x, int delta_y, int buttons);
int input_snapshot_get_host_key_state(const input_snapshot_state_t *state, int code);
void input_snapshot_apply(input_snapshot_state_t *state, int *keys, int key_count, int *mouse_buttons, int *mouse_x, int *mouse_y);

/* Injection functions — called from platform wrappers under mutex */
void input_snapshot_inject_key(input_snapshot_state_t *state, int code, int down);
void input_snapshot_clear_injected_key(input_snapshot_state_t *state, int code);
void input_snapshot_clear_all_injected_keys(input_snapshot_state_t *state);
void input_snapshot_inject_mouse_button(input_snapshot_state_t *state, int button_mask, int down);
void input_snapshot_inject_mouse_move(input_snapshot_state_t *state, int dx, int dy);
void input_snapshot_inject_mouse_abs(input_snapshot_state_t *state, int x, int y);
void input_snapshot_clear_injected_mouse(input_snapshot_state_t *state);

#endif

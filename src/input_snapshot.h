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
} input_snapshot_state_t;

void input_snapshot_state_init(input_snapshot_state_t *state);
void input_snapshot_capture_keys(input_snapshot_state_t *state, const int *keys, int key_count);
void input_snapshot_capture_mouse(input_snapshot_state_t *state, int captured, int delta_x, int delta_y, int buttons);
int input_snapshot_get_host_key_state(const input_snapshot_state_t *state, int code);
void input_snapshot_apply(input_snapshot_state_t *state, int *keys, int key_count, int *mouse_buttons, int *mouse_x, int *mouse_y);

#endif

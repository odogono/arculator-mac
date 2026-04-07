#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "emulation_control.h"
#include "input_snapshot.h"

static void expect_true(int condition, const char *message)
{
	if (!condition)
	{
		fprintf(stderr, "FAIL: %s\n", message);
		exit(1);
	}
}

static void test_command_queue_fifo(void)
{
	emulation_command_queue_t queue;
	emulation_command_t command;
	emulation_command_t first = {EMU_COMMAND_RESET, 0, 0, {0}};
	emulation_command_t second = {EMU_COMMAND_DISC_CHANGE, 2, 0, "disc.adf"};

	emulation_command_queue_init(&queue);
	expect_true(emulation_command_queue_is_empty(&queue), "queue should start empty");
	expect_true(emulation_command_queue_push(&queue, &first), "first push should succeed");
	expect_true(emulation_command_queue_push(&queue, &second), "second push should succeed");
	expect_true(emulation_command_queue_pop(&queue, &command), "first pop should succeed");
	expect_true(command.type == EMU_COMMAND_RESET, "first command should preserve FIFO order");
	expect_true(emulation_command_queue_pop(&queue, &command), "second pop should succeed");
	expect_true(command.type == EMU_COMMAND_DISC_CHANGE, "second command should preserve FIFO order");
	expect_true(command.drive == 2, "command payload should round-trip");
	expect_true(strcmp(command.path, "disc.adf") == 0, "command path should round-trip");
	expect_true(!emulation_command_queue_pop(&queue, &command), "empty queue pop should fail");
}

static void test_command_queue_capacity(void)
{
	emulation_command_queue_t queue;
	emulation_command_t command = {EMU_COMMAND_SET_DISPLAY_MODE, 0, 1, {0}};
	int count = 0;

	emulation_command_queue_init(&queue);
	while (emulation_command_queue_push(&queue, &command))
		count++;

	expect_true(count == EMULATION_COMMAND_QUEUE_CAPACITY - 1, "ring buffer should reserve one slot");
	expect_true(emulation_command_queue_is_full(&queue), "queue should report full");
}

static void test_input_snapshot_apply_consumes_mouse_delta_once(void)
{
	input_snapshot_state_t state;
	int host_keys[512] = {0};
	int runtime_keys[512] = {0};
	int mouse_buttons = 0;
	int mouse_x = 0;
	int mouse_y = 0;

	host_keys[10] = 1;
	host_keys[20] = 1;

	input_snapshot_state_init(&state);
	input_snapshot_capture_keys(&state, host_keys, 512);
	input_snapshot_capture_mouse(&state, 1, 3, -4, 5);
	input_snapshot_apply(&state, runtime_keys, 512, &mouse_buttons, &mouse_x, &mouse_y);

	expect_true(runtime_keys[10] == 1 && runtime_keys[20] == 1, "key snapshot should copy into runtime state");
	expect_true(mouse_buttons == 5, "mouse buttons should apply");
	expect_true(mouse_x == 3 && mouse_y == -4, "mouse delta should apply");

	input_snapshot_apply(&state, runtime_keys, 512, &mouse_buttons, &mouse_x, &mouse_y);
	expect_true(mouse_x == 3 && mouse_y == -4, "mouse delta should not be applied twice");
}

static void test_input_snapshot_uncaptured_mouse_clears_buttons(void)
{
	input_snapshot_state_t state;
	int host_keys[512] = {0};
	int runtime_keys[512] = {0};
	int mouse_buttons = 7;
	int mouse_x = 10;
	int mouse_y = 10;

	host_keys[42] = 1;

	input_snapshot_state_init(&state);
	input_snapshot_capture_keys(&state, host_keys, 512);
	input_snapshot_capture_mouse(&state, 0, 99, 99, 7);
	input_snapshot_apply(&state, runtime_keys, 512, &mouse_buttons, &mouse_x, &mouse_y);

	expect_true(mouse_buttons == 0, "uncaptured mouse should clear buttons");
	expect_true(mouse_x == 10 && mouse_y == 10, "uncaptured mouse should not move runtime cursor");
	expect_true(input_snapshot_get_host_key_state(&state, 42) == 1, "host key state lookup should reflect last capture");
}

int main(void)
{
	test_command_queue_fifo();
	test_command_queue_capacity();
	test_input_snapshot_apply_consumes_mouse_delta_once();
	test_input_snapshot_uncaptured_mouse_clears_buttons();
	return 0;
}

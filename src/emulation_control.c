#include "emulation_control.h"

void emulation_command_queue_init(emulation_command_queue_t *queue)
{
	queue->read_index = 0;
	queue->write_index = 0;
}

int emulation_command_queue_is_empty(const emulation_command_queue_t *queue)
{
	return queue->read_index == queue->write_index;
}

int emulation_command_queue_is_full(const emulation_command_queue_t *queue)
{
	return ((queue->write_index + 1) % EMULATION_COMMAND_QUEUE_CAPACITY) == queue->read_index;
}

int emulation_command_queue_push(emulation_command_queue_t *queue, const emulation_command_t *command)
{
	if (emulation_command_queue_is_full(queue))
		return 0;

	queue->commands[queue->write_index] = *command;
	queue->write_index = (queue->write_index + 1) % EMULATION_COMMAND_QUEUE_CAPACITY;
	return 1;
}

int emulation_command_queue_pop(emulation_command_queue_t *queue, emulation_command_t *command)
{
	if (emulation_command_queue_is_empty(queue))
		return 0;

	*command = queue->commands[queue->read_index];
	queue->read_index = (queue->read_index + 1) % EMULATION_COMMAND_QUEUE_CAPACITY;
	return 1;
}

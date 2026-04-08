#ifndef EMULATION_CONTROL_H
#define EMULATION_CONTROL_H

#include <stddef.h>
#include <stdint.h>

typedef enum emulation_command_type_t
{
	EMU_COMMAND_RESET = 0,
	EMU_COMMAND_DISC_CHANGE,
	EMU_COMMAND_DISC_EJECT,
	EMU_COMMAND_SET_DISPLAY_MODE,
	EMU_COMMAND_SET_DBLSCAN,
	EMU_COMMAND_SAVE_SNAPSHOT
} emulation_command_type_t;

typedef struct emulation_command_t
{
	emulation_command_type_t type;
	int drive;
	int value;
	char path[512];

	/* SAVE_SNAPSHOT payload. Heap-owned; the consumer on the
	 * emulation thread takes ownership and must free() each buffer
	 * exactly once. NULL means "no preview" / "no metadata". */
	uint8_t *preview_png;
	size_t   preview_png_size;
	int      preview_width;
	int      preview_height;

	/* Pointer to a heap-allocated arcsnap_meta_t (the real struct is
	 * defined in snapshot.h). Stored as void* here so this header
	 * stays independent of the snapshot public API. */
	void    *meta;
} emulation_command_t;

#define EMULATION_COMMAND_QUEUE_CAPACITY 32

typedef struct emulation_command_queue_t
{
	emulation_command_t commands[EMULATION_COMMAND_QUEUE_CAPACITY];
	int read_index;
	int write_index;
} emulation_command_queue_t;

void emulation_command_queue_init(emulation_command_queue_t *queue);
int emulation_command_queue_is_empty(const emulation_command_queue_t *queue);
int emulation_command_queue_is_full(const emulation_command_queue_t *queue);
int emulation_command_queue_push(emulation_command_queue_t *queue, const emulation_command_t *command);
int emulation_command_queue_pop(emulation_command_queue_t *queue, emulation_command_t *command);

#endif

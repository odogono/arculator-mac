/*Arculator 2.2 by Sarah Walker
  IOEB emulation*/
#include <string.h>
#include "arc.h"
#include "config.h"
#include "ioc.h"
#include "ioeb.h"
#include "joystick.h"
#include "plat_joystick.h"
#include "snapshot.h"
#include "snapshot_chunks.h"
#include "snapshot_subsystems.h"
#include "vidc.h"

static const struct
{
	uint8_t id;
	uint8_t hs;
} monitor_id[5] =
{
	{0xe, 0x1}, /*Standard*/
	{0xb, 0x4}, /*Multisync/SVGA*/
	{0xe, 0x0}, /*Colour VGA*/
	{0xf, 0x0}, /*High res mono - not supported by IOEB systems*/
	{0xf, 0x0}  /*LCD*/
};

static int hs_invert;
static int has_joystick_ports;
int ioeb_clock_select;

static uint8_t ioeb_joystick_read(int addr)
{
	if (joystick_a3010_present && has_joystick_ports)
	{
		int c = (addr & 4) ? 1 : 0;
		uint8_t temp = 0x7f;

		if (joystick_state[c].axis[1] < -16383)
			temp &= ~0x01;
		if (joystick_state[c].axis[1] > 16383)
			temp &= ~0x02;
		if (joystick_state[c].axis[0] < -16383)
			temp &= ~0x04;
		if (joystick_state[c].axis[0] > 16383)
			temp &= ~0x08;
		if (joystick_state[c].button[0])
			temp &= ~0x10;

		return temp;
	}
	else if (has_joystick_ports)
		return 0x7f;
	else
		return 0xff;
}

uint8_t ioeb_read(uint32_t addr)
{
	int hs;

	switch (addr & 0xf8)
	{
		case 0x50: /*Device ID*/
		return 0x05; /*IOEB*/

		case 0x70: /*Monitor ID*/
		if (hs_invert)
			hs = !vidc_get_hs();
		else
			hs = vidc_get_hs();

		if (hs)
			return monitor_id[monitor_type].id | monitor_id[monitor_type].hs;
		return monitor_id[monitor_type].id;

		case 0x78: /*Joystick (A3010)*/
		return ioeb_joystick_read(addr);
	}

	return 0xff;
}

void ioeb_write(uint32_t addr, uint8_t val)
{
	switch (addr & 0xf8)
	{
		case 0x48:
		ioeb_clock_select = val & 3;
		vidc_setclock(val & 3);
		hs_invert = val & 4;
		break;
	}
}

void ioeb_init()
{
	has_joystick_ports = !strcmp(machine, "a3010");
}

/* ----- Snapshot save/load -------------------------------------------- */

#define IOEB_STATE_VERSION 1u

int ioeb_save_state(snapshot_writer_t *w)
{
	if (!snapshot_writer_begin_chunk(w, ARCSNAP_CHUNK_IOEB, IOEB_STATE_VERSION))
		return 0;

	snapshot_writer_append_i32(w, ioeb_clock_select);
	snapshot_writer_append_i32(w, hs_invert);

	return snapshot_writer_end_chunk(w);
}

int ioeb_load_state(snapshot_payload_reader_t *r, uint32_t version)
{
	int32_t loaded_clock_select, loaded_hs_invert;

	(void)version;

	if (!snapshot_payload_reader_read_i32(r, &loaded_clock_select)) return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_hs_invert))    return 0;

	ioeb_clock_select = (int)loaded_clock_select;
	hs_invert         = (int)loaded_hs_invert;

	/* Re-apply VIDC clock selection so the timing follows the
	 * restored register value. */
	vidc_setclock(ioeb_clock_select);

	return 1;
}

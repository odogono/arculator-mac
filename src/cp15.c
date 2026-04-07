/*Arculator 2.2 by Sarah Walker
  ARM3 CP15 emulation*/
#include "arc.h"
#include "arm.h"
#include "cp15.h"
#include "mem.h"
#include "snapshot.h"
#include "snapshot_chunks.h"
#include "snapshot_subsystems.h"
#include "vidc.h"

arm3cp_t arm3cp;
int cp15_cacheon;

void resetcp15()
{
	arm3cp.ctrl = 0;
	cp15_cacheon = 0;
}

uint32_t readcp15(int reg)
{
	switch (reg)
	{
		case 0: /*ID*/
		return 0x41560300; /*VLSI ARM3*/
		case 2: /*CTRL*/
		return arm3cp.ctrl;
		case 3: /*Cacheable areas*/
		return arm3cp.cache;
		case 4: /*Updateable areas*/
		return arm3cp.update;
		case 5: /*Disruptive areas*/
		return arm3cp.disrupt;
	}
	return 0;
}

void writecp15(int reg, uint32_t val)
{
	switch (reg)
	{
		case 1:
		cache_flush();
		return;
		case 2: /*CTRL*/
		arm3cp.ctrl=val;

		cp15_cacheon = val & 1;

		rpclog("CTRL %i\n", val & 1);
		vidc_redovideotiming();
//                redoioctiming();
		return;
		case 3: /*Cacheable areas*/
		arm3cp.cache=val;
		return;
		case 4: /*Updateable areas*/
		arm3cp.update=val;
		return;
		case 5: /*Disruptive areas*/
		arm3cp.disrupt=val;
		return;
	}
}

/* ----- Snapshot save/load -------------------------------------------- */

#define CP15_STATE_VERSION 1u

int cp15_save_state(snapshot_writer_t *w)
{
	if (!snapshot_writer_begin_chunk(w, ARCSNAP_CHUNK_CP15, CP15_STATE_VERSION))
		return 0;
	snapshot_writer_append_u32(w, arm3cp.ctrl);
	snapshot_writer_append_u32(w, arm3cp.cache);
	snapshot_writer_append_u32(w, arm3cp.update);
	snapshot_writer_append_u32(w, arm3cp.disrupt);
	snapshot_writer_append_i32(w, cp15_cacheon);
	return snapshot_writer_end_chunk(w);
}

int cp15_load_state(snapshot_payload_reader_t *r, uint32_t version)
{
	uint32_t ctrl, cache, update, disrupt;
	int32_t  cacheon;

	(void)version;

	if (!snapshot_payload_reader_read_u32(r, &ctrl))    return 0;
	if (!snapshot_payload_reader_read_u32(r, &cache))   return 0;
	if (!snapshot_payload_reader_read_u32(r, &update))  return 0;
	if (!snapshot_payload_reader_read_u32(r, &disrupt)) return 0;
	if (!snapshot_payload_reader_read_i32(r, &cacheon)) return 0;

	arm3cp.ctrl    = ctrl;
	arm3cp.cache   = cache;
	arm3cp.update  = update;
	arm3cp.disrupt = disrupt;
	cp15_cacheon   = (int)cacheon;
	return 1;
}


/*Arculator 2.2 by Sarah Walker
  MEMC1/MEMC1a emulation*/

int flybacklines;
#include <stdio.h>
#include <string.h>
#include "arc.h"
#include "debugger.h"
#include "ioc.h"
#include "mem.h"
#include "memc.h"
#include "snapshot.h"
#include "snapshot_chunks.h"
#include "snapshot_subsystems.h"
#include "timer.h"
#include "vidc.h"

static struct
{
	uint32_t logical_addr;
	uint8_t ppl;
} memc_cam[512];

int memc_videodma_enable;
int memc_refreshon;
int memc_refresh_always;
int memc_is_memc1 = 1;
int memc_type;

int memc_dma_sound_req;
uint64_t memc_dma_sound_req_ts;
int memc_dma_video_req;
uint64_t memc_dma_video_req_ts;
uint64_t memc_dma_video_req_start_ts;
uint64_t memc_dma_video_req_period;
int memc_dma_cursor_req;
uint64_t memc_dma_cursor_req_ts;

uint32_t memctrl;

int sdmaena=0;
int bigcyc=0;
int pagesize;
int memcpages[0x2000];
int spdcount;

uint32_t sstart,ssend,sptr;
uint32_t vinit,vstart,vend;
uint32_t cinit;

uint32_t spos,sendN,sstart2;
int nextvalid;
#define getdmaaddr(addr) (((addr>>2)&0x7FFF)<<2)
void writememc(uint32_t a)
{
//        rpclog("Write MEMC %08X\n",a);
	switch ((a>>17)&7)
	{
		case 0:
		LOG_MEMC_VIDEO("MEMC write %08X - VINIT  = %05X\n",a,getdmaaddr(a)*4);
		vinit=getdmaaddr(a);
		LOG_MEMC_VIDEO("Vinit write %08X %07X\n",vinit,PC);
		return;
		case 1:
		/*Set start of video RAM*/
		LOG_MEMC_VIDEO("MEMC write %08X - VSTART = %05X\n",a,getdmaaddr(a)*4);
		vstart=getdmaaddr(a);
		LOG_MEMC_VIDEO("Vstart write %08X %07X\n",vstart,PC);
		return;
		case 2:
		/*Set end of video RAM*/
		LOG_MEMC_VIDEO("MEMC write %08X - VEND   = %05X\n",a,getdmaaddr(a)*4);
		vend=getdmaaddr(a);
		LOG_MEMC_VIDEO("Vend write %08X %07X\n",vend,PC);
		return;
		case 3:
		LOG_MEMC_VIDEO("MEMC write %08X - CINIT  = %05X\n",a,getdmaaddr(a));
		cinit=getdmaaddr(a);
		LOG_MEMC_VIDEO("CINIT=%05X\n",cinit<<2);
		return;
		case 4:
//                rpclog("MEMC write %08X - SSTART = %05X %05X\n",a,getdmaaddr(a),spos);
		sstart=getdmaaddr(a); /*printf("SSTART=%05X\n",sstart<<2);*/

		if (!nextvalid) nextvalid=1;
		if (nextvalid==2) nextvalid=0;

		ioc_irqbc(IOC_IRQB_SOUND_BUFFER);
		nextvalid=2;
		return;
		case 5:
//                rpclog("MEMC write %08X - SEND   = %05X %05X\n",a,getdmaaddr(a),spos);
		sendN=getdmaaddr(a);

		if (nextvalid==1) nextvalid=2;
		if (nextvalid!=2) nextvalid=1;
		return;
		case 6:
//                rpclog("MEMC write %08X - SPTR   = %05X %05X\n",a,getdmaaddr(a),spos);
		sptr=getdmaaddr(a); /*printf("SPTR=%05X\n",sptr); */
		spos=sstart2=sstart<<2;
		ssend=sendN<<2;
		ioc_irqb(IOC_IRQB_SOUND_BUFFER);
		nextvalid=0;
		return;
		case 7: /*MEMC ctrl*/
		memctrl = a & 0x3ffc;
		osmode=(a&0x1000)?1:0;
		sdmaena=(a&0x800)?1:0;
		pagesize=(a&0xC)>>2;
		resetpagesize(pagesize);
		memc_videodma_enable = a & 0x400;
		LOG_MEMC_VIDEO("MEMC set memc_videodma_enable = %d\n", memc_videodma_enable);
		switch ((a >> 6) & 3) /*High ROM speed*/
		{
			case 0: /*450ns*/
			mem_setromspeed(4, 4);
			break;
			case 1: /*325ns*/
			mem_setromspeed(3, 3);
			break;
			case 2: /*200ns*/
			mem_setromspeed(2, 2);
			break;
			case 3: /*200ns with 60ns nibble mode*/
			mem_setromspeed(2, 1);
			break;
		}
		memc_refreshon = (((a >> 8) & 3) == 1);
		memc_refresh_always = (((a >> 8) & 3) == 3);
		mem_dorefresh = (memc_refreshon && !vidc_displayon) || memc_refresh_always;
//                rpclog("MEMC ctrl write %08X %i  %i %i %i\n",a,sdmaena, memc_refreshon, memc_refresh_always, mem_dorefresh);
		return;
	}
}

void writecam(uint32_t a)
{
	int page = 0, access = 0, logical = 0, c;
//        rpclog("Write CAM %08X pagesize %i %i\n",a,pagesize,ins);
	switch (pagesize)
	{
//                #if 0
		case 1: /*8k*/
		page=((a>>1)&0x3f) | ((a&1)<<6);
		access=(a>>8)&3;
		logical=(a>>13)&0x3FF;
		logical|=(a&0xC00);
//                rpclog("Map page %02X to %03X\n",page,logical);
		for (c=0;c<0x2000;c++)
		{
			if ((memcpages[c]&~0x1FFF)==(page<<13))
			{
				memcpages[c]=~0;
				memstat[c]=0;
			}
		}
		logical<<=1;
		for (c=0;c<2;c++)
		{
			memcpages[logical+c]=page<<13;
			memstat[logical+c]=access+1;
			mempoint[logical + c] = ((uint8_t *)&ram[(page << 11) + (c << 10)]) - ((logical + c) << 12);
		}
		break;
//                #endif
		case 2: /*16k*/
		page=((a>>2)&0x1f) | ((a&3)<<5);
		access=(a>>8)&3;
		logical=(a>>14)&0x1FF;
		logical|=(a>>1)&0x600;
		for (c=0;c<0x2000;c++)
		{
			if ((memcpages[c]&~0x3FFF)==(page<<14))
			{
				memcpages[c]=~0;
				memstat[c]=0;
			}
		}
		logical<<=2;
		for (c=0;c<4;c++)
		{
			memcpages[logical+c]=page<<14;
			memstat[logical+c]=access+1;
			mempoint[logical + c] = ((uint8_t *)&ram[(page << 12) + (c << 10)]) - ((logical + c) << 12);
		}
		break;
		case 3: /*32k*/
		page=((a>>3)&0xf) | ((a&1)<<4) | ((a&2)<<5) | ((a&4)<<3);
		if (a&0x80) page|=0x80;
		if (a&0x1000) page|=0x100;
		if ((page * 32) >= memsize)
			return;
		access=(a>>8)&3;
		logical=(a>>15)&0xFF;
		logical|=(a>>2)&0x300;
//                printf("Mapping %08X to %08X\n",0x2000000+(page*32768),logical<<15);
		for (c=0;c<0x2000;c++)
		{
			if ((memcpages[c]&~0x7FFF)==(page<<15))
			{
				memcpages[c]=~0;
				memstat[c]=0;
			}
		}
		logical<<=3;
		for (c=0;c<8;c++)
		{
			memcpages[logical+c]=page<<15;
			memstat[logical+c]=access+1;
			mempoint[logical + c] = ((uint8_t *)&ram[(page << 13) + (c << 10)]) - ((logical + c) << 12);
		}
		break;
	}
//        memcpermissions[logical]=access;
	memc_cam[page].logical_addr = logical << 12;
	memc_cam[page].ppl = access;
}

void initmemc()
{
	int c;

	for (c = 0; c < 0x2000; c++)
	{
		memstat[c] = 0;
		mempoint[c] = NULL;
	}
}

static const char *page_sizes[4] =
{
	"4k", "8k", "16k", "32k"
};

static const char *rom_speeds[4] =
{
	"450ns", "325ns", "200ns", "200ns w/60ns nibble mode"
};

static const char *refresh_modes[4] =
{
	"Disabled", "Vblank only", "Disabled", "Continuous"
};

void memc_debug_print(char *s)
{
	sprintf(s, "MEMC registers :\n"
		   "Control=%04x\n"
		   "  Page size=%s\n"
		   "  Low ROM area (5th column) speed=%s (at 8 MHz)\n"
		   "  High ROM area (OS) speed=%s (at 8 MHz)\n"
		   "  DRAM refresh=%s\n"
		   "  Video DMA=%s\n"
		   "  Sound DMA=%s\n"
		   "  OS mode=%s\n\n"
		   "DMA register values :\n"
		   "  Vinit=%05x Vstart=%05x Vend=%05x Cinit=%05x\n"
		   "  Sstart=%05x SendN=%05x\n\n"
		   "DMA current values :\n"
		   "  Vaddr=%05x Caddr=%05x Saddr=%05x Send=%05x\n\n",
		   memctrl,
		   page_sizes[pagesize],
		   rom_speeds[(memctrl >> 4) & 3],
		   rom_speeds[(memctrl >> 6) & 3],
		   refresh_modes[(memctrl >> 8) & 3],
		   (memctrl & (1 << 10)) ? "Enabled" : "Disabled",
		   (memctrl & (1 << 11)) ? "Enabled" : "Disabled",
		   (memctrl & (1 << 12)) ? "Enabled" : "Disabled",
		   vinit << 2, vstart << 2, vend << 2, cinit << 2,
		   sstart << 2, sendN << 2,
		   vidc_get_current_vaddr() << 2,
		   vidc_get_current_caddr() << 2,
		   spos, ssend);
}

void memc_debug_print_cam(void)
{
	int nr_memcs = memsize / 4096;

	if (!nr_memcs)
		nr_memcs = 1;

	for (int j = 0; j < nr_memcs; j++)
	{
		char s[256];

		if (nr_memcs > 1)
		{
			sprintf(s, "MEMC #%i :\n", j);
			debug_out(s);
		}

		for (int i = 0; i < 128/4; i++)
		{
			int offset = j*128 + i;

			sprintf(s, " [%02x] addr=%07x ppl=%i   [%02x] addr=%07x ppl=%i   [%02x] addr=%07x ppl=%i   [%02x] addr=%07x ppl=%i\n",
				i, memc_cam[offset].logical_addr, memc_cam[offset].ppl,
				i+32, memc_cam[offset+32].logical_addr, memc_cam[offset+32].ppl,
				i+64, memc_cam[offset+64].logical_addr, memc_cam[offset+64].ppl,
				i+96, memc_cam[offset+96].logical_addr, memc_cam[offset+96].ppl);

			debug_out(s);
		}
		debug_out("\n");
	}
}

/* ----- Snapshot save/load -------------------------------------------- */

#define MEMC_STATE_VERSION 1u

int memc_save_state(snapshot_writer_t *w)
{
	int i;

	if (!snapshot_writer_begin_chunk(w, ARCSNAP_CHUNK_MEMC, MEMC_STATE_VERSION))
		return 0;

	if (!snapshot_writer_append_u32(w, memctrl))             goto fail;
	if (!snapshot_writer_append_i32(w, pagesize))            goto fail;
	if (!snapshot_writer_append_i32(w, sdmaena))             goto fail;
	if (!snapshot_writer_append_i32(w, bigcyc))              goto fail;
	if (!snapshot_writer_append_i32(w, memc_videodma_enable)) goto fail;
	if (!snapshot_writer_append_i32(w, memc_refreshon))      goto fail;
	if (!snapshot_writer_append_i32(w, memc_refresh_always)) goto fail;

	if (!snapshot_writer_append_u32(w, vinit))   goto fail;
	if (!snapshot_writer_append_u32(w, vstart))  goto fail;
	if (!snapshot_writer_append_u32(w, vend))    goto fail;
	if (!snapshot_writer_append_u32(w, cinit))   goto fail;
	if (!snapshot_writer_append_u32(w, sstart))  goto fail;
	if (!snapshot_writer_append_u32(w, ssend))   goto fail;
	if (!snapshot_writer_append_u32(w, sptr))    goto fail;
	if (!snapshot_writer_append_u32(w, spos))    goto fail;
	if (!snapshot_writer_append_u32(w, sendN))   goto fail;
	if (!snapshot_writer_append_u32(w, sstart2)) goto fail;
	if (!snapshot_writer_append_i32(w, nextvalid)) goto fail;

	/* DMA request flags / timestamps */
	if (!snapshot_writer_append_i32(w, memc_dma_sound_req))           goto fail;
	if (!snapshot_writer_append_u64(w, memc_dma_sound_req_ts))        goto fail;
	if (!snapshot_writer_append_i32(w, memc_dma_video_req))           goto fail;
	if (!snapshot_writer_append_u64(w, memc_dma_video_req_ts))        goto fail;
	if (!snapshot_writer_append_u64(w, memc_dma_video_req_start_ts))  goto fail;
	if (!snapshot_writer_append_u64(w, memc_dma_video_req_period))    goto fail;
	if (!snapshot_writer_append_i32(w, memc_dma_cursor_req))          goto fail;
	if (!snapshot_writer_append_u64(w, memc_dma_cursor_req_ts))       goto fail;

	/* CAM */
	for (i = 0; i < 512; i++)
	{
		if (!snapshot_writer_append_u32(w, memc_cam[i].logical_addr)) goto fail;
		if (!snapshot_writer_append_u8 (w, memc_cam[i].ppl))          goto fail;
	}

	/* memcpages[0x2000] — int per entry */
	for (i = 0; i < 0x2000; i++)
		if (!snapshot_writer_append_i32(w, (int32_t)memcpages[i]))    goto fail;

	return snapshot_writer_end_chunk(w);

fail:
	return 0;
}

int memc_load_state(snapshot_payload_reader_t *r, uint32_t version)
{
	int i;
	uint32_t loaded_memctrl, loaded_vinit, loaded_vstart, loaded_vend;
	uint32_t loaded_cinit, loaded_sstart, loaded_ssend, loaded_sptr;
	uint32_t loaded_spos, loaded_sendN, loaded_sstart2;
	int32_t  loaded_pagesize, loaded_sdmaena, loaded_bigcyc;
	int32_t  loaded_videodma_enable, loaded_refreshon, loaded_refresh_always;
	int32_t  loaded_nextvalid;
	int32_t  loaded_dma_sound_req, loaded_dma_video_req, loaded_dma_cursor_req;
	uint64_t loaded_dma_sound_req_ts, loaded_dma_video_req_ts;
	uint64_t loaded_dma_video_req_start_ts, loaded_dma_video_req_period;
	uint64_t loaded_dma_cursor_req_ts;

	(void)version;

	if (!snapshot_payload_reader_read_u32(r, &loaded_memctrl))        return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_pagesize))       return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_sdmaena))        return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_bigcyc))         return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_videodma_enable)) return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_refreshon))      return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_refresh_always)) return 0;

	if (!snapshot_payload_reader_read_u32(r, &loaded_vinit))   return 0;
	if (!snapshot_payload_reader_read_u32(r, &loaded_vstart))  return 0;
	if (!snapshot_payload_reader_read_u32(r, &loaded_vend))    return 0;
	if (!snapshot_payload_reader_read_u32(r, &loaded_cinit))   return 0;
	if (!snapshot_payload_reader_read_u32(r, &loaded_sstart))  return 0;
	if (!snapshot_payload_reader_read_u32(r, &loaded_ssend))   return 0;
	if (!snapshot_payload_reader_read_u32(r, &loaded_sptr))    return 0;
	if (!snapshot_payload_reader_read_u32(r, &loaded_spos))    return 0;
	if (!snapshot_payload_reader_read_u32(r, &loaded_sendN))   return 0;
	if (!snapshot_payload_reader_read_u32(r, &loaded_sstart2)) return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_nextvalid)) return 0;

	if (!snapshot_payload_reader_read_i32(r, &loaded_dma_sound_req))            return 0;
	if (!snapshot_payload_reader_read_u64(r, &loaded_dma_sound_req_ts))         return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_dma_video_req))            return 0;
	if (!snapshot_payload_reader_read_u64(r, &loaded_dma_video_req_ts))         return 0;
	if (!snapshot_payload_reader_read_u64(r, &loaded_dma_video_req_start_ts))   return 0;
	if (!snapshot_payload_reader_read_u64(r, &loaded_dma_video_req_period))     return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_dma_cursor_req))           return 0;
	if (!snapshot_payload_reader_read_u64(r, &loaded_dma_cursor_req_ts))        return 0;

	for (i = 0; i < 512; i++)
	{
		uint32_t logical_addr;
		uint8_t ppl;
		if (!snapshot_payload_reader_read_u32(r, &logical_addr)) return 0;
		if (!snapshot_payload_reader_read_u8 (r, &ppl))          return 0;
		memc_cam[i].logical_addr = logical_addr;
		memc_cam[i].ppl = ppl;
	}

	for (i = 0; i < 0x2000; i++)
	{
		int32_t v;
		if (!snapshot_payload_reader_read_i32(r, &v)) return 0;
		memcpages[i] = (int)v;
	}

	memctrl              = loaded_memctrl;
	pagesize             = (int)loaded_pagesize;
	sdmaena              = (int)loaded_sdmaena;
	bigcyc               = (int)loaded_bigcyc;
	memc_videodma_enable = (int)loaded_videodma_enable;
	memc_refreshon       = (int)loaded_refreshon;
	memc_refresh_always  = (int)loaded_refresh_always;

	vinit   = loaded_vinit;
	vstart  = loaded_vstart;
	vend    = loaded_vend;
	cinit   = loaded_cinit;
	sstart  = loaded_sstart;
	ssend   = loaded_ssend;
	sptr    = loaded_sptr;
	spos    = loaded_spos;
	sendN   = loaded_sendN;
	sstart2 = loaded_sstart2;
	nextvalid = (int)loaded_nextvalid;

	memc_dma_sound_req           = (int)loaded_dma_sound_req;
	memc_dma_sound_req_ts        = loaded_dma_sound_req_ts;
	memc_dma_video_req           = (int)loaded_dma_video_req;
	memc_dma_video_req_ts        = loaded_dma_video_req_ts;
	memc_dma_video_req_start_ts  = loaded_dma_video_req_start_ts;
	memc_dma_video_req_period    = loaded_dma_video_req_period;
	memc_dma_cursor_req          = (int)loaded_dma_cursor_req;
	memc_dma_cursor_req_ts       = loaded_dma_cursor_req_ts;

	return 1;
}

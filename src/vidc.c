/*Arculator 2.2 by Sarah Walker
  VIDC10 emulation*/
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#if WIN32
#define BITMAP __win_BITMAP
#include <windows.h>
#undef BITMAP
#endif
#include "arc.h"
#include "arm.h"
#include "config.h"
#include "debugger.h"
#include "ioc.h"
#include "keyboard.h"
#include "mem.h"
#include "memc.h"
#include "platform_shell.h"
#include "snapshot.h"
#include "snapshot_chunks.h"
#include "snapshot_subsystems.h"
#include "sound.h"
#include "timer.h"
#include "vidc.h"
#include "video.h"
#include "plat_video.h"

/*RISC OS 3 sets a total of 832 horizontal and 288 vertical for MODE 12. We use
  768x576 to get a 4:3 aspect ratio. This also allows MODEs 33-36 to display
  correctly*/
#define TV_X_MIN (197)
#define TV_X_MAX (TV_X_MIN+768)
#define TV_Y_MIN (23)
#define TV_Y_MAX (TV_Y_MIN+288)

/*TV horizontal settings for 12/24 MHz modes. Use 1152x576, scaled to 4:3*/
#define TV_X_MIN_24 (295)
#define TV_X_MAX_24 (TV_X_MIN_24+1152)

int display_mode;
int video_scale;
int video_fullscreen_scale;
int video_linear_filtering;
int video_black_level;

static uint32_t vidcr[64];

/* VIDC Control Register
   Bits 31-16: 11100000 XXXXXXXX
   Bits 15-14: Test mode (00 normal, 01 test mode 0, 10 test mode 1, 11 test mode 2)
   Bits 13-9: XXXXX
   Bit 8: Test mode (0 normal, 1 test mode 3)
   Bit 7: Composite sync (0 vsync, 1 csync)
   Bit 6: Interlace sync (0 interlace off, 1 interlace on)
   Bits 5-4: DMA request (00 end of word 0,4, 01 end of word 1,5, 10 end of word 2,6, 11 end of word 3,7)
   Bits 3-2: Bits per pixel (00 1bpp, 01 2bpp, 10 4bpp, 11 8bpp)
   Bits 1-0: Pixel rate (00 8MHz, 01 12MHz, 10 16MHz, 11 24MHz)
*/
#define VIDC_CR 0x38

static int soundhz;
int soundper;

int offsetx = 0, offsety = 0;
int fullscreen;
int fullborders,noborders;
int dblscan;


void clear(BITMAP *b)
{
	memset(b->dat, 0, b->w * b->h * 4);
}

BITMAP *create_bitmap(int x, int y)
{
	BITMAP *b = (BITMAP *)malloc(sizeof(BITMAP) + (y * sizeof(uint8_t *)));
	int c;
	b->dat = (uint8_t *)malloc(x * y * 4);
	for (c = 0; c < y; c++)
	{
		b->line[c] = b->dat + (c * x * 4);
	}
	b->w = x;
	b->h = y;
	clear(b);
	return b;
}

void destroy_bitmap(BITMAP *b)
{
	free(b->dat);
	free(b);
}

int vidc_dma_length;
extern int vidc_fetches;
int vidc_framecount = 0;
int vidc_displayon = 0;
int blitcount=0;
/*b - memory buffer*/
BITMAP *buffer;

int flyback;
int deskdepth;
int videodma=0;
int palchange;
uint32_t vidlookup[256];   /*Lookup table for 4bpp modes*/

int redrawpalette=0;

int oldflash;


struct
{
	uint32_t vtot,htot,vsync;
	int line;
	int displayon,borderon;
	uint32_t addr,caddr;
	int vbstart,vbend;
	int vdstart,vdend;
	int hbstart,hbend;
	int hdstart,hdend;
	int hdstart2,hdend2;
	uint32_t cr;
	int sync,inter;

	int horiz_length;
	int hsync_length;
	int front_porch_length;
	int display_length;
	int back_porch_length;

	int state;

	uint64_t pixel_time;
	uint64_t fetch_time; /*Time for one fetch (four words) to be consumed*/
	uint64_t initial_fetch_time;

	int cursor_lines;
	int first_line;

	/*Palette lookups - pal8 for 8bpp modes, pal for all others*/
	uint32_t pal[32],pal8[256];
	int cx,cys,cye,cxh;
	int scanrate;

	int in_display;
	int cyclesperline_display, cyclesperline_blanking;
	int cycles_per_fetch;
	int fetch_count;

	int clear_pending;

	int clock;

	int disp_len, disp_rate, disp_count;

	int disp_y_min, disp_y_max;
	int y_min, y_max;

	int border_was_disabled, display_was_disabled;

	int output_enable;

	emu_timer_t timer;

	void (*data_callback)(uint8_t *data, int pixels, int hsync_length, int resolution, void *p);
	void (*vsync_callback)(void *p, int state);
	void *callback_p;
} vidc;

enum
{
	VIDC_HSYNC = 0,
	VIDC_FRONT_PORCH,
	VIDC_DISPLAY,
	VIDC_BACK_PORCH
};

int vidc_getline()
{
//        if (vidc.scanrate) return vidc.line>>1;
	return vidc.line;
}
uint32_t monolook[16][4];
uint32_t hirescurcol[4]={0,0,0,0xFFFFFF};

void redolookup()
{
	int c;
	if (monitor_type == MONITOR_MONO)
	{
		for (c=0;c<16;c++)
		{
			monolook[c][0]=(vidcr[c]&1)?0xFFFFFF:0x000000;
			monolook[c][1]=(vidcr[c]&2)?0xFFFFFF:0x000000;
			monolook[c][2]=(vidcr[c]&4)?0xFFFFFF:0x000000;
			monolook[c][3]=(vidcr[c]&8)?0xFFFFFF:0x000000;
		}
	}
	switch (vidcr[VIDC_CR]&0xF) /*Control Register*/
	{
		case 2: /*Mode 0*/
		case 3: /*Mode 25*/
		vidlookup[0]=vidc.pal[0]|(vidc.pal[0]<<16);
		vidlookup[1]=vidc.pal[1]|(vidc.pal[0]<<16);
		vidlookup[2]=vidc.pal[0]|(vidc.pal[1]<<16);
		vidlookup[3]=vidc.pal[1]|(vidc.pal[1]<<16);
		break;
		case 6: /*Mode 8*/
		case 7: /*Mode 26*/
		for (c=0;c<16;c++)
		{
			vidlookup[c]=vidc.pal[c&0x3]|(vidc.pal[(c>>2)&0x3]<<16);
		}
		break;
		case 8: /*Mode 9*/
		case 9: /*Mode 48*/
		for (c=0;c<16;c++)
		{
			vidlookup[c]=vidc.pal[c&0xF]|(vidc.pal[c&0xF]<<16);
		}
		break;
		case 10: /*Mode 12*/
		case 11: /*Mode 27*/
		for (c=0;c<256;c++)
		{
			vidlookup[c]=vidc.pal[c&0xF]|(vidc.pal[(c>>4)&0xF]<<16);
		}
		break;
	}
}

void recalcse()
{
	int pixels_per_word;
	int disp_start, disp_end;

	switch (vidcr[VIDC_CR] & 3)
	{
		case 0: /*8MHz pixel rate*/
		vidc.pixel_time = (TIMER_USEC * 1000) / (vidc.clock / 3);
		break;
		case 1: /*12MHz pixel rate*/
		vidc.pixel_time = (TIMER_USEC * 1000) / (vidc.clock / 2);
		break;
		case 2: /*16MHz pixel rate*/
		vidc.pixel_time = (TIMER_USEC * 1000) / ((vidc.clock * 2) / 3);
		break;
		case 3: /*24MHz pixel rate*/
		vidc.pixel_time = (TIMER_USEC * 1000) / vidc.clock;
		break;
	}

/*                rpclog("pixel_time %016llx  %016llx %016llx\n", vidc.pixel_time,
			(TIMER_USEC * 1000) / vidc.clock,
			(TIMER_USEC * 1000) / ((vidc.clock * 2) / 3));*/

	switch (vidcr[VIDC_CR] & 0xC)
	{
		case 0xC: /*8bpp*/
		vidc.hdstart=(vidc.hdstart2<<1)+5;
		vidc.hdend=(vidc.hdend2<<1)+5;
		vidc.fetch_time = vidc.pixel_time * 4 * 4;
		pixels_per_word = 4;
		break;
		case 8: /*4bpp*/
		if (monitor_type == MONITOR_MONO)
		{
			vidc.hdstart=(vidc.hdstart2<<1)-14;
			vidc.hdend=(vidc.hdend2<<1)-14;
		}
		else
		{
			vidc.hdstart=(vidc.hdstart2<<1)+7;
			vidc.hdend=(vidc.hdend2<<1)+7;
		}
		vidc.fetch_time = vidc.pixel_time * 8 * 4;
		pixels_per_word = 8;
		break;
		case 4: /*2bpp*/
		vidc.hdstart=(vidc.hdstart2<<1)+11;
		vidc.hdend=(vidc.hdend2<<1)+11;
		vidc.fetch_time = vidc.pixel_time * 16 * 4;
		pixels_per_word = 16;
		break;
		case 0: /*1bpp*/
		default:
		vidc.hdstart=(vidc.hdstart2<<1)+19;
		vidc.hdend=(vidc.hdend2<<1)+19;
		vidc.fetch_time = vidc.pixel_time * 32 * 4;
		pixels_per_word = 32;
		break;
	}

	switch (vidcr[VIDC_CR] & 0x30) /*DMA Request*/
	{
		case 0x00: /*end of word 0, 4*/
		vidc.initial_fetch_time = (vidc.pixel_time * 4) * pixels_per_word;
		break;
		case 0x10: /*end of word 1, 5*/
		vidc.initial_fetch_time = (vidc.pixel_time * 5) * pixels_per_word;
		break;
		case 0x20: /*end of word 2, 6*/
		vidc.initial_fetch_time = (vidc.pixel_time * 6) * pixels_per_word;
		break;
		case 0x30: /*end of word 3, 7*/
		default:
		vidc.initial_fetch_time = (vidc.pixel_time * 7) * pixels_per_word;
		break;
	}

	memc_dma_video_req_period = vidc.fetch_time;
/*        rpclog("memc_dma_video_req_period=%016llx\n", memc_dma_video_req_period);*/

	vidc.horiz_length = (vidc.htot * 2) + 2;

	vidc.hsync_length = (vidc.sync * 2) + 2;
	vidc.front_porch_length = vidc.hdstart - vidc.hsync_length;

	if (vidc.hdstart < vidc.horiz_length)
		disp_start = vidc.hdstart;
	else
		disp_start = vidc.horiz_length;
	if (vidc.hdend < vidc.horiz_length)
		disp_end = vidc.hdend;
	else
		disp_end = vidc.horiz_length;
	vidc.display_length = disp_end - disp_start;
	vidc.back_porch_length = vidc.horiz_length - disp_end;

	if (vidc.hsync_length < 0)
		vidc.hsync_length = 0;
	if (vidc.front_porch_length < 0)
		vidc.front_porch_length = 0;
	if (vidc.display_length < 0)
		vidc.display_length = 0;
	if (vidc.back_porch_length < 0)
		vidc.back_porch_length = 0;

/*        rpclog("recalcse: horiz_length=%i  hsync_length=%i front_porch_length=%i display_length=%i back_port_length=%i\n",
		vidc.horiz_length,
		vidc.hsync_length, vidc.front_porch_length, vidc.display_length, vidc.back_porch_length);*/
}

static uint32_t vidc_make_colour(RGB r)
{
	if (video_black_level == BLACK_LEVEL_ACORN)
	{
		r.r = (MAX(r.r - 3, 0) * 255) / 12;
		r.g = (MAX(r.g - 3, 0) * 255) / 12;
		r.b = (MAX(r.b - 3, 0) * 255) / 12;
	}
	else
	{
		r.r |= r.r << 4;
		r.g |= r.g << 4;
		r.b |= r.b << 4;
	}

	return makecol(r.r, r.g, r.b);
}

void vidc_redopalette(void)
{
	for (int i = 0; i < 20; i++)
	{
		uint32_t v = vidcr[i];
		RGB r =
		{
			.b = (v & 0xf00) >> 8,
			.g = (v & 0xf0) >> 4,
			.r = v & 0xf
		};

		vidc.pal[i] = vidc_make_colour(r);
	}

	for (int i = 0; i < 256; i++)
	{
		uint32_t v = vidcr[i & 0xf];
		RGB r =
		{
			.b = (v & 0x700) >> 8,
			.g = (v & 0x30) >> 4,
			.r = v & 0x7
		};

		if (i & 0x10)
			r.r |= 8;
		if (i & 0x20)
			r.g |= 4;
		if (i & 0x40)
			r.g |= 8;
		if (i & 0x80)
			r.b |= 8;

		vidc.pal8[i] = vidc_make_colour(r);
	}

	palchange = 1;
}

void writevidc(uint32_t v)
{
//        char s[80];
	RGB r;
	int c,d;
	LOG_VIDC_REGISTERS("Write VIDC %08X (addr %02X<<2 or %02X/%02X, data %06X) with R15=%08X (PC=%08X)\n",
		v, v>>26, v>>24, (v>>24) & 0xFC, v & 0xFFFFFFul, armregs[15], PC);
	if (((v>>24)&~0x1F)==0x60)
	{
		stereoimages[((v>>26)-1)&7]=v&7;
//                rpclog("Stereo image write %08X %i %i\n",v,((v>>26)-1)&7,v&7);
	}
	if (((v>>26)<0x14) && (v!=vidcr[v>>26] || redrawpalette))
	{
/*                if ((v>>26)<0x10) rpclog("Write pal %08X\n", v);
		switch (v >> 26)
		{
			case  0: v = 0x00000000; break;
			case  1: v = 0x04000111; break;
			case  2: v = 0x08000222; break;
			case  3: v = 0x0C000333; break;
			case  4: v = 0x10000004; break;
			case  5: v = 0x14000115; break;
			case  6: v = 0x18000226; break;
			case  7: v = 0x1C000337; break;
			case  8: v = 0x20000400; break;
			case  9: v = 0x24000511; break;
			case 10: v = 0x28000622; break;
			case 11: v = 0x2C000733; break;
			case 12: v = 0x30000404; break;
			case 13: v = 0x34000515; break;
			case 14: v = 0x38000626; break;
			case 15: v = 0x3C000737; break;
		}*/
		vidcr[v >> 26] = v & 0x1fff;
		LOG_VIDC_REGISTERS("VIDC Write pal %08X %08X %08X\n",c,vidc.pal[(v>>26)&0x1F],v);
		vidc_redopalette();
		return;
	}
	vidcr[v>>26]=v;
	if ((v>>24)==0x80)
	{
		if (vidc.htot != ((v >> 14) & 0x3FF))
		{
			vidc.htot = (v >> 14) & 0x3FF;
			vidc_redovideotiming();
		}
		LOG_VIDC_REGISTERS("VIDC write htot = %d\n", vidc.htot);
	}
	if ((v>>24)==0xA0)
	{
		if (vidc.vtot != ((v >> 14) & 0x3FF) + 1)
		{
			int old_scanrate = vidc.scanrate;

			vidc.vtot = ((v >> 14) & 0x3FF) + 1;

			if (vidc.vtot >= 350)
				vidc.scanrate=1;
			else
				vidc.scanrate=0;

			if (old_scanrate != vidc.scanrate)
				vidc.clear_pending = 1;
		}
		LOG_VIDC_REGISTERS("VIDC write vtot = %d\n", vidc.vtot);
	}
	if ((v>>24)==0x84)
	{
		if (vidc.sync != ((v >> 14) & 0x3FF))
		{
			vidc.sync = (v >> 14) & 0x3FF;
		}
		LOG_VIDC_REGISTERS("VIDC write sync = %d\n", vidc.sync);
	}
	if ((v>>24)==0x88)
	{
		vidc.hbstart=(((v&0xFFFFFF)>>14)<<1)+1;
		LOG_VIDC_REGISTERS("VIDC write hbstart = %d\n", vidc.hbstart);
	}
	if ((v>>24)==0x8C)
	{
		vidc.hdstart2=((v&0xFFFFFF)>>14);
		recalcse();
		vidc_redovideotiming();
		LOG_VIDC_REGISTERS("VIDC write hdstart2 = %d\n", vidc.hdstart2);
	}
	if ((v>>24)==0x90)
	{
		vidc.hdend2=((v&0xFFFFFF)>>14);
		recalcse();
		vidc_redovideotiming();
		LOG_VIDC_REGISTERS("VIDC write hdend2 = %d\n", vidc.hdend2);
	}
	if ((v>>24)==0x94) vidc.hbend=(((v&0xFFFFFF)>>14)<<1)+1;
	if ((v>>24)==0x98) { vidc.cx=((v&0xFFE000)>>13)+6; vidc.cxh=((v&0xFFF800)>>11)+24; }
	if ((v>>24)==0x9C) vidc.inter = (v & 0xffc000) >> 13;
	if ((v>>24)==0xA4)
	{
		if (vidc.vsync != ((v >> 14) & 0x3FF) + 1)
		{
			vidc.vsync = ((v >> 14) & 0x3FF) + 1;
		}
	}
	if ((v>>24)==0xA8)
	{
		vidc.vbstart=((v&0xFFFFFF)>>14)+1;
	}
	if ((v>>24)==0xAC)
	{
		vidc.vdstart=((v&0xFFFFFF)>>14)+1;
	}
	if ((v>>24)==0xB0)
	{
		vidc.vdend=((v&0xFFFFFF)>>14)+1;
	}
	if ((v>>24)==0xB4)
	{
		vidc.vbend=((v&0xFFFFFF)>>14)+1;
	}
	if ((v>>24)==0xB8) vidc.cys=(v&0xFFC000);
	if ((v>>24)==0xBC) vidc.cye=(v&0xFFC000);
	if ((v>>24)==0xC0)
	{
		soundhz = 250000 / ((v & 0xff) + 2);
		soundper = ((v & 0xff) + 2) << 10;
		soundper = (soundper * 24000) / vidc.clock;

		sound_set_period((v & 0xff) + 2);

		LOG_VIDC_REGISTERS("Sound frequency write %08X period %i\n",v,soundper);
	}
	if ((v>>24)==0xE0)
	{
		vidc.cr = v & 0x00c1ff;
		recalcse();
		vidc_redovideotiming();
		LOG_VIDC_REGISTERS("VIDC write ctrl %08X\n", vidc.cr);
	}
//        printf("VIDC write %08X\n",v);
}

void clearbitmap()
{
	clear(buffer);
}

void initvid()
{
	buffer = create_bitmap(4096, 2048);
	vidc.line = 0;
	vidc.clock = 24000;
}

void redopalette()
{
	int c;
	redrawpalette=1;
	for (c=0;c<0x14;c++)
	{
		writevidc(vidcr[c]);
	}
	redrawpalette=0;
}

void setredrawall()
{
	clear(buffer);
}

void closevideo()
{
}

void reinitvideo()
{
	setredrawall();
	redopalette();
}

int getvidcline()
{
	return vidc.line;
}
int getvidcwidth()
{
	return vidc.htot;
}

void archline(uint8_t *bp, int x1, int y, int x2, uint32_t col)
{
	int x;
	for (x=x1;x<=x2;x++)
		((uint32_t *)bp)[x]=col;
}

static void vidc_poll(void *__p)
{
	int c;
	int mode;
//        int col=0;
	int x,xx;
	uint32_t temp;
	uint32_t *p;
	uint8_t *bp;
//        char s[256];
	int l = vidc.line;
	int xoffset,xoffset2;
	int do_double_scan = (!vidc.scanrate && !dblscan);

	if (do_double_scan)
		l <<= 1;

	if (output)
		rpclog("vidc_poll: state=%i line=%i\n", vidc.state, vidc.line);
	switch (vidc.state)
	{
		case VIDC_HSYNC:
		vidc.state = VIDC_FRONT_PORCH;
		timer_advance_u64(&vidc.timer, vidc.front_porch_length * vidc.pixel_time);
		break;

		case VIDC_FRONT_PORCH:
		vidc.state = VIDC_DISPLAY;
		timer_advance_u64(&vidc.timer, vidc.display_length * vidc.pixel_time);
		vidc.in_display = 1;
		break;

		case VIDC_DISPLAY:
		vidc.state = VIDC_BACK_PORCH;
		timer_advance_u64(&vidc.timer, vidc.back_porch_length * vidc.pixel_time);
		/*Delay next fetch until display starts again*/
		memc_dma_video_req_ts += ((vidc.back_porch_length + vidc.hsync_length + vidc.front_porch_length) * vidc.pixel_time);
		recalc_min_timer();
		vidc.in_display = 0;
		break;

		case VIDC_BACK_PORCH:
		vidc.state = VIDC_HSYNC;

		/*Clock vertical count*/
		if (vidc.line == vidc.vsync)
		{
			if (vidc.vsync_callback)
				vidc.vsync_callback(vidc.callback_p, 0);
		}
		if (vidc.line == vidc.vbstart && !vidc.border_was_disabled)
		{
			vidc.borderon = 1;
			flyback = 0;
			if (vidc.disp_y_min > l && vidc.displayon)
				vidc.disp_y_min = l + (do_double_scan ? 2 : 1);
		}
		if (vidc.line == vidc.vdstart && !vidc.display_was_disabled)
		{
//                        rpclog("VIDC addr %08X %08X\n",vinit,vidcr[VIDC_CR]);
			vidc.addr = vinit;
			vidc.caddr = cinit;

			/*First cursor DMA fetch at start of hsync before first display line*/
			memc_dma_cursor_req_ts = timer_get_ts(&vidc.timer);
			memc_dma_cursor_req = 1;
			/*First video DMA fetch at end of hsync before first display line.
			  Note that first DMA fetch is double length!*/
			memc_dma_video_req_ts = memc_dma_cursor_req_ts + (vidc.hsync_length * vidc.pixel_time);
			memc_dma_video_req_start_ts = memc_dma_video_req_ts + (vidc.front_porch_length * vidc.pixel_time);
			memc_dma_video_req = 2;
			vidc.cursor_lines = 2;
			vidc.first_line = 1;
			recalc_min_timer();

			vidc.displayon = vidc_displayon = 1;
			vidc.fetch_count = vidc.cycles_per_fetch;
			mem_dorefresh = memc_refresh_always;
			flyback = 0;
			if (vidc.disp_y_min > l && vidc.borderon)
				vidc.disp_y_min = l + (do_double_scan ? 2 : 1);
		}
		if (vidc.line == vidc.vdend)
		{
			vidc.displayon = vidc_displayon = 0;
			memc_dma_video_req = 0;
			mem_dorefresh = (memc_refreshon && !vidc_displayon) || memc_refresh_always;
			ioc_irqa(IOC_IRQA_VBLANK);
			flyback = 0x80;
			if (vidc.disp_y_max == -1)
				vidc.disp_y_max = l + (do_double_scan ? 2 : 1);
			vidc.display_was_disabled = 1;
			LOG_VIDEO_FRAMES("Normal vsync; speed %d%%, ins=%d, inscount=%d, PC=%08X\n", inssec, ins, inscount, PC);
		}
		if (vidc.line == vidc.vbend)
		{
			vidc.borderon = 0;
			if (vidc.disp_y_max == -1)
				vidc.disp_y_max = l + (do_double_scan ? 2 : 1);
			vidc.border_was_disabled = 1;
		}
		if (vidc.displayon && !vidc.cursor_lines)
		{
			/*Fetched cursor data used, request next fetch*/
			memc_dma_cursor_req = 1;
			vidc.cursor_lines = 2;
		}
		vidc.line++;
		LOG_VIDC_TIMING("++ vidc.line == %d\n", vidc.line);

		timer_advance_u64(&vidc.timer, vidc.hsync_length * vidc.pixel_time);
		break;
	}

	if (vidc.state != VIDC_BACK_PORCH)
		return;

	if (palchange)
	{
		redolookup();
		palchange=0;
	}

	videodma=vidc.addr;
	mode=(vidcr[VIDC_CR]&0xF);
	if (monitor_type == MONITOR_MONO)
		mode = 2;

	if (l>=0 && vidc.line<=1023 && l<1536)
	{
		int htot = (vidc.htot+1)*2;
		bp = (uint8_t *)buffer->line[l];
		if (!memc_videodma_enable)
		{
			if (vidc.borderon)
			{
				int hb_start = vidc.hbstart, hb_end = vidc.hbend;
				int hd_start = vidc.hdstart, hd_end = vidc.hdend;

				if (!(vidcr[VIDC_CR] & 2))
				{
					/*8MHz or 12MHz pixel rate*/
					hb_start *= 2;
					hb_end *= 2;
					hd_start *= 2;
					hd_end *= 2;
				}

				if (display_mode == DISPLAY_MODE_TV)
					archline(bp, TV_X_MIN, l, hb_start-1, 0);
				else
					archline(bp, 0, l, hb_start-1, 0);
				if (vidc.hdend > vidc.hbend || !vidc.displayon)
					archline(bp, hb_start, l, hb_end-1, vidc.pal[16]);
				else
				{
					archline(bp, hb_start, l, hd_start-1, vidc.pal[16]);
					archline(bp, hd_start, l, hd_end-1, 0);
					archline(bp, hd_end, l, hb_end-1, vidc.pal[16]);
				}
				if (display_mode == DISPLAY_MODE_TV)
					archline(bp, hb_end, l, TV_X_MAX-1, 0);
				else
					archline(bp, hb_end, l, htot, 0);

				if (l < vidc.y_min)
					vidc.y_min = l;
				if ((l+1) > vidc.y_max)
					vidc.y_max = l+1;
				if (l < vidc.disp_y_min)
					vidc.disp_y_min = l;
				if ((l+1) > vidc.disp_y_max)
					vidc.disp_y_max = l+1;
			}
			else
				archline(bp, 0, l, 1023, 0);
		}
		else
		{
			int xstart, xend;

			x=vidc.hbstart;
			if (vidc.hdstart>x) x=vidc.hdstart;
			xx=vidc.hbend;
			if (vidc.hdend<xx) xx=vidc.hdend;
			xoffset=xx-x;
			if (!(vidcr[VIDC_CR]&2))
			{
				/*8MHz or 12MHz pixel rate*/
				xoffset=200-(xoffset>>1);
				if (vidc.hdstart<vidc.hbstart) xoffset2=xoffset+(vidc.hdstart-vidc.hbstart);
				else                           xoffset2=xoffset;
				xoffset<<=1;
				xoffset2<<=1;

				xstart = vidc.hdstart*2;
				if (xstart > (vidc.htot+1)*4)
					xstart = (vidc.htot+1)*4;
				xend = vidc.hdend*2;
				if (xend > (vidc.htot+1)*4)
					xend = (vidc.htot+1)*4;
			}
			else
			{
				/*16MHz or 24MHz pixel rate*/
				xoffset=400-(xoffset>>1);
				if (vidc.hdstart<vidc.hbstart) xoffset2=xoffset+(vidc.hdstart-vidc.hbstart);
				else                           xoffset2=xoffset;

				xstart = vidc.hdstart;
				if (xstart > (vidc.htot+1)*2)
					xstart = (vidc.htot+1)*2;
				xend = vidc.hdend;
				if (xend > (vidc.htot+1)*2)
					xend = (vidc.htot+1)*2;
			}
			if (monitor_type == MONITOR_MONO)
				xoffset2 = 0;
			if (vidc.displayon)
			{
				switch (mode)
				{
					case 0: /*Mode 4: 320x256 8MHz 1bpp*/
					case 1: /*12MHz 1bpp*/
					for (x = xstart; x < xend; x += 32)
					{
						temp = ram[vidc.addr++];
						if (x < 4096)
						{
							for (xx = 0; xx < 64; xx += 2)
								((uint32_t *)bp)[x+xx] = ((uint32_t *)bp)[x+xx+1] = vidc.pal[(temp>>xx)&1];
						}
						if (vidc.addr == vend + 4)
							vidc.addr = vstart;
					}
					break;
					case 2: /*Mode 0: 640x256 16MHz 1bpp*/
					case 3: /*Mode 25: 640x480 24MHz 1bpp*/
					for (x = ((monitor_type == MONITOR_MONO) ? xstart*4 : xstart); x < ((monitor_type == MONITOR_MONO) ? xend*4 : xend); x += 32)
					{
						temp = ram[vidc.addr++];
						if (x < 4096)
						{
							if (monitor_type == MONITOR_MONO)
							{
								for (xx=0;xx<32;xx+=4)
								{
									((uint32_t *)bp)[x+xx]   = monolook[temp&0xF][0];
									((uint32_t *)bp)[x+xx+1] = monolook[temp&0xF][1];
									((uint32_t *)bp)[x+xx+2] = monolook[temp&0xF][2];
									((uint32_t *)bp)[x+xx+3] = monolook[temp&0xF][3];
									temp>>=4;
								}
							}
							else
							{
								for (xx=0;xx<32;xx++)
									((uint32_t *)bp)[x+xx] = vidc.pal[(temp>>xx)&1];
							}
//                                                        p += 32;
						}
						if (vidc.addr == vend + 4)
							vidc.addr = vstart;
					}
					break;
					case 4: /*Mode 1: 320x256 8MHz 2bpp*/
					case 5: /*12MHz 2bpp*/
					for (x = xstart; x < xend; x += 32)
					{
						temp = ram[vidc.addr++];
						if (x < 4096)
						{
							for (xx=0;xx<32;xx+=2)
								((uint32_t *)bp)[x+xx]=((uint32_t *)bp)[x+xx+1]=vidc.pal[(temp>>xx)&3];
						}
						if (vidc.addr == vend + 4)
							vidc.addr = vstart;
					}
					break;
					case 6: /*Mode 8: 640x256 16MHz 2bpp*/
					case 7: /*Mode 26: 640x480 24MHz 2bpp*/
					for (x = xstart; x < xend; x += 16)
					{
						temp = ram[vidc.addr++];
						if (x < 4096)
						{
							for (xx = 0; xx < 16; xx++)
								((uint32_t *)bp)[x+xx]=vidc.pal[temp>>(xx<<1)&3];
							p+=16;
						}
						if (vidc.addr == vend + 4)
							vidc.addr = vstart;
					}
					break;
					case 8: /*Mode 9: 320x256 8MHz 4bpp*/
					case 9: /*12MHz 4bpp*/
					for (x = xstart; x < xend; x += 16)
					{
						temp = ram[vidc.addr++];
						if (x < 4096)
						{
							for (c = 0; c < 16; c += 2)
								((uint32_t *)bp)[x+c] = ((uint32_t *)bp)[x+c+1] = vidc.pal[(temp>>(c<<1))&0xF];
						}
						if (vidc.addr == vend + 4)
							vidc.addr = vstart;
					}
					break;
					case 10: /*Mode 12: 640x256 16MHz 4bpp*/
					case 11: /*Mode 27: 640x480 24MHz 4bpp*/
					for (x = xstart; x < xend; x += 8)
					{
						temp = ram[vidc.addr++];
						if (x < 4096)
						{
							for (c = 0; c < 8; c++)
								((uint32_t *)bp)[x+c]=vidc.pal[(temp>>(c<<2))&0xF];
							p+=8;
						}
						if (vidc.addr==vend+4) vidc.addr=vstart;
					}
					break;
					case 12: /*Mode 13: 320x256 8bpp*/
					case 13: /*12MHz 8bpp*/
					for (x = xstart; x < xend/*vidc.hdend*2*/; x += 8)
					{
						temp=ram[vidc.addr++];
						if (x < 4096)
						{
							((uint32_t *)bp)[x]=((uint32_t *)bp)[x+1]=vidc.pal8[temp&0xFF];
							((uint32_t *)bp)[x+2]=((uint32_t *)bp)[x+3]=vidc.pal8[(temp>>8)&0xFF];
							((uint32_t *)bp)[x+4]=((uint32_t *)bp)[x+5]=vidc.pal8[(temp>>16)&0xFF];
							((uint32_t *)bp)[x+6]=((uint32_t *)bp)[x+7]=vidc.pal8[(temp>>24)&0xFF];
						}
						if (vidc.addr==vend+4) vidc.addr=vstart;
					}
					break;
					case 14: /*Mode 15: 640x256 16MHz 8bpp*/
					case 15: /*Mode 28: 640x480 24MHz 8bpp*/
					for (x = xstart; x < xend; x += 4)
					{
						temp = ram[vidc.addr++];
						if (x < 4096)
						{
							((uint32_t *)bp)[x]   = vidc.pal8[temp&0xFF];
							((uint32_t *)bp)[x+1] = vidc.pal8[(temp>>8)&0xFF];
							((uint32_t *)bp)[x+2] = vidc.pal8[(temp>>16)&0xFF];
							((uint32_t *)bp)[x+3] = vidc.pal8[(temp>>24)&0xFF];
						}
						if (vidc.addr == vend + 4)
							vidc.addr = vstart;
					}
					break;
				}

				switch (mode)
				{
					case 0: /*Mode 4*/
					case 1:
					case 4: /*Mode 1*/
					case 5:
					case 8: /*Mode 9*/
					case 9:
					case 12: /*Mode 13*/
					case 13:
					if (vidc.hbstart<vidc.hdstart)
					{
						if (display_mode == DISPLAY_MODE_TV)
							archline(bp, TV_X_MIN, l, (vidc.hdstart*2)-1, 0);
						archline(bp, vidc.hbstart*2, l, (vidc.hdstart*2)-1, vidc.pal[0x10]);
					}
					else
					{
						if (display_mode == DISPLAY_MODE_TV)
							archline(bp, TV_X_MIN, l, (vidc.hbstart*2)-1, 0);
					}
					if (vidc.hbend > vidc.hdend)
					{
						archline(bp, vidc.hdend*2, l, vidc.hbend*2, vidc.pal[0x10]);
						if (display_mode == DISPLAY_MODE_TV)
							archline(bp, vidc.hbend*2, l, TV_X_MAX-1, 0);
					}
					else
					{
						if (display_mode == DISPLAY_MODE_TV)
							archline(bp, vidc.hbend*2, l, TV_X_MAX-1, 0);
					}
					if (htot > MAX(vidc.hbend, vidc.hdend))
						archline(bp, MAX(vidc.hbend*2, vidc.hdend*2), l, htot*2, 0);
					break;
					case 2:  /*Mode 0*/
					case 3:  /*Mode 25*/
					case 6:  /*Mode 8*/
					case 7:  /*Mode 26*/
					case 10: /*Mode 12*/
					case 11: /*Mode 27*/
					case 14: /*Mode 15*/
					case 15: /*Mode 28*/
					if (monitor_type == MONITOR_MONO)
						break;
					archline(bp, 0, l, MIN(vidc.hbstart, vidc.hdstart)-1, 0);
					if (vidc.hbstart < vidc.hdstart)
					{
						if (display_mode == DISPLAY_MODE_TV)
							archline(bp, TV_X_MIN, l, vidc.hbstart-1, 0);
						archline(bp, vidc.hbstart, l, vidc.hdstart-1, vidc.pal[0x10]);
					}
					else
					{
						if (display_mode == DISPLAY_MODE_TV)
							archline(bp, TV_X_MIN, l, vidc.hbstart-1, 0);
					}
					if (vidc.hbend > vidc.hdend)
					{
						archline(bp, vidc.hdend, l, vidc.hbend, vidc.pal[0x10]);
						if (display_mode == DISPLAY_MODE_TV)
							archline(bp, vidc.hbend, l, TV_X_MAX-1, 0);
					}
					else
					{
						if (display_mode == DISPLAY_MODE_TV)
							archline(bp, vidc.hbend, l, TV_X_MAX-1, 0);
					}
					if (htot > MAX(vidc.hbend, vidc.hdend))
						archline(bp, MAX(vidc.hbend, vidc.hdend), l, htot, 0);
					break;
				}

				if (((vidc.cys>>14)+2)<=vidc.line && ((vidc.cye>>14)+2)>vidc.line)
				{
					if (monitor_type == MONITOR_MONO)
					{
						x = (vidc.cx << 2) - 80;
						temp = ram[vidc.caddr++];
						for (xx = 0; xx < 64; xx += 4)
						{
							if (temp & 3)
								((uint32_t *)bp)[x+xx]   = ((uint32_t *)bp)[x+xx+1] =
								((uint32_t *)bp)[x+xx+2] = ((uint32_t *)bp)[x+xx+3] = hirescurcol[temp&3];
							temp>>=2;
						}
						temp = ram[vidc.caddr++];
						for (xx = 64; xx < 128; xx += 4)
						{
							if (temp & 3)
								((uint32_t *)bp)[x+xx]   = ((uint32_t *)bp)[x+xx+1] =
								((uint32_t *)bp)[x+xx+2] = ((uint32_t *)bp)[x+xx+3] = hirescurcol[temp&3];
							temp>>=2;
						}
					}
					else switch (vidcr[VIDC_CR]&0xF)
					{
						case 0: /*Mode 4*/
						case 1:
						case 4: /*Mode 1*/
						case 5:
						case 8: /*Mode 9*/
						case 9:
						case 12: /*Mode 13*/
						case 13:
						x = vidc.cx << 1;//((vidc.cx-vidc.hdstart)<<1)+xoffset2;
						if (x > (2048 - 32*2))
							break;
						temp=ram[vidc.caddr++];
						for (xx=0;xx<32;xx+=2)
						{
							if (temp&3) ((uint32_t *)bp)[x+xx]=((uint32_t *)bp)[x+xx+1]=vidc.pal[(temp&3)|0x10];
							temp>>=2;
						}
						temp=ram[vidc.caddr++];
						for (xx=32;xx<64;xx+=2)
						{
							if (temp&3) ((uint32_t *)bp)[x+xx]=((uint32_t *)bp)[x+xx+1]=vidc.pal[(temp&3)|0x10];
							temp>>=2;
						}
						break;

						case 2:  /*Mode 0*/
						case 3:  /*Mode 25*/
						case 6:  /*Mode 8*/
						case 7:  /*Mode 26*/
						case 10: /*Mode 12*/
						case 11: /*Mode 27*/
						case 14: /*Mode 15*/
						case 15: /*Mode 28*/
						x = vidc.cx;//(vidc.cx-vidc.hdstart)+xoffset2;
						if (x > (2048-32))
							break;
						temp=ram[vidc.caddr++];
						for (xx=0;xx<16;xx++)
						{
							if (temp&3) ((uint32_t *)bp)[x+xx]=vidc.pal[(temp&3)|0x10];
							temp>>=2;
						}
						temp=ram[vidc.caddr++];
						for (xx=16;xx<32;xx++)
						{
							if (temp&3) ((uint32_t *)bp)[x+xx]=vidc.pal[(temp&3)|0x10];
							temp>>=2;
						}
						break;
					}
				}
			}
			if (vidc.borderon && !vidc.displayon)
			{
				int hb_start = vidc.hbstart, hb_end = vidc.hbend;

				if (!(vidcr[VIDC_CR] & 2))
				{
					hb_start *= 2;
					hb_end *= 2;
				}

				if (display_mode == DISPLAY_MODE_TV)
					archline(bp, TV_X_MIN, l, hb_start-1, 0);
				else
					archline(bp, 0, l, hb_start-1, 0);
				archline(bp, hb_start, l, hb_end-1, vidc.pal[16]);
				if (display_mode == DISPLAY_MODE_TV)
					archline(bp, hb_end, l, TV_X_MAX-1, 0);
				else
					archline(bp, hb_end, l, htot, 0);
			}
			if (!vidc.borderon && vidc.displayon)
				archline(bp,0,l,MAX(1023,htot),0);
			if (!vidc.borderon && !vidc.displayon)
				archline(bp,0,l,MAX(1023,htot),0);
			if (vidc.borderon && l < vidc.y_min)
				vidc.y_min = l;
			if (vidc.borderon && (l+1) > vidc.y_max)
				vidc.y_max = l+1;
		}
	}
	else if (display_mode == DISPLAY_MODE_TV && l >= TV_Y_MIN && l < TV_Y_MAX)
		archline(buffer->line[l], TV_X_MIN, l, TV_X_MAX-1, 0);
	else
	{
		int htot = (vidc.htot+1)*2;

		archline(buffer->line[l], 0, l, htot, 0);
	}
	if (vidc.data_callback)
	{
		uint8_t out_data[4096];

		/*Extract red nibble for full scanline to send to attached device*/
		if (l >= 0)
		{
			if (mode & 2)
			{
				int pixels = (vidc.htot+1)*2;
				for (x = 0; x < pixels; x++)
					out_data[x] = (((uint32_t *)buffer->line[l])[x] >> 20) & 0x1f;
			}
			else
			{
				int pixels = (vidc.htot+1)*4;
				for (x = 0; x < pixels; x += 2)
					out_data[x>>1] = (((uint32_t *)buffer->line[l])[x] >> 20) & 0x1f;
			}
		}
		else
			memset(out_data, 0, (vidc.htot+1)*2);

		vidc.data_callback(out_data, (vidc.htot+1)*2, (vidc.sync+1)*2, !(mode & 2), vidc.callback_p);
	}

	if (vidc.line>=vidc.vtot)
	{
		LOG_VIDEO_FRAMES("Frame over!  vidc.line=%d, vidc.vtot=%d\n", vidc.line, vidc.vtot);
		if (vidc.displayon)
		{
			vidc.displayon = vidc_displayon = 0;
			mem_dorefresh = (memc_refreshon && !vidc_displayon) || memc_refresh_always;
			ioc_irqa(IOC_IRQA_VBLANK);
			flyback=0x80;
			vidc.disp_y_max = l;
//                        rpclog("Late vsync\n");
		}

		oldflash=readflash[0]|readflash[1]|readflash[2]|readflash[3];

		if (vidc.output_enable)
		{
			if ((display_mode == DISPLAY_MODE_NO_BORDERS) || (monitor_type == MONITOR_MONO))
			{
				int hd_start = (vidc.hbstart > vidc.hdstart) ? vidc.hbstart : vidc.hdstart;
				int hd_end = (vidc.hbend < vidc.hdend) ? vidc.hbend : vidc.hdend;
				int height = vidc.disp_y_max - vidc.disp_y_min;

				if (monitor_type == MONITOR_MONO)
				{
					hd_start = vidc.hdstart * 4;
					hd_end = vidc.hdend * 4;
				}
				else if (!(vidcr[VIDC_CR] & 2))
				{
					hd_start *= 2;
					hd_end *= 2;
				}

				if (vidc.scanrate || !dblscan)
				{
					LOG_VIDEO_FRAMES("PRESENT: normal display\n");
					updatewindowsize(hd_end-hd_start, height);
					video_renderer_update(buffer, hd_start, vidc.disp_y_min, 0, 0, hd_end-hd_start, height);
					video_renderer_present(0, 0, hd_end-hd_start, height, 0);
				}
				else
				{
					LOG_VIDEO_FRAMES("PRESENT: line doubled");
					updatewindowsize(hd_end-hd_start, height * 2);
					video_renderer_update(buffer, hd_start, vidc.disp_y_min, 0, 0, hd_end-hd_start, height);
					video_renderer_present(0, 0, hd_end-hd_start, height, 1);
				}
			}
			else if (display_mode == DISPLAY_MODE_NATIVE_BORDERS)
			{
				LOG_VIDEO_FRAMES("BLIT: fullborders|fullscreen\n");
				int hb_start = vidc.hbstart;
				int hb_end = vidc.hbend;

				if (!(vidcr[VIDC_CR] & 2))
				{
					hb_start *= 2;
					hb_end *= 2;
				}

				if (vidc.scanrate || !dblscan)
				{
					LOG_VIDEO_FRAMES("UPDATE AND PRESENT: fullborders|fullscreen no doubling\n");
					updatewindowsize(hb_end-hb_start, vidc.y_max-vidc.y_min);
					video_renderer_update(buffer, hb_start, vidc.y_min, 0, 0, hb_end-hb_start, vidc.y_max-vidc.y_min);
					video_renderer_present(0, 0, hb_end-hb_start, vidc.y_max-vidc.y_min, 0);
				}
				else
				{
					LOG_VIDEO_FRAMES("UPDATE AND PRESENT: fullborders|fullscreen + doubling\n");
					updatewindowsize(hb_end-hb_start, (vidc.y_max-vidc.y_min) * 2);
					video_renderer_update(buffer, hb_start, vidc.y_min, 0, 0, hb_end-hb_start, vidc.y_max-vidc.y_min);
					video_renderer_present(0, 0, hb_end-hb_start, vidc.y_max-vidc.y_min, 1);
				}
			}
			else
			{
				LOG_VIDEO_FRAMES("BLIT: !(fullborders|fullscreen) dblscan=%d VIDC_CR=%08X\n", dblscan, vidcr[VIDC_CR]);
				updatewindowsize(TV_X_MAX-TV_X_MIN, (TV_Y_MAX-TV_Y_MIN)*2);
				if (vidcr[VIDC_CR] & 1)
				{
					if (dblscan)
					{
						video_renderer_update(buffer, TV_X_MIN_24, TV_Y_MIN, 0, 0, TV_X_MAX_24-TV_X_MIN_24, TV_Y_MAX-TV_Y_MIN);
						video_renderer_present(0, 0, TV_X_MAX_24-TV_X_MIN_24, TV_Y_MAX-TV_Y_MIN, 1);
					}
					else
					{
						video_renderer_update(buffer, TV_X_MIN_24, TV_Y_MIN*2, 0, 0, TV_X_MAX_24-TV_X_MIN_24, (TV_Y_MAX-TV_Y_MIN)*2);
						video_renderer_present(0, 0, TV_X_MAX_24-TV_X_MIN_24, (TV_Y_MAX-TV_Y_MIN)*2, 0);
					}
				}
				else
				{
					if (dblscan)
					{
						video_renderer_update(buffer, TV_X_MIN, TV_Y_MIN, 0, 0, TV_X_MAX-TV_X_MIN, TV_Y_MAX-TV_Y_MIN);
						video_renderer_present(0, 0, TV_X_MAX-TV_X_MIN, TV_Y_MAX-TV_Y_MIN, 1);
					}
					else
					{
						video_renderer_update(buffer, TV_X_MIN, TV_Y_MIN*2, 0, 0, TV_X_MAX-TV_X_MIN, (TV_Y_MAX-TV_Y_MIN)*2);
						video_renderer_present(0, 0, TV_X_MAX-TV_X_MIN, (TV_Y_MAX-TV_Y_MIN)*2, 0);
					}
				}
			}

			vidc.y_min = 9999;
			vidc.y_max = 0;
			vidc.disp_y_min = 9999;
			vidc.disp_y_max = -1;

			/*Clear the buffer now so we don't get a persistent ghost when changing
			  from a high vertical res mode to a line-doubled mode.*/
			if (vidc.clear_pending)
			{
				vidc.clear_pending = 0;
				clear(buffer);
			}
		}

		vidc.line=0;
		if (vidc.vsync_callback)
			vidc.vsync_callback(vidc.callback_p, 1);
		vidc.border_was_disabled = 0;
		vidc.display_was_disabled = 0;
//                rpclog("%i fetches\n", vidc_fetches);
		vidc_fetches = 0;
		vidc_framecount++;

/*                rpclog("htot=%i hswr=%i hbsr=%i hdsr=%i hder=%i hber=%i\n",
				vidc.htot, vidc.sync, vidc.hbstart, vidc.hdstart, vidc.hdend, vidc.hbend);
		rpclog("vtot=%i vswr=%i vbsr=%i vdsr=%i vder=%i vber=%i cr=%08x\n",
				vidc.vtot, vidc.vsync, vidc.vbstart,
				vidc.vdstart, vidc.vdend, vidc.vbend, vidcr[VIDC_CR]);*/
	}
}

void vidc_redovideotiming()
{
	vidc.cyclesperline_display = vidc.cyclesperline_blanking = 0;
}

void vidc_setclock(int clock)
{
	switch (clock)
	{
		case 0:
		vidc.clock = 24000;
		break;
		case 1:
		vidc.clock = 25175;
		break;
		case 2:
		vidc.clock = 36000;
		break;
	}
	sound_set_clock((vidc.clock * 1000) / 24);
	recalcse();
}

void vidc_setclock_direct(int clock)
{
	vidc.clock = clock;
	sound_set_clock((vidc.clock * 1000) / 24);
	recalcse();
}

int vidc_getclock()
{
	return vidc.clock;
}

int vidc_get_hs()
{
	/*Not quite horizontal sync pulse, but good enough for monitor ID detection*/
	return vidc.in_display;
}

void vidc_reset()
{
	timer_add(&vidc.timer, vidc_poll, NULL, 1);
	vidc_setclock(0);
	sound_set_period(255);
	recalcse();
	vidc_output_enable(1);
	vidc.data_callback = NULL;
	vidc.vsync_callback = NULL;
}


void vidc_attach(void (*vidc_data)(uint8_t *data, int pixels, int hsync_length, int resolution, void *p), void (*vidc_vsync)(void *p, int state), void *p)
{
	vidc.data_callback = vidc_data;
	vidc.vsync_callback = vidc_vsync;
	vidc.callback_p = p;
}

void vidc_output_enable(int ena)
{
	vidc.output_enable = ena;
}

uint32_t vidc_get_current_vaddr(void)
{
	return vidc.addr;
}
uint32_t vidc_get_current_caddr(void)
{
	return vidc.caddr;
}

static const int pixel_rates[4] = {8, 12, 16, 24};
static const char *stereo_images[8] =
{
	"Undefined ", "100% left ", "83% left  ", "67% left  ",
	"Centre    ", "67% right ", "83% right ", "100% right"
};

void vidc_debug_print(char *s)
{
	sprintf(s, "VIDC registers :\n"
		   " Horizontal cycle        =%4i   Vertical cycle        =%4i\n"
		   " Horizontal sync width   =%4i   Vertical sync width   =%4i\n"
		   " Horizontal border start =%4i   Vertical border start =%4i\n"
		   " Horizontal display start=%4i   Vertical display start=%4i\n"
		   " Horizontal display end  =%4i   Vertical display end  =%4i\n"
		   " Horizontal border end   =%4i   Vertical border end   =%4i\n"
		   " Horizontal cursor start =%4i   Vertical cursor start =%4i\n"
		   "                                 Vertical cursor end   =%4i\n"
		   " Interlace=%4i\n"
		   " Sound period=%i  frequency=%i kHz\n"
		   " Control=%x\n"
		   "   Pixel rate=%g MHz\n"
		   "   Bits per pixel=%i\n"
		   "   DMA request=end of word %i,%i\n"
		   "   Interlace sync %s\n"
		   "   %s sync\n"
		   " Input clock=%g MHz\n\n",
		   vidc.htot*2 + 2, vidc.vtot,
		   vidc.sync*2 + 2, vidc.vsync,
		   vidc.hbstart, vidc.vbstart,
		   vidc.hdstart, vidc.vdstart,
		   vidc.hdend, vidc.vdend,
		   vidc.hbend, vidc.vbend,
		   vidc.cx, vidc.cys >> 14,
		   vidc.cye >> 14,
		   vidc.inter,
		   (vidcr[0xc0 >> 2] & 0xff) + 2,
		   ((vidc.clock * 1000) / 24) / ((vidcr[0xc0 >> 2] & 0xff) + 2),
		   vidc.cr,
		   (double)((vidc.clock * pixel_rates[vidc.cr & 3]) / 24) / 1000.0,
		   1 << ((vidc.cr >> 2) & 3),
		   (vidc.cr >> 4) & 3, 4 + ((vidc.cr >> 4) & 3),
		   (vidc.cr & (1 << 6)) ? "on" : "off",
		   (vidc.cr & (1 << 7)) ? "Composite" : "Vertical",
		   (double)vidc.clock / 1000.0);
	debug_out(s);

	sprintf(s, "Palette :\n"
		   " [0]=%04x [1]=%04x [2]=%04x [3]=%04x [4]=%04x [5]=%04x [6]=%04x [7]=%04x\n"
		   " [8]=%04x [9]=%04x [a]=%04x [b]=%04x [c]=%04x [d]=%04x [e]=%04x [f]=%04x\n"
		   " Border=%04x  Cursor[1]=%04x  Cursor[2]=%04x  Cursor[3]=%04x\n\n"
		   "Stereo images :\n"
		   " [0]=%s [1]=%s [2]=%s [3]=%s\n"
		   " [4]=%s [5]=%s [6]=%s [7]=%s\n\n",
		   vidcr[0], vidcr[1], vidcr[2], vidcr[3], vidcr[4], vidcr[5], vidcr[6], vidcr[7],
		   vidcr[8], vidcr[9], vidcr[10], vidcr[11], vidcr[12], vidcr[13], vidcr[14], vidcr[15],
		   vidcr[16], vidcr[17], vidcr[18], vidcr[19],
		   stereo_images[stereoimages[0]], stereo_images[stereoimages[1]],
		   stereo_images[stereoimages[2]], stereo_images[stereoimages[3]],
		   stereo_images[stereoimages[4]], stereo_images[stereoimages[5]],
		   stereo_images[stereoimages[6]], stereo_images[stereoimages[7]]);
}

/* ----- Snapshot save/load -------------------------------------------- *
 *
 * vidcr[64] is the on-the-wire register file. The pal[]/pal8[] and
 * vidlookup[] arrays are derived state and get rebuilt by
 * vidc_redopalette() / redolookup() during the load. The line callback
 * timer is restored via timer_restore().
 */

#define VIDC_STATE_VERSION 1u

int vidc_save_state(snapshot_writer_t *w)
{
	int i;

	if (!snapshot_writer_begin_chunk(w, ARCSNAP_CHUNK_VIDC, VIDC_STATE_VERSION))
		return 0;

	/* Register cache */
	for (i = 0; i < 64; i++)
		if (!snapshot_writer_append_u32(w, vidcr[i])) goto fail;

	/* Top-level VIDC outputs that are reachable from outside the file */
	if (!snapshot_writer_append_i32(w, vidc_dma_length))   goto fail;
	if (!snapshot_writer_append_i32(w, vidc_framecount))   goto fail;
	if (!snapshot_writer_append_i32(w, vidc_displayon))    goto fail;
	if (!snapshot_writer_append_i32(w, soundhz))           goto fail;
	if (!snapshot_writer_append_i32(w, soundper))          goto fail;
	if (!snapshot_writer_append_i32(w, flyback))           goto fail;
	if (!snapshot_writer_append_i32(w, videodma))          goto fail;
	if (!snapshot_writer_append_i32(w, palchange))         goto fail;
	if (!snapshot_writer_append_i32(w, redrawpalette))     goto fail;
	if (!snapshot_writer_append_i32(w, oldflash))          goto fail;

	/* The static vidc struct: timing/DMA/state-machine fields */
	if (!snapshot_writer_append_u32(w, vidc.vtot))             goto fail;
	if (!snapshot_writer_append_u32(w, vidc.htot))             goto fail;
	if (!snapshot_writer_append_u32(w, vidc.vsync))            goto fail;
	if (!snapshot_writer_append_i32(w, vidc.line))             goto fail;
	if (!snapshot_writer_append_i32(w, vidc.displayon))        goto fail;
	if (!snapshot_writer_append_i32(w, vidc.borderon))         goto fail;
	if (!snapshot_writer_append_u32(w, vidc.addr))             goto fail;
	if (!snapshot_writer_append_u32(w, vidc.caddr))            goto fail;
	if (!snapshot_writer_append_i32(w, vidc.vbstart))          goto fail;
	if (!snapshot_writer_append_i32(w, vidc.vbend))            goto fail;
	if (!snapshot_writer_append_i32(w, vidc.vdstart))          goto fail;
	if (!snapshot_writer_append_i32(w, vidc.vdend))            goto fail;
	if (!snapshot_writer_append_i32(w, vidc.hbstart))          goto fail;
	if (!snapshot_writer_append_i32(w, vidc.hbend))            goto fail;
	if (!snapshot_writer_append_i32(w, vidc.hdstart))          goto fail;
	if (!snapshot_writer_append_i32(w, vidc.hdend))            goto fail;
	if (!snapshot_writer_append_i32(w, vidc.hdstart2))         goto fail;
	if (!snapshot_writer_append_i32(w, vidc.hdend2))           goto fail;
	if (!snapshot_writer_append_u32(w, vidc.cr))               goto fail;
	if (!snapshot_writer_append_i32(w, vidc.sync))             goto fail;
	if (!snapshot_writer_append_i32(w, vidc.inter))            goto fail;
	if (!snapshot_writer_append_i32(w, vidc.horiz_length))     goto fail;
	if (!snapshot_writer_append_i32(w, vidc.hsync_length))     goto fail;
	if (!snapshot_writer_append_i32(w, vidc.front_porch_length)) goto fail;
	if (!snapshot_writer_append_i32(w, vidc.display_length))   goto fail;
	if (!snapshot_writer_append_i32(w, vidc.back_porch_length)) goto fail;
	if (!snapshot_writer_append_i32(w, vidc.state))            goto fail;
	if (!snapshot_writer_append_u64(w, vidc.pixel_time))       goto fail;
	if (!snapshot_writer_append_u64(w, vidc.fetch_time))       goto fail;
	if (!snapshot_writer_append_u64(w, vidc.initial_fetch_time)) goto fail;
	if (!snapshot_writer_append_i32(w, vidc.cursor_lines))     goto fail;
	if (!snapshot_writer_append_i32(w, vidc.first_line))       goto fail;
	if (!snapshot_writer_append_i32(w, vidc.cx))               goto fail;
	if (!snapshot_writer_append_i32(w, vidc.cys))              goto fail;
	if (!snapshot_writer_append_i32(w, vidc.cye))              goto fail;
	if (!snapshot_writer_append_i32(w, vidc.cxh))              goto fail;
	if (!snapshot_writer_append_i32(w, vidc.scanrate))         goto fail;
	if (!snapshot_writer_append_i32(w, vidc.in_display))       goto fail;
	if (!snapshot_writer_append_i32(w, vidc.cyclesperline_display))  goto fail;
	if (!snapshot_writer_append_i32(w, vidc.cyclesperline_blanking)) goto fail;
	if (!snapshot_writer_append_i32(w, vidc.cycles_per_fetch)) goto fail;
	if (!snapshot_writer_append_i32(w, vidc.fetch_count))      goto fail;
	if (!snapshot_writer_append_i32(w, vidc.clear_pending))    goto fail;
	if (!snapshot_writer_append_i32(w, vidc.clock))            goto fail;
	if (!snapshot_writer_append_i32(w, vidc.disp_len))         goto fail;
	if (!snapshot_writer_append_i32(w, vidc.disp_rate))        goto fail;
	if (!snapshot_writer_append_i32(w, vidc.disp_count))       goto fail;
	if (!snapshot_writer_append_i32(w, vidc.disp_y_min))       goto fail;
	if (!snapshot_writer_append_i32(w, vidc.disp_y_max))       goto fail;
	if (!snapshot_writer_append_i32(w, vidc.y_min))            goto fail;
	if (!snapshot_writer_append_i32(w, vidc.y_max))            goto fail;
	if (!snapshot_writer_append_i32(w, vidc.border_was_disabled))  goto fail;
	if (!snapshot_writer_append_i32(w, vidc.display_was_disabled)) goto fail;
	if (!snapshot_writer_append_i32(w, vidc.output_enable))    goto fail;

	/* Embedded line timer */
	if (!snapshot_writer_append_u32(w, vidc.timer.ts_integer)) goto fail;
	if (!snapshot_writer_append_u32(w, vidc.timer.ts_frac))    goto fail;
	if (!snapshot_writer_append_i32(w, vidc.timer.enabled))    goto fail;

	return snapshot_writer_end_chunk(w);

fail:
	return 0;
}

int vidc_load_state(snapshot_payload_reader_t *r, uint32_t version)
{
	int i;
	uint32_t loaded_vidcr[64];
	int32_t  loaded_dma_length, loaded_framecount, loaded_displayon_top;
	int32_t  loaded_soundhz, loaded_soundper, loaded_flyback, loaded_videodma;
	int32_t  loaded_palchange, loaded_redrawpalette, loaded_oldflash;
	uint32_t loaded_vtot, loaded_htot, loaded_vsync, loaded_addr, loaded_caddr, loaded_cr;
	int32_t  loaded_line, loaded_displayon_inner, loaded_borderon;
	int32_t  loaded_vbstart, loaded_vbend, loaded_vdstart, loaded_vdend;
	int32_t  loaded_hbstart, loaded_hbend, loaded_hdstart, loaded_hdend;
	int32_t  loaded_hdstart2, loaded_hdend2, loaded_sync, loaded_inter;
	int32_t  loaded_horiz_length, loaded_hsync_length, loaded_front_porch_length;
	int32_t  loaded_display_length, loaded_back_porch_length, loaded_state;
	uint64_t loaded_pixel_time, loaded_fetch_time, loaded_initial_fetch_time;
	int32_t  loaded_cursor_lines, loaded_first_line;
	int32_t  loaded_cx, loaded_cys, loaded_cye, loaded_cxh, loaded_scanrate;
	int32_t  loaded_in_display, loaded_cyclesperline_display, loaded_cyclesperline_blanking;
	int32_t  loaded_cycles_per_fetch, loaded_fetch_count, loaded_clear_pending;
	int32_t  loaded_clock, loaded_disp_len, loaded_disp_rate, loaded_disp_count;
	int32_t  loaded_disp_y_min, loaded_disp_y_max, loaded_y_min, loaded_y_max;
	int32_t  loaded_border_was_disabled, loaded_display_was_disabled, loaded_output_enable;
	uint32_t loaded_timer_ts_int, loaded_timer_ts_frac;
	int32_t  loaded_timer_enabled;

	(void)version;

	for (i = 0; i < 64; i++)
		if (!snapshot_payload_reader_read_u32(r, &loaded_vidcr[i])) return 0;

	if (!snapshot_payload_reader_read_i32(r, &loaded_dma_length))      return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_framecount))      return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_displayon_top))   return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_soundhz))         return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_soundper))        return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_flyback))         return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_videodma))        return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_palchange))       return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_redrawpalette))   return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_oldflash))        return 0;

	if (!snapshot_payload_reader_read_u32(r, &loaded_vtot))   return 0;
	if (!snapshot_payload_reader_read_u32(r, &loaded_htot))   return 0;
	if (!snapshot_payload_reader_read_u32(r, &loaded_vsync))  return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_line))   return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_displayon_inner)) return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_borderon)) return 0;
	if (!snapshot_payload_reader_read_u32(r, &loaded_addr))   return 0;
	if (!snapshot_payload_reader_read_u32(r, &loaded_caddr))  return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_vbstart)) return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_vbend))   return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_vdstart)) return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_vdend))   return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_hbstart)) return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_hbend))   return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_hdstart)) return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_hdend))   return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_hdstart2)) return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_hdend2))   return 0;
	if (!snapshot_payload_reader_read_u32(r, &loaded_cr))      return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_sync))    return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_inter))   return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_horiz_length))     return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_hsync_length))     return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_front_porch_length)) return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_display_length))   return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_back_porch_length)) return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_state))   return 0;
	if (!snapshot_payload_reader_read_u64(r, &loaded_pixel_time))         return 0;
	if (!snapshot_payload_reader_read_u64(r, &loaded_fetch_time))         return 0;
	if (!snapshot_payload_reader_read_u64(r, &loaded_initial_fetch_time)) return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_cursor_lines)) return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_first_line))   return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_cx))           return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_cys))          return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_cye))          return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_cxh))          return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_scanrate))     return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_in_display))   return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_cyclesperline_display))  return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_cyclesperline_blanking)) return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_cycles_per_fetch)) return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_fetch_count))   return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_clear_pending)) return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_clock))    return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_disp_len)) return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_disp_rate)) return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_disp_count)) return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_disp_y_min)) return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_disp_y_max)) return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_y_min))    return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_y_max))    return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_border_was_disabled)) return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_display_was_disabled)) return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_output_enable)) return 0;

	if (!snapshot_payload_reader_read_u32(r, &loaded_timer_ts_int))  return 0;
	if (!snapshot_payload_reader_read_u32(r, &loaded_timer_ts_frac)) return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_timer_enabled)) return 0;

	for (i = 0; i < 64; i++)
		vidcr[i] = loaded_vidcr[i];

	vidc_dma_length = (int)loaded_dma_length;
	vidc_framecount = (int)loaded_framecount;
	vidc_displayon  = (int)loaded_displayon_top;
	soundhz         = (int)loaded_soundhz;
	soundper        = (int)loaded_soundper;
	flyback         = (int)loaded_flyback;
	videodma        = (int)loaded_videodma;
	palchange       = (int)loaded_palchange;
	redrawpalette   = (int)loaded_redrawpalette;
	oldflash        = (int)loaded_oldflash;

	vidc.vtot   = loaded_vtot;
	vidc.htot   = loaded_htot;
	vidc.vsync  = loaded_vsync;
	vidc.line   = (int)loaded_line;
	vidc.displayon = (int)loaded_displayon_inner;
	vidc.borderon  = (int)loaded_borderon;
	vidc.addr   = loaded_addr;
	vidc.caddr  = loaded_caddr;
	vidc.vbstart = (int)loaded_vbstart;
	vidc.vbend   = (int)loaded_vbend;
	vidc.vdstart = (int)loaded_vdstart;
	vidc.vdend   = (int)loaded_vdend;
	vidc.hbstart = (int)loaded_hbstart;
	vidc.hbend   = (int)loaded_hbend;
	vidc.hdstart = (int)loaded_hdstart;
	vidc.hdend   = (int)loaded_hdend;
	vidc.hdstart2 = (int)loaded_hdstart2;
	vidc.hdend2   = (int)loaded_hdend2;
	vidc.cr     = loaded_cr;
	vidc.sync   = (int)loaded_sync;
	vidc.inter  = (int)loaded_inter;
	vidc.horiz_length       = (int)loaded_horiz_length;
	vidc.hsync_length       = (int)loaded_hsync_length;
	vidc.front_porch_length = (int)loaded_front_porch_length;
	vidc.display_length     = (int)loaded_display_length;
	vidc.back_porch_length  = (int)loaded_back_porch_length;
	vidc.state              = (int)loaded_state;
	vidc.pixel_time         = loaded_pixel_time;
	vidc.fetch_time         = loaded_fetch_time;
	vidc.initial_fetch_time = loaded_initial_fetch_time;
	vidc.cursor_lines = (int)loaded_cursor_lines;
	vidc.first_line   = (int)loaded_first_line;
	vidc.cx  = (int)loaded_cx;
	vidc.cys = (int)loaded_cys;
	vidc.cye = (int)loaded_cye;
	vidc.cxh = (int)loaded_cxh;
	vidc.scanrate    = (int)loaded_scanrate;
	vidc.in_display  = (int)loaded_in_display;
	vidc.cyclesperline_display  = (int)loaded_cyclesperline_display;
	vidc.cyclesperline_blanking = (int)loaded_cyclesperline_blanking;
	vidc.cycles_per_fetch = (int)loaded_cycles_per_fetch;
	vidc.fetch_count      = (int)loaded_fetch_count;
	vidc.clear_pending    = (int)loaded_clear_pending;
	vidc.clock     = (int)loaded_clock;
	vidc.disp_len  = (int)loaded_disp_len;
	vidc.disp_rate = (int)loaded_disp_rate;
	vidc.disp_count = (int)loaded_disp_count;
	vidc.disp_y_min = (int)loaded_disp_y_min;
	vidc.disp_y_max = (int)loaded_disp_y_max;
	vidc.y_min = (int)loaded_y_min;
	vidc.y_max = (int)loaded_y_max;
	vidc.border_was_disabled  = (int)loaded_border_was_disabled;
	vidc.display_was_disabled = (int)loaded_display_was_disabled;
	vidc.output_enable        = (int)loaded_output_enable;

	timer_restore(&vidc.timer, loaded_timer_ts_int, loaded_timer_ts_frac, (int)loaded_timer_enabled);

	/* Rebuild derived state from the freshly-restored vidcr[] */
	vidc_redopalette();
	redolookup();
	setredrawall();

	return 1;
}

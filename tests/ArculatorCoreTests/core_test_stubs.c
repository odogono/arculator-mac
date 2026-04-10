/*
 * Linker stubs for ArculatorCoreTests.
 *
 * The core test bundle compiles config.c, cmos.c, platform_paths.c, and
 * timer.c directly.  Those files pull in headers that declare externs
 * defined elsewhere in the emulator.  This file provides zero-value
 * definitions so the test bundle links without dragging in the entire
 * emulator.
 */
#include <stdarg.h>
#include <stdint.h>
#include <string.h>

#include "plat_joystick.h"

/* --- globals from main.c --- */
int romset = 0;
int firstfull = 1;
int memsize = 4096;
int speed_mhz = 0;
char exname[512];

/* --- globals from arm.c --- */
int arm_cpu_type = 0;
int fpaena = 0;

/* --- globals from fpa.c --- */
int fpu_type = 0;

/* --- globals from memc.c --- */
int memc_type = 0;

/* --- globals from vidc.c / video --- */
int display_mode = 0;
int video_scale = 1;
int video_fullscreen_scale = 0;
int video_linear_filtering = 0;
int video_black_level = 0;
int fullscreen = 0;
int fullborders = 0;
int noborders = 0;
int dblscan = 1;

/* --- globals from sound.c --- */
int stereo = 0;
int soundena = 0;
int sound_gain = 0;
int sound_filter = 0;

/* --- globals from disc.c --- */
int fdctype = 0;
int disc_noise_gain = 0;
char discname[4][512];

/* snapshot_can_save() gates. Default to the "idle + paused" baseline
 * so scope-guard tests can toggle one input at a time. */
int g_test_floppy_is_idle = 1;
int g_test_arc_is_paused  = 1;
int g_test_ide_is_idle    = 1;
int floppy_is_idle(void)        { return g_test_floppy_is_idle; }
int arc_is_paused(void)         { return g_test_arc_is_paused; }
int ide_internal_is_idle(void)  { return g_test_ide_is_idle; }

/* --- globals from st506.c --- */
int st506_present = 0;

/* --- globals from romload.c --- */
int romset_available_mask = 0;

/* --- globals from joystick.c --- */
int joystick_type = 0;

/* --- globals from plat_joystick --- */
joystick_t joystick_state[MAX_JOYSTICKS];
plat_joystick_t plat_joystick_state[MAX_PLAT_JOYSTICKS];
int joysticks_present = 0;

/* --- globals from plat_video --- */
int selected_video_renderer = 0;

/* --- arc.h logging --- */
void rpclog(const char *format, ...)
{
	(void)format;
}
void error(const char *format, ...)
{
	(void)format;
}
void fatal(const char *format, ...)
{
	(void)format;
}

/* --- joystick.c functions --- */
int joystick_get_type(char *config_name)
{
	(void)config_name;
	return 0;
}
const int joystick_get_max_joysticks(int joystick)
{
	(void)joystick;
	return 0;
}
const int joystick_get_axis_count(int joystick)
{
	(void)joystick;
	return 0;
}
const int joystick_get_button_count(int joystick)
{
	(void)joystick;
	return 0;
}
const int joystick_get_pov_count(int joystick)
{
	(void)joystick;
	return 0;
}

/* --- podules --- */
char podule_names[4][16];

/* --- plat_video / video_renderer --- */
void video_renderer_begin_close(void) {}
void video_renderer_close(void) {}
int video_renderer_get_id(char *name)
{
	(void)name;
	return 0;
}
char *video_renderer_get_name(int id)
{
	(void)id;
	return "auto";
}

/* --- bmu.c --- */
uint8_t bmu_read(int addr)
{
	(void)addr;
	return 0;
}
void bmu_write(int addr, uint8_t val)
{
	(void)addr;
	(void)val;
}

/* --- debugger.c --- */
void debug_start(void) {}
void debug_kill(void) {}
void debug_end(void) {}
void debugger_do(void) {}
void debug_out(char *s) { (void)s; }
void debug_trap(int trap, uint32_t opcode) { (void)trap; (void)opcode; }

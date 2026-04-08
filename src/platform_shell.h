#ifndef PLATFORM_SHELL_H
#define PLATFORM_SHELL_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

void arc_print_error(const char *format, ...);

void updatewindowsize(int x, int y);

void arc_start_main_thread(void *window, void *menu);
void arc_stop_main_thread(void);
void arc_pause_main_thread(void);
void arc_resume_main_thread(void);

void arc_do_reset(void);
void arc_disc_change(int drive, char *fn);
void arc_disc_eject(int drive);
void arc_enter_fullscreen(void);
void arc_renderer_reset(void);
void arc_set_display_mode(int new_display_mode);
void arc_set_dblscan(int new_dblscan);

void arc_stop_emulation(void);
void arc_popup_menu(void);
void arc_update_menu(void);
void *wx_getnativemenu(void *menu);
void arc_main_loop(void);

#ifdef __APPLE__
#include <stdint.h>

int arc_is_session_active(void);
int arc_is_paused(void);

/* Queue a save-snapshot command for the running (paused) emulation
 * thread. Executes on the next tick of the command queue. Errors are
 * reported asynchronously via arc_print_error().
 *
 * Ownership transfer: `preview_png` and `meta` (if non-NULL) must be
 * heap-allocated. On success (queue push accepted the command) the
 * emulation thread takes ownership and frees them after the save runs.
 * On failure (queue full) the caller is responsible for freeing. */
void arc_save_snapshot(const char *path,
                       uint8_t *preview_png, size_t preview_png_size,
                       int preview_width, int preview_height,
                       void *meta);

/* Start a fresh emulation session from a .arcsnap file. Session must
 * be idle (no running emulation thread). Synchronous: on success
 * returns 1 and the emulation thread is running; on failure returns 0
 * and writes a human-readable message to `err_out`. */
int arc_start_snapshot_session(const char *path, char *err_out, size_t n);

/* Returns the original machine_config_name captured in the active
 * snapshot session's manifest, or NULL if the current session isn't
 * a snapshot session (or no session is active). */
const char *arc_snapshot_session_display_name(void);
#endif

#ifdef __cplusplus
}
#endif

#endif

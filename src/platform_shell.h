#ifndef PLATFORM_SHELL_H
#define PLATFORM_SHELL_H

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

#ifdef __cplusplus
}
#endif

#endif

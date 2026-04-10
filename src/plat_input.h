#ifndef PLAT_INPUT_H
#define PLAT_INPUT_H

#include "input_snapshot.h"

void input_init();
void input_close();

void input_capture_host_snapshot();
void input_apply_host_snapshot();
int input_get_host_key_state(int code);
int input_is_host_key_suppressed(int code);
void input_begin_host_key_suppression(const int *codes, int count);

void mouse_get_mickeys(int *x, int *y);
int mouse_get_buttons();
void mouse_capture_enable();
void mouse_capture_disable();

/* Input injection (called from ObjC bridge, thread-safe via input_mutex) */
void input_inject_key(int code, int down);
void input_inject_clear_key(int code);
void input_inject_clear_all_keys(void);
void input_inject_mouse_button(int button_mask, int down);
void input_inject_mouse_move(int dx, int dy);
void input_inject_mouse_abs(int x, int y);
void input_inject_clear_mouse(void);

extern int key[INPUT_MAX_KEYCODES];

#ifdef __APPLE__
#include "keyboard_macos.h"
#else
#include "keyboard_sdl.h"
#endif

#endif

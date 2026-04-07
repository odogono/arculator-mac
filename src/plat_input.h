#ifndef PLAT_INPUT_H
#define PLAT_INPUT_H

#include "input_snapshot.h"

void input_init();
void input_close();

void input_capture_host_snapshot();
void input_apply_host_snapshot();
int input_get_host_key_state(int code);

void mouse_get_mickeys(int *x, int *y);
int mouse_get_buttons();
void mouse_capture_enable();
void mouse_capture_disable();

extern int key[INPUT_MAX_KEYCODES];

#ifdef __APPLE__
#include "keyboard_macos.h"
#else
#include "keyboard_sdl.h"
#endif

#endif

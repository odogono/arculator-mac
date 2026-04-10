#ifndef RELEASE_SHORTCUT_LOGIC_H
#define RELEASE_SHORTCUT_LOGIC_H

#import <AppKit/AppKit.h>

#include <stdint.h>

#include "keyboard_macos.h"

enum
{
	ARC_RELEASE_MODIFIER_COMMAND = 1u << 0,
	ARC_RELEASE_MODIFIER_CONTROL = 1u << 1,
	ARC_RELEASE_MODIFIER_OPTION  = 1u << 2,
	ARC_RELEASE_MODIFIER_SHIFT   = 1u << 3,
};

static inline uint32_t arc_release_shortcut_modifier_mask_from_flags(uint64_t flags)
{
	uint32_t mask = 0;

	if (flags & NSEventModifierFlagCommand) mask |= ARC_RELEASE_MODIFIER_COMMAND;
	if (flags & NSEventModifierFlagControl) mask |= ARC_RELEASE_MODIFIER_CONTROL;
	if (flags & NSEventModifierFlagOption)  mask |= ARC_RELEASE_MODIFIER_OPTION;
	if (flags & NSEventModifierFlagShift)   mask |= ARC_RELEASE_MODIFIER_SHIFT;

	return mask;
}

static inline int arc_release_shortcut_matches(uint32_t event_modifiers,
                                               int event_keycode,
                                               uint32_t configured_modifiers,
                                               int configured_keycode)
{
	return event_modifiers == configured_modifiers && event_keycode == configured_keycode;
}

static inline int arc_release_shortcut_fill_suppressed_keys(uint32_t modifiers,
                                                            int main_keycode,
                                                            int *dest,
                                                            int max_dest)
{
	int count = 0;

#define ARC_RELEASE_APPEND(code) \
	do { \
		if (count < max_dest) \
			dest[count] = (code); \
		count++; \
	} while (0)

	if (modifiers & ARC_RELEASE_MODIFIER_COMMAND)
	{
		ARC_RELEASE_APPEND(KEY_LWIN);
		ARC_RELEASE_APPEND(KEY_RWIN);
	}
	if (modifiers & ARC_RELEASE_MODIFIER_CONTROL)
	{
		ARC_RELEASE_APPEND(KEY_LCONTROL);
		ARC_RELEASE_APPEND(KEY_RCONTROL);
	}
	if (modifiers & ARC_RELEASE_MODIFIER_OPTION)
	{
		ARC_RELEASE_APPEND(KEY_ALT);
		ARC_RELEASE_APPEND(KEY_ALTGR);
	}
	if (modifiers & ARC_RELEASE_MODIFIER_SHIFT)
	{
		ARC_RELEASE_APPEND(KEY_LSHIFT);
		ARC_RELEASE_APPEND(KEY_RSHIFT);
	}
	ARC_RELEASE_APPEND(main_keycode);

#undef ARC_RELEASE_APPEND

	return count;
}

#endif

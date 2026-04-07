#import <Foundation/Foundation.h>
#import <GameController/GameController.h>

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "joystick_api.h"

#define GC_AXIS_COUNT 6
#define GC_BUTTON_COUNT 10
#define GC_POV_COUNT 1

#define PLAT_JOYSTICK_POV_CENTERED 0x00
#define PLAT_JOYSTICK_POV_UP 0x01
#define PLAT_JOYSTICK_POV_RIGHT 0x02
#define PLAT_JOYSTICK_POV_DOWN 0x04
#define PLAT_JOYSTICK_POV_LEFT 0x08
#define PLAT_JOYSTICK_POV_RIGHTUP (PLAT_JOYSTICK_POV_RIGHT | PLAT_JOYSTICK_POV_UP)
#define PLAT_JOYSTICK_POV_RIGHTDOWN (PLAT_JOYSTICK_POV_RIGHT | PLAT_JOYSTICK_POV_DOWN)
#define PLAT_JOYSTICK_POV_LEFTUP (PLAT_JOYSTICK_POV_LEFT | PLAT_JOYSTICK_POV_UP)
#define PLAT_JOYSTICK_POV_LEFTDOWN (PLAT_JOYSTICK_POV_LEFT | PLAT_JOYSTICK_POV_DOWN)

int joysticks_present;
joystick_t joystick_state[MAX_JOYSTICKS];
plat_joystick_t plat_joystick_state[MAX_PLAT_JOYSTICKS];
static char joystick_button_text[65536];
static char joystick_axis_text[65536];

podule_config_selection_t joystick_button_config_selection[33];
podule_config_selection_t joystick_axis_config_selection[13];

static const char * const gc_axis_names[GC_AXIS_COUNT] = {
	"Left X",
	"Left Y",
	"Right X",
	"Right Y",
	"Left Trigger",
	"Right Trigger"
};

static const char * const gc_button_names[GC_BUTTON_COUNT] = {
	"A",
	"B",
	"X",
	"Y",
	"Left Shoulder",
	"Right Shoulder",
	"Menu",
	"Options",
	"Left Thumbstick",
	"Right Thumbstick"
};

static int normalize_axis(float value, int centered)
{
	float clamped = fmaxf(-1.0f, fminf(1.0f, value));

	if (!centered)
		clamped = fmaxf(0.0f, clamped);

	return (int)lrintf(clamped * 32767.0f);
}


static int current_pov_value(GCControllerDirectionPad *dpad)
{
	int pov = PLAT_JOYSTICK_POV_CENTERED;

	if (!dpad)
		return pov;

	if (dpad.up.isPressed)
		pov |= PLAT_JOYSTICK_POV_UP;
	if (dpad.right.isPressed)
		pov |= PLAT_JOYSTICK_POV_RIGHT;
	if (dpad.down.isPressed)
		pov |= PLAT_JOYSTICK_POV_DOWN;
	if (dpad.left.isPressed)
		pov |= PLAT_JOYSTICK_POV_LEFT;

	return pov;
}

static void fill_controller_metadata(plat_joystick_t *state, GCController *controller)
{
	NSString *name = controller.vendorName;
	int i;

	memset(state, 0, sizeof(*state));
	if (!name.length)
		name = @"Game Controller";

	strncpy(state->name, [name UTF8String], sizeof(state->name) - 1);
	state->nr_axes = GC_AXIS_COUNT;
	state->nr_buttons = GC_BUTTON_COUNT;
	state->nr_povs = 0;

	for (i = 0; i < GC_AXIS_COUNT; i++)
	{
		strncpy(state->axis[i].name, gc_axis_names[i], sizeof(state->axis[i].name) - 1);
		state->axis[i].id = i;
	}

	for (i = 0; i < GC_BUTTON_COUNT; i++)
	{
		strncpy(state->button[i].name, gc_button_names[i], sizeof(state->button[i].name) - 1);
		state->button[i].id = i;
	}

	if (controller.extendedGamepad.dpad || controller.gamepad.dpad || controller.microGamepad.dpad)
	{
		strncpy(state->pov[0].name, "D-Pad", sizeof(state->pov[0].name) - 1);
		state->pov[0].id = 0;
		state->nr_povs = GC_POV_COUNT;
	}
}

static void refresh_controller_list(NSArray<GCController *> *controllers)
{
	NSUInteger count = MIN((NSUInteger)MAX_PLAT_JOYSTICKS, controllers.count);
	NSUInteger i;

	memset(plat_joystick_state, 0, sizeof(plat_joystick_state));
	joysticks_present = (int)count;

	for (i = 0; i < count; i++)
		fill_controller_metadata(&plat_joystick_state[i], controllers[i]);
}

static void populate_platform_state(plat_joystick_t *state, GCController *controller)
{
	GCExtendedGamepad *extended = controller.extendedGamepad;
	GCGamepad *gamepad = controller.gamepad;
	GCMicroGamepad *micro = controller.microGamepad;

	if (extended)
	{
		state->a[0] = normalize_axis(extended.leftThumbstick.xAxis.value, 1);
		state->a[1] = normalize_axis(extended.leftThumbstick.yAxis.value, 1);
		state->a[2] = normalize_axis(extended.rightThumbstick.xAxis.value, 1);
		state->a[3] = normalize_axis(extended.rightThumbstick.yAxis.value, 1);
		state->a[4] = normalize_axis(extended.leftTrigger.value, 0);
		state->a[5] = normalize_axis(extended.rightTrigger.value, 0);

		state->b[0] = extended.buttonA.isPressed;
		state->b[1] = extended.buttonB.isPressed;
		state->b[2] = extended.buttonX.isPressed;
		state->b[3] = extended.buttonY.isPressed;
		state->b[4] = extended.leftShoulder.isPressed;
		state->b[5] = extended.rightShoulder.isPressed;
		state->b[6] = extended.buttonMenu.isPressed;
		state->b[7] = extended.buttonOptions ? extended.buttonOptions.isPressed : 0;
		state->b[8] = extended.leftThumbstickButton ? extended.leftThumbstickButton.isPressed : 0;
		state->b[9] = extended.rightThumbstickButton ? extended.rightThumbstickButton.isPressed : 0;
		state->p[0] = current_pov_value(extended.dpad);
		return;
	}

	if (gamepad)
	{
		state->b[0] = gamepad.buttonA.isPressed;
		state->b[1] = gamepad.buttonB.isPressed;
		state->b[2] = gamepad.buttonX.isPressed;
		state->b[3] = gamepad.buttonY.isPressed;
		state->b[4] = gamepad.leftShoulder.isPressed;
		state->b[5] = gamepad.rightShoulder.isPressed;
		state->p[0] = current_pov_value(gamepad.dpad);
		return;
	}

	if (micro)
	{
		state->b[0] = micro.buttonA.isPressed;
		state->b[1] = micro.buttonX.isPressed;
		state->b[6] = micro.buttonMenu.isPressed;
		state->p[0] = current_pov_value(micro.dpad);
	}
}

static int joystick_get_axis(int joystick_nr, int mapping)
{
	if (mapping & POV_X)
	{
		switch (plat_joystick_state[joystick_nr].p[mapping & 3])
		{
			case PLAT_JOYSTICK_POV_LEFTUP:
			case PLAT_JOYSTICK_POV_LEFT:
			case PLAT_JOYSTICK_POV_LEFTDOWN:
			return -32767;

			case PLAT_JOYSTICK_POV_RIGHTUP:
			case PLAT_JOYSTICK_POV_RIGHT:
			case PLAT_JOYSTICK_POV_RIGHTDOWN:
			return 32767;

			default:
			return 0;
		}
	}
	else if (mapping & POV_Y)
	{
		switch (plat_joystick_state[joystick_nr].p[mapping & 3])
		{
			case PLAT_JOYSTICK_POV_LEFTUP:
			case PLAT_JOYSTICK_POV_UP:
			case PLAT_JOYSTICK_POV_RIGHTUP:
			return -32767;

			case PLAT_JOYSTICK_POV_LEFTDOWN:
			case PLAT_JOYSTICK_POV_DOWN:
			case PLAT_JOYSTICK_POV_RIGHTDOWN:
			return 32767;

			default:
			return 0;
		}
	}

	return plat_joystick_state[joystick_nr].a[plat_joystick_state[joystick_nr].axis[mapping].id];
}

void joystick_init(podule_t *podule, const podule_callbacks_t *podule_callbacks)
{
	int c;

	@autoreleasepool {
		refresh_controller_list([GCController controllers]);
	}

	if (!podule)
		return;

	for (c = 0; c < joystick_get_max_joysticks(); c++)
	{
		char s[80];

		sprintf(s, "joystick_%i_nr", c);
		joystick_state[c].plat_joystick_nr = podule_callbacks->config_get_int(podule, s, 0);

		if (joystick_state[c].plat_joystick_nr)
		{
			int d;

			for (d = 0; d < joystick_get_axis_count(); d++)
			{
				sprintf(s, "joystick_%i_axis_%i", c, d);
				joystick_state[c].axis_mapping[d] = podule_callbacks->config_get_int(podule, s, d);
			}
			for (d = 0; d < joystick_get_button_count(); d++)
			{
				sprintf(s, "joystick_%i_button_%i", c, d);
				joystick_state[c].button_mapping[d] = podule_callbacks->config_get_int(podule, s, d);
			}
			for (d = 0; d < joystick_get_pov_count(); d++)
			{
				sprintf(s, "joystick_%i_pov_%i_x", c, d);
				joystick_state[c].pov_mapping[d][0] = podule_callbacks->config_get_int(podule, s, d);
				sprintf(s, "joystick_%i_pov_%i_y", c, d);
				joystick_state[c].pov_mapping[d][1] = podule_callbacks->config_get_int(podule, s, d);
			}
		}
	}
}

void joystick_close(void)
{
	memset(plat_joystick_state, 0, sizeof(plat_joystick_state));
	memset(joystick_state, 0, sizeof(joystick_state));
	joysticks_present = 0;
}

void joystick_poll_host(void)
{
	int c;

	@autoreleasepool {
		NSArray<GCController *> *controllers = [GCController controllers];
		NSUInteger count = MIN((NSUInteger)MAX_PLAT_JOYSTICKS, controllers.count);
		NSUInteger i;

		if ((int)count != joysticks_present)
			refresh_controller_list(controllers);

		for (i = 0; i < count; i++)
			populate_platform_state(&plat_joystick_state[i], controllers[i]);
	}

	for (c = 0; c < joystick_get_max_joysticks(); c++)
	{
		if (joystick_state[c].plat_joystick_nr && joystick_state[c].plat_joystick_nr <= joysticks_present)
		{
			int joystick_nr = joystick_state[c].plat_joystick_nr - 1;
			int d;

			for (d = 0; d < joystick_get_axis_count(); d++)
				joystick_state[c].axis[d] = joystick_get_axis(joystick_nr, joystick_state[c].axis_mapping[d]);
			for (d = 0; d < joystick_get_button_count(); d++)
				joystick_state[c].button[d] = plat_joystick_state[joystick_nr].b[joystick_state[c].button_mapping[d]];
			for (d = 0; d < joystick_get_pov_count(); d++)
			{
				int x, y;
				double angle, magnitude;

				x = joystick_get_axis(joystick_nr, joystick_state[c].pov_mapping[d][0]);
				y = joystick_get_axis(joystick_nr, joystick_state[c].pov_mapping[d][1]);

				angle = (atan2((double)y, (double)x) * 360.0) / (2 * M_PI);
				magnitude = sqrt((double)x * (double)x + (double)y * (double)y);

				if (magnitude < 16384)
					joystick_state[c].pov[d] = -1;
				else
					joystick_state[c].pov[d] = ((int)angle + 90 + 360) % 360;
			}
		}
		else
		{
			int d;

			for (d = 0; d < joystick_get_axis_count(); d++)
				joystick_state[c].axis[d] = 0;
			for (d = 0; d < joystick_get_button_count(); d++)
				joystick_state[c].button[d] = 0;
			for (d = 0; d < joystick_get_pov_count(); d++)
				joystick_state[c].pov[d] = -1;
		}
	}
}

podule_config_selection_t *joystick_devices_config(const podule_callbacks_t *podule_callbacks)
{
	podule_config_selection_t *sel;
	podule_config_selection_t *sel_p;
	char *joystick_dev_text = malloc(65536);
	int c;

	joystick_init(NULL, podule_callbacks);

	sel = malloc(sizeof(podule_config_selection_t) * (joysticks_present + 2));
	sel_p = sel;

	strcpy(joystick_dev_text, "None");
	sel_p->description = joystick_dev_text;
	sel_p->value = 0;
	sel_p++;
	joystick_dev_text += strlen(joystick_dev_text) + 1;

	for (c = 0; c < joysticks_present; c++)
	{
		strcpy(joystick_dev_text, plat_joystick_state[c].name);
		sel_p->description = joystick_dev_text;
		sel_p->value = c + 1;
		sel_p++;

		joystick_dev_text += strlen(joystick_dev_text) + 1;
	}

	strcpy(joystick_dev_text, "");
	sel_p->description = joystick_dev_text;

	joystick_close();

	return sel;
}

void joystick_update_buttons_config(int joy_device)
{
	podule_config_selection_t *sel_p = joystick_button_config_selection;
	char *text_p = joystick_button_text;

	if (joy_device)
	{
		int c;

		for (c = 0; c < MIN(plat_joystick_state[joy_device - 1].nr_buttons, 8); c++)
		{
			strcpy(text_p, plat_joystick_state[joy_device - 1].button[c].name);
			sel_p->description = text_p;
			sel_p->value = c;
			sel_p++;
			text_p += strlen(text_p) + 1;
		}
	}
	else
	{
		strcpy(text_p, "None");
		sel_p->description = text_p;
		sel_p->value = 0;
		sel_p++;
		text_p += strlen(text_p) + 1;
	}

	strcpy(text_p, "");
	sel_p->description = text_p;
}

void joystick_update_axes_config(int joy_device)
{
	podule_config_selection_t *sel_p = joystick_axis_config_selection;
	char *text_p = joystick_axis_text;

	if (joy_device)
	{
		int c;

		for (c = 0; c < MIN(plat_joystick_state[joy_device - 1].nr_axes, 8); c++)
		{
			strcpy(text_p, plat_joystick_state[joy_device - 1].axis[c].name);
			sel_p->description = text_p;
			sel_p->value = c;
			sel_p++;
			text_p += strlen(text_p) + 1;
		}

		for (c = 0; c < MIN(plat_joystick_state[joy_device - 1].nr_povs, 4); c++)
		{
			sprintf(text_p, "%s (X axis)", plat_joystick_state[joy_device - 1].pov[c].name);
			sel_p->description = text_p;
			sel_p->value = c | POV_X;
			sel_p++;
			text_p += strlen(text_p) + 1;

			sprintf(text_p, "%s (Y axis)", plat_joystick_state[joy_device - 1].pov[c].name);
			sel_p->description = text_p;
			sel_p->value = c | POV_Y;
			sel_p++;
			text_p += strlen(text_p) + 1;
		}
	}
	else
	{
		strcpy(text_p, "None");
		sel_p->description = text_p;
		sel_p->value = 0;
		sel_p++;
		text_p += strlen(text_p) + 1;
	}

	strcpy(text_p, "");
	sel_p->description = text_p;
}

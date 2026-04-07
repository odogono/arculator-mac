#import <Foundation/Foundation.h>
#import <GameController/GameController.h>

#include <math.h>
#include <string.h>

#include "arc.h"
#include "joystick.h"
#include "plat_joystick.h"

#define GC_AXIS_COUNT 6
#define GC_BUTTON_COUNT 10
#define GC_POV_COUNT 1

int joysticks_present;
joystick_t joystick_state[MAX_JOYSTICKS];
plat_joystick_t plat_joystick_state[MAX_PLAT_JOYSTICKS];

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

static void clear_platform_joystick(plat_joystick_t *state)
{
	memset(state, 0, sizeof(*state));
}

static void fill_controller_metadata(plat_joystick_t *state, GCController *controller)
{
	NSString *name = controller.vendorName;

	clear_platform_joystick(state);
	if (!name.length)
		name = @"Game Controller";

	strncpy(state->name, [name UTF8String], sizeof(state->name) - 1);
	state->nr_axes = GC_AXIS_COUNT;
	state->nr_buttons = GC_BUTTON_COUNT;
	state->nr_povs = 0;

	for (int i = 0; i < GC_AXIS_COUNT; i++)
	{
		strncpy(state->axis[i].name, gc_axis_names[i], sizeof(state->axis[i].name) - 1);
		state->axis[i].id = i;
	}

	for (int i = 0; i < GC_BUTTON_COUNT; i++)
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

	memset(plat_joystick_state, 0, sizeof(plat_joystick_state));
	joysticks_present = (int)count;

	for (NSUInteger i = 0; i < count; i++)
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

void joystick_init(void)
{
	@autoreleasepool {
		refresh_controller_list([GCController controllers]);
	}
}

void joystick_close(void)
{
	memset(plat_joystick_state, 0, sizeof(plat_joystick_state));
	joysticks_present = 0;
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

void joystick_poll_host(void)
{
	@autoreleasepool {
		NSArray<GCController *> *controllers = [GCController controllers];
		NSUInteger count = MIN((NSUInteger)MAX_PLAT_JOYSTICKS, controllers.count);

		if ((int)count != joysticks_present)
			refresh_controller_list(controllers);

		for (NSUInteger i = 0; i < count; i++)
			populate_platform_state(&plat_joystick_state[i], controllers[i]);

		for (int c = 0; c < joystick_get_max_joysticks(joystick_type); c++)
		{
			if (joystick_state[c].plat_joystick_nr && joystick_state[c].plat_joystick_nr <= joysticks_present)
			{
				int joystick_nr = joystick_state[c].plat_joystick_nr - 1;

				for (int d = 0; d < joystick_get_axis_count(joystick_type); d++)
					joystick_state[c].axis[d] = joystick_get_axis(joystick_nr, joystick_state[c].axis_mapping[d]);
				for (int d = 0; d < joystick_get_button_count(joystick_type); d++)
					joystick_state[c].button[d] = plat_joystick_state[joystick_nr].b[joystick_state[c].button_mapping[d]];
				for (int d = 0; d < joystick_get_pov_count(joystick_type); d++)
				{
					int x = joystick_get_axis(joystick_nr, joystick_state[c].pov_mapping[d][0]);
					int y = joystick_get_axis(joystick_nr, joystick_state[c].pov_mapping[d][1]);
					double angle = (atan2((double)y, (double)x) * 360.0) / (2 * M_PI);
					double magnitude = sqrt((double)x * (double)x + (double)y * (double)y);

					if (magnitude < 16384)
						joystick_state[c].pov[d] = -1;
					else
						joystick_state[c].pov[d] = ((int)angle + 90 + 360) % 360;
				}
			}
			else
			{
				for (int d = 0; d < joystick_get_axis_count(joystick_type); d++)
					joystick_state[c].axis[d] = 0;
				for (int d = 0; d < joystick_get_button_count(joystick_type); d++)
					joystick_state[c].button[d] = 0;
				for (int d = 0; d < joystick_get_pov_count(joystick_type); d++)
					joystick_state[c].pov[d] = -1;
			}
		}
	}
}

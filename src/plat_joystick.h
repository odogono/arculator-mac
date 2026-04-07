#ifndef PLAT_JOYSTICK_H
#define PLAT_JOYSTICK_H

#ifdef __cplusplus
extern "C" {
#endif
	void joystick_init();
	void joystick_close();
	void joystick_poll_host();

	#define PLAT_JOYSTICK_POV_CENTERED 0x00
	#define PLAT_JOYSTICK_POV_UP       0x01
	#define PLAT_JOYSTICK_POV_RIGHT    0x02
	#define PLAT_JOYSTICK_POV_DOWN     0x04
	#define PLAT_JOYSTICK_POV_LEFT     0x08
	#define PLAT_JOYSTICK_POV_RIGHTUP  (PLAT_JOYSTICK_POV_RIGHT | PLAT_JOYSTICK_POV_UP)
	#define PLAT_JOYSTICK_POV_RIGHTDOWN (PLAT_JOYSTICK_POV_RIGHT | PLAT_JOYSTICK_POV_DOWN)
	#define PLAT_JOYSTICK_POV_LEFTUP   (PLAT_JOYSTICK_POV_LEFT | PLAT_JOYSTICK_POV_UP)
	#define PLAT_JOYSTICK_POV_LEFTDOWN (PLAT_JOYSTICK_POV_LEFT | PLAT_JOYSTICK_POV_DOWN)

	typedef struct plat_joystick_t
	{
		char name[64];

		int a[8];
		int b[32];
		int p[4];

		struct
		{
			char name[32];
			int id;
		} axis[8];

		struct
		{
			char name[32];
			int id;
		} button[32];

		struct
		{
			char name[32];
			int id;
		} pov[4];

		int nr_axes;
		int nr_buttons;
		int nr_povs;
	} plat_joystick_t;

	#define MAX_PLAT_JOYSTICKS 8

	extern plat_joystick_t plat_joystick_state[MAX_PLAT_JOYSTICKS];
	extern int joysticks_present;

	#define POV_X 0x80000000
	#define POV_Y 0x40000000

	typedef struct joystick_t
	{
		int axis[8];
		int button[32];
		int pov[4];

		int plat_joystick_nr;
		int axis_mapping[8];
		int button_mapping[32];
		int pov_mapping[4][2];
	} joystick_t;

	#define MAX_JOYSTICKS 4
	extern joystick_t joystick_state[MAX_JOYSTICKS];

	#define JOYSTICK_PRESENT(n) (joystick_state[n].plat_joystick_nr != 0)

#ifdef __cplusplus
}
#endif

#endif

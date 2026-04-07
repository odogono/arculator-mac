/*Arculator 2.2 by Sarah Walker
  I2C + CMOS RAM emulation*/
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#ifdef WIN32
#include <windows.h>
#endif
#include "arc.h"
#include "bmu.h"
#include "cmos.h"
#include "config.h"
#include "platform_paths.h"
#include "st506.h"
#include "timer.h"

int cmos_changed = 0;
int i2c_clock = 1, i2c_data = 1;

#define TRANSMITTER_CMOS 1
#define TRANSMITTER_ARM -1

#define I2C_IDLE             0
#define I2C_RECEIVE          1
#define I2C_TRANSMIT         2
#define I2C_ACKNOWLEDGE      3
#define I2C_TRANSACKNOWLEDGE 4

enum
{
	CMOS_IDLE,
	CMOS_RECEIVEADDR,
	CMOS_RECEIVEDATA,
	CMOS_SENDDATA,
	CMOS_NOT_SELECTED
};

static struct
{
	int state;
	int last_data;
	int pos;
	int transmit;
	uint8_t byte;
} i2c;

static struct
{
	uint8_t device_addr;

	int state;
	int addr;
	int rw;

	uint8_t ram[256];
	uint8_t rtc_ram[8];

	emu_timer_t timer;
} cmos;

static struct
{
	int msec;
	int sec;
	int min;
	int hour;
	int day;
	int mon;
	int year;
} systemtime;

static const int rtc_days_in_month[12] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};

static void cmos_get_time();

static int cmos_read_file(const char *path)
{
	FILE *cmosf = fopen(path, "rb");

	if (!cmosf)
		return 0;

	size_t bytes_read = fread(cmos.ram, 1, sizeof(cmos.ram), cmosf);
	fclose(cmosf);

	return (bytes_read == sizeof(cmos.ram));
}

static int cmos_ram_has_persistent_state(void)
{
	for (int i = 0; i < (int)sizeof(cmos.ram); i++)
	{
		/* Bytes 1-6 are refreshed from the host clock on every load. */
		if (i >= 1 && i <= 6)
			continue;
		if (cmos.ram[i] != 0)
			return 1;
	}

	return 0;
}

static int cmos_internal_drive_count(void)
{
	int count = 0;

	if (hd_fn[0][0])
		count++;
	if (hd_fn[1][0])
		count++;

	return count;
}

static void cmos_apply_internal_drive_defaults(void)
{
	int drive_count = cmos_internal_drive_count();
	uint8_t adfs_drives = cmos.ram[135];
	uint8_t selected_drive = cmos.ram[11] & 7;
	uint8_t new_adfs_drives = adfs_drives;

	if (fdctype == FDC_82C711)
	{
		new_adfs_drives &= ~0xC0;
		new_adfs_drives |= (drive_count & 0x03) << 6;
	}
	else if (st506_present)
	{
		new_adfs_drives &= ~0x38;
		new_adfs_drives |= (drive_count & 0x07) << 3;
	}

	if (new_adfs_drives != adfs_drives)
	{
		cmos.ram[135] = new_adfs_drives;
		cmos_changed = CMOS_CHANGE_DELAY;
	}

	if (drive_count > 0 && (selected_drive < 4 || selected_drive >= (4 + drive_count)))
	{
		cmos.ram[11] = (cmos.ram[11] & ~7) | 4;
		cmos_changed = CMOS_CHANGE_DELAY;
	}
}

void cmos_load()
{
	char fn[512];
	char fallback_fn[512];
	char cmos_name[512];
	int loaded = 0;

	LOG_CMOS("Read cmos %i\n", romset);
	snprintf(cmos_name, sizeof(cmos_name), "cmos/%s.%s.cmos.bin", machine_config_name, config_get_cmos_name(romset, fdctype));
	platform_path_join_support(fn, cmos_name, sizeof(fn));

	loaded = cmos_read_file(fn);
	if (loaded && cmos_ram_has_persistent_state())
	{
		LOG_CMOS("Read CMOS contents from %s\n", fn);
	}
	else
	{
		if (loaded)
			LOG_CMOS("%s is effectively empty; restoring bundled defaults\n", fn);
		else
			LOG_CMOS("%s doesn't exist; restoring bundled defaults\n", fn);

		snprintf(cmos_name, sizeof(cmos_name), "cmos/%s/cmos.bin", config_get_cmos_name(romset, fdctype));
		platform_path_join_resource(fallback_fn, cmos_name, sizeof(fallback_fn));

		if (cmos_read_file(fallback_fn))
		{
			LOG_CMOS("Read CMOS defaults from %s\n", fallback_fn);
			cmos_changed = CMOS_CHANGE_DELAY;
		}
		else
		{
			LOG_CMOS("%s doesn't exist; zeroing CMOS\n", fallback_fn);
			memset(cmos.ram, 0, 256);
		}
	}

	cmos_apply_internal_drive_defaults();
	cmos_get_time();
}

const uint8_t *cmos_get_ram_ptr(void)
{
	return cmos.ram;
}

void cmos_save()
{
	char fn[512];
	char cmos_name[512];
	FILE *cmosf;

	LOG_CMOS("Writing CMOS %i\n", romset);
	snprintf(cmos_name, sizeof(cmos_name), "cmos/%s.%s.cmos.bin", machine_config_name, config_get_cmos_name(romset, fdctype));
	platform_path_join_support(fn, cmos_name, sizeof(fn));

	LOG_CMOS("Writing %s\n", fn);
	cmosf = fopen(fn, "wb");
	if (!cmosf)
	{
		rpclog("cmos_save: failed to open %s\n", fn);
		return;
	}
	fwrite(cmos.ram, 256, 1, cmosf);
	fclose(cmosf);
}

static void cmos_stop()
{
	LOG_CMOS("cmos_stop()\n");
	cmos.state = CMOS_IDLE;
	i2c.transmit = TRANSMITTER_ARM;
}

static void cmos_next_byte()
{
	LOG_CMOS("cmos_next_byte(%d)\n", cmos.addr);
	if (!machine_is_a500() || cmos.device_addr == 0xa0)
		i2c.byte = cmos.ram[(cmos.addr++) & 0xFF];
	else if (machine_is_a500() && cmos.device_addr == 0xd0)
	{
		if (!(cmos.addr & 0x70))
		{
			i2c.byte = cmos.rtc_ram[cmos.addr & 0x07];
			cmos.addr = (cmos.addr & 0x70) | ((cmos.addr + 1) & 7);
		}
		else
			i2c.byte = 0;
//                rpclog(" read RTC %02x %02x\n", cmos.addr-1, i2c.byte);
	}
}

static void cmos_get_time()
{
	int c, d;

	LOG_CMOS("cmos_get_time()\n");

	if (machine_is_a500())
	{
		d = systemtime.hour % 10;
		c = systemtime.hour / 10;
		cmos.rtc_ram[0] = d | (c << 4);
		d = systemtime.min % 10;
		c = systemtime.min / 10;
		cmos.rtc_ram[1] = d | (c << 4);
		d = systemtime.day % 10;
		c = systemtime.day / 10;
		cmos.rtc_ram[2] = d | (c << 4);
		d = systemtime.mon % 10;
		c = systemtime.mon / 10;
		cmos.rtc_ram[3] = d | (c << 4);
	}
	else
	{
		c = systemtime.msec / 10;
		d = c % 10;
		c /= 10;
		cmos.ram[1] = d | (c << 4);
		d = systemtime.sec % 10;
		c = systemtime.sec / 10;
		cmos.ram[2] = d | (c << 4);
		d = systemtime.min % 10;
		c = systemtime.min / 10;
		cmos.ram[3] = d | (c << 4);
		d = systemtime.hour % 10;
		c = systemtime.hour / 10;
		cmos.ram[4] = d | (c << 4);
		d = systemtime.day % 10;
		c = systemtime.day / 10;
		cmos.ram[5] = d | (c << 4);
		d = systemtime.mon % 10;
		c = systemtime.mon / 10;
		cmos.ram[6] = d | (c << 4);
//                LOG_CMOS("Read time - %02X %02X %02X %02X %02X %02X\n",cmosram[1],cmosram[2],cmosram[3],cmosram[4],cmosram[5],cmosram[6]);
	}
}

static void cmos_tick(void *p)
{
	timer_advance_u64(&cmos.timer, TIMER_USEC * 10000); /*10ms*/

	systemtime.msec += 10;
	if (systemtime.msec >= 1000)
	{
		systemtime.msec = 0;
		systemtime.sec++;
		if (systemtime.sec >= 60)
		{
			systemtime.sec = 0;
			systemtime.min++;
			if (systemtime.min >= 60)
			{
				systemtime.min = 0;
				systemtime.hour++;
				if (systemtime.hour >= 24)
				{
					systemtime.hour = 0;
					systemtime.day++;
					if (systemtime.day > rtc_days_in_month[systemtime.mon])
					{
						systemtime.day = 1;
						systemtime.mon++;
						if (systemtime.mon > 12)
						{
							systemtime.mon = 1;
							systemtime.year++;
						}
					}
				}
			}
		}
	}
}

void cmos_init()
{
#ifdef WIN32
	SYSTEMTIME real_time;

	GetLocalTime(&real_time);
	systemtime.msec = real_time.wMilliseconds;
	systemtime.sec = real_time.wSecond;
	systemtime.min = real_time.wMinute;
	systemtime.hour = real_time.wHour;
	systemtime.day = real_time.wDay;
	systemtime.mon = real_time.wMonth;
	systemtime.year = real_time.wYear;
#else
	struct tm *cur_time_tm;
	time_t cur_time;

	time(&cur_time);
	cur_time_tm = localtime(&cur_time);

	systemtime.msec = 0;
	systemtime.sec = cur_time_tm->tm_sec;
	systemtime.min = cur_time_tm->tm_min;
	systemtime.hour = cur_time_tm->tm_hour;
	systemtime.day = cur_time_tm->tm_mday;
	systemtime.mon = cur_time_tm->tm_mon + 1;
	systemtime.year = cur_time_tm->tm_year + 1900;
#endif

	timer_add(&cmos.timer, cmos_tick, NULL, 1);
}

void cmos_write(uint8_t byte)
{
	LOG_CMOS("cmos_write()\n");
	switch (cmos.state)
	{
		case CMOS_IDLE:
		cmos.rw = byte & 1;
		/*A500 has PCF8570 EEPROM at 0xa0, PCF8573 RTC at 0xd0
		  Production machines have PCF8583 at 0xa0*/
		cmos.device_addr = byte & 0xfe;
//                rpclog("CMOS addr %02x\n", byte);
		if (cmos.device_addr == 0xa0 ||
				(cmos.device_addr == 0xa2 && machine_type == MACHINE_TYPE_A4) ||
				(cmos.device_addr == 0xd0 && machine_is_a500()))
		{
			if (cmos.rw)
			{
				cmos.state = CMOS_SENDDATA;
				i2c.transmit = TRANSMITTER_CMOS;
				if (cmos.device_addr == 0xa0)
				{
					if (!machine_is_a500() && (cmos.addr < 0x10))
						cmos_get_time();
					i2c.byte = cmos.ram[(cmos.addr++) & 0xFF];
				}
				else if (cmos.device_addr == 0xa2 && machine_type == MACHINE_TYPE_A4)
				{
					i2c.byte = bmu_read(cmos.addr);
					cmos.addr++;
				}
				else if (cmos.device_addr == 0xd0 && machine_is_a500())
				{
					cmos_get_time();
					if (!(cmos.addr & 0x70))
					{
						i2c.byte = cmos.rtc_ram[cmos.addr & 0x07];
						cmos.addr = (cmos.addr & 0x70) | ((cmos.addr + 1) & 7);
					}
					else
						i2c.byte = 0;
//                                        rpclog(" read RTC %02x %02x\n", cmos.addr-1, i2c.byte);
				}
//printf("CMOS - %02X from %02X\n",i2cbyte,cmosaddr-1);
//                        log("Transmitter now CMOS\n");
			}
			else
			{
				cmos.state = CMOS_RECEIVEADDR;
				i2c.transmit = TRANSMITTER_ARM;
			}
		}
		else
		{
			cmos.state = CMOS_NOT_SELECTED;
			i2c.byte = 0xff;
		}
//                log("CMOS R/W=%i\n",cmosrw);
		return;

		case CMOS_RECEIVEADDR:
//                printf("CMOS addr=%02X\n",byte);
//                log("CMOS addr=%02X\n",byte);
		cmos.addr = byte;
		if (cmos.rw)
			cmos.state = CMOS_SENDDATA;
		else
			cmos.state = CMOS_RECEIVEDATA;
		break;

		case CMOS_RECEIVEDATA:
//                printf("CMOS write %02X %02X\n",cmosaddr,byte);
//                log("%02X now %02X\n",cmosaddr,byte);
		if (cmos.device_addr == 0xa0)
		{
			if (!cmos_changed)
				cmos_changed = CMOS_CHANGE_DELAY;
			cmos.ram[(cmos.addr++) & 0xFF] = byte;
		}
		else if (cmos.device_addr == 0xa2 && machine_type == MACHINE_TYPE_A4)
		{
			bmu_write(cmos.addr, byte);
			cmos.addr++;
		}
		else if (cmos.device_addr == 0xd0 && machine_is_a500())
		{
//                        rpclog(" write RTC %02x %02x\n", cmos.addr, byte);
			if (!(cmos.addr & 0x70))
			{
				cmos.rtc_ram[cmos.addr & 0x07] = byte;
				cmos.addr = (cmos.addr & 0x70) | ((cmos.addr + 1) & 7);
			}
		}
		break;

		case CMOS_SENDDATA:
#ifndef RELEASE_BUILD
		fatal("Send data %02X\n", cmos.addr);
#endif
		break;
	}
}

void i2c_change(int new_clock, int new_data)
{
//        printf("I2C %i %i %i %i  %i\n",i2cclock,nuclock,i2cdata,nudata,i2cstate);
//        log("I2C update clock %i %i data %i %i state %i\n",i2cclock,nuclock,i2cdata,nudata,i2cstate);
	switch (i2c.state)
	{
		case I2C_IDLE:
		if (i2c_clock && new_clock)
		{
			if (i2c.last_data && !new_data) /*Start bit*/
			{
//                                printf("Start bit\n");
//                                log("Start bit received\n");
				i2c.state = I2C_RECEIVE;
				i2c.pos = 0;
			}
		}
		break;

		case I2C_RECEIVE:
		if (!i2c_clock && new_clock)
		{
//                        printf("Reciving %07X %07X\n",(*armregs[15]-8)&0x3FFFFFC,(*armregs[14]-8)&0x3FFFFFC);
			i2c.byte <<= 1;
			if (new_data)
				i2c.byte |= 1;
			else
				i2c.byte &= 0xFE;
			i2c.pos++;
			if (i2c.pos == 8)
			{

//                                if (output) //logfile("Complete - byte %02X %07X %07X\n",i2cbyte,(*armregs[15]-8)&0x3FFFFFC,(*armregs[14]-8)&0x3FFFFFC);
				cmos_write(i2c.byte);
				i2c.state = I2C_ACKNOWLEDGE;
			}
		}
		else if (i2c_clock && new_clock && new_data && !i2c.last_data) /*Stop bit*/
		{
//                        log("Stop bit received\n");
			i2c.state = I2C_IDLE;
			cmos_stop();
		}
		else if (i2c_clock && new_clock && !new_data && i2c.last_data) /*Start bit*/
		{
//                        log("Start bit received\n");
			i2c.pos = 0;
			cmos.state = CMOS_IDLE;
		}
		break;

		case I2C_ACKNOWLEDGE:
		if (!i2c_clock && new_clock)
		{
//                        log("Acknowledging transfer\n");
			new_data = 0;
			i2c.pos = 0;
			if (i2c.transmit == TRANSMITTER_ARM)
				i2c.state = I2C_RECEIVE;
			else
				i2c.state = I2C_TRANSMIT;
		}
		break;

		case I2C_TRANSACKNOWLEDGE:
		if (!i2c_clock && new_clock)
		{
			if (new_data) /*It's not acknowledged - must be end of transfer*/
			{
//                                printf("End of transfer\n");
				i2c.state = I2C_IDLE;
				cmos_stop();
			}
			else /*Next byte to transfer*/
			{
				i2c.state = I2C_TRANSMIT;
				cmos_next_byte();
				i2c.pos = 0;
//                                printf("Next byte - %02X\n",i2cbyte);
			}
		}
		break;

		case I2C_TRANSMIT:
		if (!i2c_clock && new_clock)
		{
			i2c_data = new_data = i2c.byte & 128;
			i2c.byte <<= 1;
			i2c.pos++;
//                        if (output) //logfile("Transfering bit at %07X %i %02X\n",(*armregs[15]-8)&0x3FFFFFC,i2cpos,cmosaddr);
			if (i2c.pos == 8)
			{
				i2c.state = I2C_TRANSACKNOWLEDGE;
//                                printf("Acknowledge mode\n");
			}
			i2c_clock = new_clock;
			return;
		}
		break;

	}
	if (!i2c_clock && new_clock)
		i2c_data = new_data;
	i2c.last_data = new_data;
	i2c_clock = new_clock;
}

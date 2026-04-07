/*Arculator 2.2 by Sarah Walker
  Sound emulation*/
#include <math.h>
#include <string.h>
#include "arc.h"
#include "arm.h"
#include "config.h"
#include "ioc.h"
#include "memc.h"
#include "plat_sound.h"
#include "snapshot.h"
#include "snapshot_chunks.h"
#include "snapshot_subsystems.h"
#include "sound.h"
#include "timer.h"

int stereoimages[8];
int stereo;
int soundena;
int sound_gain = 0;

static emu_timer_t sound_timer;
static emu_timer_t sound_timer_100ms;
static uint64_t sound_timer_base_period; /*Time for 1 tick of sample base clock*/

static int16_t sound_in_buffer[256*1024*2];
static int16_t sound_out_buffer[4800*2];
static uint32_t samp_rp = 0, samp_wp = 0, samp_fp = 0;
static int SAMP_INC;

static int sample_period;
static uint64_t sample_16_time; /*Time for 16 bytes (1 fetch) to be consumed by VIDC*/

static int sound_first_poll = 1;
static int sound_write_ptr;

static int sound_clock_mhz;
int sound_filter;

static double filter_freqs[] =
{
	2200.0, /*Original filter*/
	3200.0, /*Reduced*/
	5000.0  /*More reduced*/
};

static int16_t log_to_lin[256];

static int vollevels[2][2][8]=
{
	{
		{0,4,4,4,4,4,4,4},
		{0,4,4,4,4,4,4,4}
	},
	{
		{0,6,5,4,3,2,1,0},
		{0,0,1,2,3,4,5,6}
	}
};

static double ACoef[3];
static double BCoef[3];

static void iir_gen_coefficients(const int samplerate, const double cutoff, double* const ax, double* const by)
{
	double ff = cutoff/samplerate;
	const double ita = 1.0 / tan(M_PI*ff);
	const double q = sqrt(2.0);

	ax[0] = 1.0 / (1.0 + q*ita + ita*ita);
	ax[1]= 2*ax[0];
	ax[2]= ax[0];
	by[0] = 1.0;
	by[1] = -(2.0 * (ita*ita - 1.0) * ax[0]);
	by[2] = (1.0 - q*ita + ita*ita) * ax[0];
}

static int16_t iir_l(int16_t NewSample)
{
	static double y[3]; //output samples
	static double x[3]; //input samples

	//shift the old samples
	x[2] = x[1];
	y[2] = y[1];
	x[1] = x[0];
	y[1] = y[0];

	//Calculate the new output
	x[0] = (double)NewSample;
	y[0] = ACoef[0] * x[0];
	y[0] += ACoef[1] * x[1] - BCoef[1] * y[1];
	y[0] += ACoef[2] * x[2] - BCoef[2] * y[2];

	return (int16_t)y[0];
}
static int16_t iir_r(int16_t NewSample)
{
	static double y[3]; //output samples
	static double x[3]; //input samples

	//shift the old samples
	x[2] = x[1];
	y[2] = y[1];
	x[1] = x[0];
	y[1] = y[0];

	//Calculate the new output
	x[0] = (double)NewSample;
	y[0] = ACoef[0] * x[0];
	y[0] += ACoef[1] * x[1] - BCoef[1] * y[1];
	y[0] += ACoef[2] * x[2] - BCoef[2] * y[2];

	return (int16_t)y[0];
}


static void update_sound(int end_sample)
{
	if (end_sample > 2400)
		end_sample = 2400;

	if (sound_first_poll)
		return;
	if (!soundena)
		return;

//        rpclog("mixsound: samp_fp=%i samp_wp=%i samp_rp=%i %08x %08x\n", samp_fp, samp_wp, (samp_rp >> 15) * 2, samp_rp, SAMP_INC);
	while (samp_fp != samp_wp)
	{
		sound_in_buffer[samp_fp] = iir_l(sound_in_buffer[samp_fp]);
		samp_fp++;
		sound_in_buffer[samp_fp] = iir_r(sound_in_buffer[samp_fp]);
		samp_fp++;
		samp_fp &= 0x7fffe;
	}

	for (; sound_write_ptr < end_sample; sound_write_ptr++)
	{
		sound_out_buffer[sound_write_ptr*2]     = sound_in_buffer[(samp_rp >> 14) * 2];
		sound_out_buffer[sound_write_ptr*2 + 1] = sound_in_buffer[(samp_rp >> 14) * 2 + 1];
		samp_rp += SAMP_INC;
	}

}

static void pollsound_100ms(void *p)
{
	timer_advance_u64(&sound_timer_100ms, 50 * 1000 * TIMER_USEC);

	update_sound(2400);
	if (sound_first_poll)
		sound_first_poll = 0;

	sound_write_ptr = 0;
	if (soundena)
		sound_givebuffer(sound_out_buffer);
//        rpclog("          samp_fp=%i samp_wp=%i samp_rp=%i %08x %08x\n", samp_fp, samp_wp, (samp_rp >> 15) * 2, samp_rp, SAMP_INC);
}

void sound_set_clock(int clock_mhz)
{
	/*Write out samples up to this point*/
	uint64_t remaining = timer_get_remaining_u64(&sound_timer_100ms);
	int remaining_samples = (int)(((remaining / (50ull * 1000ull)) * 2400ull) / TIMER_USEC);

	update_sound(2400 - remaining_samples);

//        rpclog("sound_set_clock: clock_mhz=%i\n", clock_mhz);
	/*Update constants for new clock frequency*/
	sound_timer_base_period = (TIMER_USEC * 1000000) / clock_mhz;
	sample_16_time = sample_period * 16 * sound_timer_base_period;
	SAMP_INC = ((int)(((double)clock_mhz / 48000.0) * 16384.0));
//        rpclog("  SAMP_INC=%08x  sample_16_time=%016llx  sound_timer_base_period=%016llx\n", SAMP_INC, sample_16_time, sound_timer_base_period);

	iir_gen_coefficients(clock_mhz, filter_freqs[sound_filter], ACoef, BCoef);

	sound_clock_mhz = clock_mhz;
}

void sound_update_filter(void)
{
	iir_gen_coefficients(sound_clock_mhz, filter_freqs[sound_filter], ACoef, BCoef);
}

void sound_set_period(int period)
{
//        rpclog("sound_set_period: period=%i\n", period);
	sample_period = period;
	sample_16_time = period * 16 * sound_timer_base_period;
}

static void pollsound(void *p)
{
	uint8_t in_samples[16];
	int c;

	timer_advance_u64(&sound_timer, sample_16_time);

	/*Read in new samples*/
	if (sdmaena)
	{
		memcpy(in_samples, &ram[(spos & 0x7fff0) >> 2], 16);
		memc_dma_sound_req_ts = tsc;
		memc_dma_sound_req = 1;
		recalc_min_timer();
//                rpclog("pollsound: spos=%05x   %02x %02x %02x %02x  samp_wp=%i\n", spos, in_samples[0], in_samples[1], in_samples[2], in_samples[3], samp_wp);
	}
	else
		memset(in_samples, 0, 16);

	/*Upsample to VIDC frequency buffer*/
	for (c = 0; c < 16; c++)
	{
		int d;
		int16_t sample_l, sample_r;
		int16_t sample = log_to_lin[in_samples[c]];

		sample_l = sample * vollevels[stereo][0][stereoimages[c & 7]];
		sample_r = sample * vollevels[stereo][1][stereoimages[c & 7]];

		for (d = 0; d < sample_period; d++)
		{
			sound_in_buffer[samp_wp++] = sample_l;
			sound_in_buffer[samp_wp++] = sample_r;
			samp_wp &= 0x7fffe;
		}
	}

	if (sdmaena)
	{
		if (spos == ssend)
		{
			if (nextvalid == 2)
			{
				spos = sstart2 = sstart << 2;
				ssend = sendN << 2;
				nextvalid = 0;
			}
			else
				spos = sstart2;
			ioc_irqb(IOC_IRQB_SOUND_BUFFER);
		}
		else
			spos = (spos + 16) & 0x7fff0;
	}
}

static signed short convbyte(uint8_t v)
{
	int sign, point, chord;
	signed short temp;

	//                         7C       chord = 3     p = E/14
	if (fdctype == FDC_WD1793_A500)
	{
		sign = v & 0x80;
		point = v & 0xf;
		chord = (v >> 4) & 7;
	}
	else
	{
		sign = v & 1;
		point = (v >> 1) & 0xf;
		chord = v >> 5;

	}

	temp = (1 << (chord + 4)) - (1 << 4);
	temp += (point << chord);
	return sign ? - temp : temp;
}

void sound_init(void)
{
	int c;

	for (c = 0; c < 256; c++)
		log_to_lin[c] = convbyte(c);

	timer_add(&sound_timer, pollsound, NULL, 1);
	timer_add(&sound_timer_100ms, pollsound_100ms, NULL, 1);
	sound_first_poll = 1;
	SAMP_INC = ((int)((1000000.0 / 48000.0) * 16384.0));

	samp_rp = 0xff000000;
	samp_wp = 0;
	samp_fp = 0;
}

/* ----- Snapshot save/load -------------------------------------------- *
 *
 * Saves the live VIDC sound state machine and the upsampler buffer
 * pointers. The IIR filter history lives in function-local statics
 * inside iir_l() / iir_r() and is NOT serialised — it relaxes back
 * within a few samples after load. Host audio buffers are never
 * snapshotted; the next pollsound_100ms() naturally writes a fresh
 * 50ms output buffer.
 */

#define SND_STATE_VERSION 1u

int sound_save_state(snapshot_writer_t *w)
{
	if (!snapshot_writer_begin_chunk(w, ARCSNAP_CHUNK_SND, SND_STATE_VERSION))
		return 0;

	if (!snapshot_writer_append_i32(w, sample_period))    goto fail;
	if (!snapshot_writer_append_u64(w, sample_16_time))   goto fail;
	if (!snapshot_writer_append_u64(w, sound_timer_base_period)) goto fail;
	if (!snapshot_writer_append_i32(w, SAMP_INC))         goto fail;
	if (!snapshot_writer_append_u32(w, samp_rp))          goto fail;
	if (!snapshot_writer_append_u32(w, samp_wp))          goto fail;
	if (!snapshot_writer_append_u32(w, samp_fp))          goto fail;
	if (!snapshot_writer_append_i32(w, sound_first_poll)) goto fail;
	if (!snapshot_writer_append_i32(w, sound_write_ptr))  goto fail;
	if (!snapshot_writer_append_i32(w, sound_clock_mhz))  goto fail;
	if (!snapshot_writer_append_i32(w, sound_filter))     goto fail;
	if (!snapshot_writer_append_i32(w, sound_gain))       goto fail;

	if (!snapshot_writer_append_u32(w, sound_timer.ts_integer)) goto fail;
	if (!snapshot_writer_append_u32(w, sound_timer.ts_frac))    goto fail;
	if (!snapshot_writer_append_i32(w, sound_timer.enabled))    goto fail;
	if (!snapshot_writer_append_u32(w, sound_timer_100ms.ts_integer)) goto fail;
	if (!snapshot_writer_append_u32(w, sound_timer_100ms.ts_frac))    goto fail;
	if (!snapshot_writer_append_i32(w, sound_timer_100ms.enabled))    goto fail;

	return snapshot_writer_end_chunk(w);

fail:
	return 0;
}

int sound_load_state(snapshot_payload_reader_t *r, uint32_t version)
{
	int32_t  loaded_sample_period, loaded_samp_inc, loaded_first_poll;
	int32_t  loaded_write_ptr, loaded_clock_mhz, loaded_sound_filter, loaded_sound_gain;
	uint64_t loaded_sample_16_time, loaded_base_period;
	uint32_t loaded_samp_rp, loaded_samp_wp, loaded_samp_fp;
	uint32_t loaded_t1_int, loaded_t1_frac, loaded_t2_int, loaded_t2_frac;
	int32_t  loaded_t1_ena, loaded_t2_ena;

	(void)version;

	if (!snapshot_payload_reader_read_i32(r, &loaded_sample_period))   return 0;
	if (!snapshot_payload_reader_read_u64(r, &loaded_sample_16_time))  return 0;
	if (!snapshot_payload_reader_read_u64(r, &loaded_base_period))     return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_samp_inc))        return 0;
	if (!snapshot_payload_reader_read_u32(r, &loaded_samp_rp))         return 0;
	if (!snapshot_payload_reader_read_u32(r, &loaded_samp_wp))         return 0;
	if (!snapshot_payload_reader_read_u32(r, &loaded_samp_fp))         return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_first_poll))      return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_write_ptr))       return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_clock_mhz))       return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_sound_filter))    return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_sound_gain))      return 0;

	if (!snapshot_payload_reader_read_u32(r, &loaded_t1_int))   return 0;
	if (!snapshot_payload_reader_read_u32(r, &loaded_t1_frac))  return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_t1_ena))   return 0;
	if (!snapshot_payload_reader_read_u32(r, &loaded_t2_int))   return 0;
	if (!snapshot_payload_reader_read_u32(r, &loaded_t2_frac))  return 0;
	if (!snapshot_payload_reader_read_i32(r, &loaded_t2_ena))   return 0;

	sample_period           = (int)loaded_sample_period;
	sample_16_time          = loaded_sample_16_time;
	sound_timer_base_period = loaded_base_period;
	SAMP_INC                = (int)loaded_samp_inc;
	samp_rp                 = loaded_samp_rp;
	samp_wp                 = loaded_samp_wp;
	samp_fp                 = loaded_samp_fp;
	sound_first_poll        = (int)loaded_first_poll;
	sound_write_ptr         = (int)loaded_write_ptr;
	sound_clock_mhz         = (int)loaded_clock_mhz;
	sound_filter            = (int)loaded_sound_filter;
	sound_gain              = (int)loaded_sound_gain;

	/* Recompute filter coefficients for the restored clock+filter
	 * (this is normally done by sound_set_clock()). */
	if (sound_clock_mhz)
		iir_gen_coefficients(sound_clock_mhz,
		                     filter_freqs[sound_filter],
		                     ACoef, BCoef);

	/* In-flight upsampler buffers are intentionally not serialised; the
	 * sample read pointer keeps walking the (zeroed) buffer until the
	 * next pollsound() refills it from RAM. */
	memset(sound_in_buffer,  0, sizeof(sound_in_buffer));
	memset(sound_out_buffer, 0, sizeof(sound_out_buffer));

	timer_restore(&sound_timer,       loaded_t1_int, loaded_t1_frac, (int)loaded_t1_ena);
	timer_restore(&sound_timer_100ms, loaded_t2_int, loaded_t2_frac, (int)loaded_t2_ena);
	return 1;
}

/*
 * Snapshot loader: runtime bundle preparation and per-subsystem state
 * dispatch.
 *
 * Kept separate from snapshot.c so the standalone format tests don't
 * have to link against config / platform_paths / per-subsystem
 * load_state symbols.
 */

#include "snapshot.h"
#include "snapshot_chunks.h"
#include "snapshot_internal.h"
#include "snapshot_subsystems.h"

#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>
#include <unistd.h>

#include "arc.h"
#include "arm.h"
#include "config.h"
#include "platform_paths.h"
#include "timer.h"

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#define SNAPSHOT_RUNTIME_NAME_PREFIX "__snapshot_"

/* Generates a 16-char lowercase hex token, unique per load session.
 * Mixes gettimeofday(), getpid(), and a monotonic counter rather than
 * touching the global rand() state that other parts of the emulator
 * consume. */
static void generate_runtime_id_hex(char out[17])
{
	static uint64_t counter = 0;
	struct timeval tv;
	uint64_t seed;

	if (gettimeofday(&tv, NULL) != 0)
	{
		tv.tv_sec = 0;
		tv.tv_usec = 0;
	}

	seed =  ((uint64_t)tv.tv_sec  * 1000003ULL) ^
	        ((uint64_t)tv.tv_usec * 0x9e3779b97f4a7c15ULL) ^
	        (uint64_t)getpid() ^
	        (counter++ * 0xbf58476d1ce4e5b9ULL);
	seed ^= seed >> 30;
	seed *= 0xbf58476d1ce4e5b9ULL;
	seed ^= seed >> 27;

	snprintf(out, 17, "%016llx", (unsigned long long)seed);
}

/* ----- file helpers --------------------------------------------------- */

static int write_file(const char *path, const void *data, size_t size,
                      char *err, size_t err_size)
{
	FILE *fp = fopen(path, "wb");
	if (!fp)
	{
		set_errorf(err, err_size,
		           "cannot create '%s': %s", path, strerror(errno));
		return 0;
	}
	if (size && fwrite(data, 1, size, fp) != size)
	{
		int saved_errno = errno;
		fclose(fp);
		remove(path);
		set_errorf(err, err_size,
		           "write to '%s' failed: %s", path, strerror(saved_errno));
		return 0;
	}
	if (fclose(fp))
	{
		int saved_errno = errno;
		remove(path);
		set_errorf(err, err_size,
		           "close of '%s' failed: %s", path, strerror(saved_errno));
		return 0;
	}
	return 1;
}

#define DEFAULT_DISC_EXTENSION "adf"

/* Copies a sanitised extension (alnum only, max 15 chars) into dest,
 * falling back to DEFAULT_DISC_EXTENSION if src is NULL/empty/all
 * non-alnum. */
static void sanitize_extension(char *dest, size_t dest_size, const char *src)
{
	size_t i, o = 0;
	if (!dest || dest_size < 2)
		return;
	if (src)
	{
		for (i = 0; src[i] && o + 1 < dest_size && o < 15; i++)
		{
			char c = src[i];
			if ((c >= 'a' && c <= 'z') ||
			    (c >= 'A' && c <= 'Z') ||
			    (c >= '0' && c <= '9'))
				dest[o++] = c;
		}
	}
	if (!o)
	{
		snprintf(dest, dest_size, DEFAULT_DISC_EXTENSION);
		return;
	}
	dest[o] = 0;
}

/* Resolve a manifest floppy entry by drive index. Returns NULL if the
 * drive isn't listed. */
static const arcsnap_manifest_floppy_t *
floppy_for_drive(const arcsnap_manifest_t *manifest, int drive_index)
{
	int i;
	for (i = 0; i < manifest->floppy_count; i++)
	{
		if (manifest->floppies[i].drive_index == drive_index)
			return &manifest->floppies[i];
	}
	return NULL;
}

/* ----- prepare_runtime ------------------------------------------------ */

int snapshot_prepare_runtime(snapshot_load_ctx_t *ctx,
                             char *runtime_dir_out, size_t runtime_dir_out_len,
                             char *runtime_config_out, size_t runtime_config_out_len,
                             char *runtime_name_out, size_t runtime_name_out_len,
                             char *err, size_t err_size)
{
	char runtime_dir[PATH_MAX];
	char runtime_config[PATH_MAX];
	char runtime_name[64];
	char id_hex[17];
	char disc_paths[4][PATH_MAX];
	int  drive_has_media[4] = {0};
	int cfg_extracted = 0;
	size_t cursor_before_chunk;
	uint32_t id_cc, version;
	const uint8_t *payload;
	uint64_t payload_size;
	int rc;
	char disc_key[32];
	int c;

	if (err && err_size)
		err[0] = 0;

	if (!ctx || !ctx->reader || !ctx->manifest_loaded)
	{
		set_error(err, err_size, "snapshot context not initialised");
		return 0;
	}

	generate_runtime_id_hex(id_hex);
	snprintf(runtime_name, sizeof(runtime_name),
	         SNAPSHOT_RUNTIME_NAME_PREFIX "%s", id_hex);
	platform_path_snapshot_runtime_dir(runtime_dir, sizeof(runtime_dir),
	                                   id_hex);
	snprintf(runtime_config, sizeof(runtime_config),
	         "%s/machine.cfg", runtime_dir);

	snapshot_reader_set_cursor(ctx->reader, ctx->post_manifest_cursor);

	for (;;)
	{
		cursor_before_chunk = snapshot_reader_cursor(ctx->reader);
		rc = snapshot_reader_next_chunk(ctx->reader, &id_cc, &version,
		                                &payload, &payload_size,
		                                err, err_size);
		if (rc < 0)
			return 0;
		if (rc == 0)
			break;

		if (id_cc == ARCSNAP_CHUNK_CFG)
		{
			if (cfg_extracted)
			{
				set_error(err, err_size,
				          "snapshot contains duplicate CFG chunk");
				return 0;
			}
			if (!write_file(runtime_config, payload,
			                (size_t)payload_size, err, err_size))
				return 0;
			cfg_extracted = 1;
		}
		else if (id_cc == ARCSNAP_CHUNK_MEDA)
		{
			snapshot_payload_reader_t pr;
			int32_t drive_index;
			const arcsnap_manifest_floppy_t *floppy;
			char ext[16];

			snapshot_payload_reader_init(&pr, payload,
			                             (size_t)payload_size);
			if (!snapshot_payload_reader_read_i32(&pr, &drive_index))
			{
				set_error(err, err_size,
				          "snapshot MEDA chunk is truncated");
				return 0;
			}
			if (drive_index < 0 || drive_index >= 4)
			{
				set_errorf(err, err_size,
				           "snapshot MEDA chunk has invalid drive index %d",
				           (int)drive_index);
				return 0;
			}
			if (drive_has_media[drive_index])
			{
				set_errorf(err, err_size,
				           "snapshot has duplicate MEDA chunk for drive %d",
				           (int)drive_index);
				return 0;
			}

			floppy = floppy_for_drive(&ctx->manifest, (int)drive_index);
			sanitize_extension(ext, sizeof(ext),
			                   floppy ? floppy->extension : NULL);
			snprintf(disc_paths[drive_index], PATH_MAX,
			         "%s/disc%d.%s", runtime_dir, (int)drive_index, ext);
			if (!write_file(disc_paths[drive_index],
			                payload + pr.cursor,
			                (size_t)payload_size - pr.cursor,
			                err, err_size))
				return 0;
			drive_has_media[drive_index] = 1;
		}
		else if (id_cc == ARCSNAP_CHUNK_PREV)
		{
			/* Screenshot preview: not needed by the loader. */
		}
		else
		{
			snapshot_reader_set_cursor(ctx->reader, cursor_before_chunk);
			break;
		}
	}

	if (!cfg_extracted)
	{
		set_error(err, err_size,
		          "snapshot is missing required CFG chunk");
		return 0;
	}

	/* Rewrite disc_name_0..3 in the extracted config so arc_init()'s
	 * autoload picks up the isolated media. Drives without a MEDA
	 * chunk are blanked so the loader doesn't chase a stale path. */
	config_load(CFG_MACHINE, runtime_config);
	for (c = 0; c < 4; c++)
	{
		snprintf(disc_key, sizeof(disc_key), "disc_name_%d", c);
		config_set_string(CFG_MACHINE, NULL, disc_key,
		                  drive_has_media[c] ? disc_paths[c] : "");
	}
	config_save(CFG_MACHINE, runtime_config);

	ctx->state_chunks_cursor = snapshot_reader_cursor(ctx->reader);

	if (runtime_dir_out && runtime_dir_out_len)
		snprintf(runtime_dir_out, runtime_dir_out_len, "%s", runtime_dir);
	if (runtime_config_out && runtime_config_out_len)
		snprintf(runtime_config_out, runtime_config_out_len, "%s",
		         runtime_config);
	if (runtime_name_out && runtime_name_out_len)
		snprintf(runtime_name_out, runtime_name_out_len, "%s", runtime_name);
	return 1;
}

/* ----- apply_machine_state -------------------------------------------- */

/* Returns 1 on success, 0 on decode failure. Chunks for absent
 * subsystems (CP15, FPA, etc., gated on the runtime config) and
 * unknown chunk ids are tolerated as no-ops so a snapshot from a
 * config that no longer needs a subsystem still loads cleanly, and so
 * future writers can add new chunks without breaking old readers. */
static int dispatch_chunk(uint32_t id, uint32_t version,
                          const uint8_t *payload, uint64_t payload_size)
{
	snapshot_payload_reader_t pr;

	snapshot_payload_reader_init(&pr, payload, (size_t)payload_size);

	switch (id)
	{
	case ARCSNAP_CHUNK_CPU:  return arm_load_state(&pr, version);
	case ARCSNAP_CHUNK_CP15: return arm_has_cp15 ? cp15_load_state(&pr, version) : 1;
	case ARCSNAP_CHUNK_FPA:  return fpaena ? fpa_load_state(&pr, version) : 1;
	case ARCSNAP_CHUNK_MEM:  return mem_load_state(&pr, version);
	case ARCSNAP_CHUNK_MEMC: return memc_load_state(&pr, version);
	case ARCSNAP_CHUNK_IOC:  return ioc_load_state(&pr, version);
	case ARCSNAP_CHUNK_VIDC: return vidc_load_state(&pr, version);
	case ARCSNAP_CHUNK_KBD:  return keyboard_load_state(&pr, version);
	case ARCSNAP_CHUNK_CMOS: return cmos_load_state(&pr, version);
	case ARCSNAP_CHUNK_DS24: return ds2401_load_state(&pr, version);
	case ARCSNAP_CHUNK_SND:  return sound_load_state(&pr, version);
	case ARCSNAP_CHUNK_IOEB: return ioeb_load_state(&pr, version);
	case ARCSNAP_CHUNK_LC:   return (machine_type == MACHINE_TYPE_A4) ? lc_load_state(&pr, version) : 1;
	case ARCSNAP_CHUNK_FDCW: return (fdctype != FDC_82C711) ? wd1770_load_state(&pr, version) : 1;
	case ARCSNAP_CHUNK_FDCS: return (fdctype == FDC_82C711) ? c82c711_fdc_load_state(&pr, version) : 1;
	case ARCSNAP_CHUNK_DISC: return disc_load_state(&pr, version);
	case ARCSNAP_CHUNK_TIMR: return timer_load_global(&pr, version);
	default:                 return 1;
	}
}

static void fourcc_to_str(uint32_t id, char out[5])
{
	out[0] = (char)(id        & 0xffu);
	out[1] = (char)((id >>  8) & 0xffu);
	out[2] = (char)((id >> 16) & 0xffu);
	out[3] = (char)((id >> 24) & 0xffu);
	out[4] = 0;
}

int snapshot_apply_machine_state(snapshot_load_ctx_t *ctx,
                                 char *err, size_t err_size)
{
	uint32_t id_cc, version;
	const uint8_t *payload;
	uint64_t payload_size;
	int rc;

	if (err && err_size)
		err[0] = 0;

	if (!ctx || !ctx->reader)
	{
		set_error(err, err_size, "snapshot context not initialised");
		return 0;
	}

	snapshot_reader_set_cursor(ctx->reader, ctx->state_chunks_cursor);

	for (;;)
	{
		rc = snapshot_reader_next_chunk(ctx->reader, &id_cc, &version,
		                                &payload, &payload_size,
		                                err, err_size);
		if (rc < 0)
			return 0;
		if (rc == 0)
			break;

		if (id_cc == ARCSNAP_CHUNK_END)
			break;

		if (!dispatch_chunk(id_cc, version, payload, payload_size))
		{
			char tag[5];
			fourcc_to_str(id_cc, tag);
			set_errorf(err, err_size,
			           "failed to apply '%s' chunk (truncated or malformed)",
			           tag);
			return 0;
		}
	}

	return 1;
}

/*
 * Snapshot session: save orchestration, runtime bundle preparation,
 * and per-subsystem state dispatch on load.
 *
 * Kept separate from snapshot.c so the standalone format tests don't
 * have to link against config / platform_paths / per-subsystem
 * save_state / load_state symbols.
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
#include "disc.h"
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
		else if (id_cc == ARCSNAP_CHUNK_META)
		{
			/* Descriptive metadata: informational only, skipped
			 * by the runtime-preparation pass. */
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

/* ----- snapshot_save -------------------------------------------------- *
 *
 * Orchestrates writing the full .arcsnap file. Runs on the emulation
 * thread while paused, so the machine state is quiescent and safe to
 * read directly. Order matches the fixed save order documented in the
 * implementation plan; the reader tolerates order and skips unknown
 * chunks, but keeping save order stable helps diffing and debugging.
 */

static int read_file_contents(const char *path, uint8_t **out_buf,
                              size_t *out_size, char *err, size_t err_size)
{
	FILE *fp;
	long size_long;
	size_t size;
	uint8_t *buf;

	*out_buf = NULL;
	*out_size = 0;

	fp = fopen(path, "rb");
	if (!fp)
	{
		set_errorf(err, err_size,
		           "cannot open '%s': %s", path, strerror(errno));
		return 0;
	}
	if (fseek(fp, 0, SEEK_END) != 0)
	{
		fclose(fp);
		set_errorf(err, err_size, "cannot seek '%s'", path);
		return 0;
	}
	size_long = ftell(fp);
	if (size_long < 0)
	{
		fclose(fp);
		set_errorf(err, err_size, "cannot size '%s'", path);
		return 0;
	}
	rewind(fp);

	size = (size_t)size_long;
	buf = (uint8_t *)malloc(size ? size : 1);
	if (!buf)
	{
		fclose(fp);
		set_error(err, err_size, "out of memory");
		return 0;
	}
	if (size && fread(buf, 1, size, fp) != size)
	{
		free(buf);
		fclose(fp);
		set_errorf(err, err_size, "read of '%s' failed", path);
		return 0;
	}
	fclose(fp);

	*out_buf = buf;
	*out_size = size;
	return 1;
}

/* Copies the last extension of `path` (without the dot) into `dest`.
 * Writes an empty string if no extension is found. */
static void extract_extension(const char *path, char *dest, size_t dest_size)
{
	const char *slash, *dot;

	if (!dest || !dest_size)
		return;
	dest[0] = 0;
	if (!path)
		return;

	slash = strrchr(path, '/');
	dot = strrchr(path, '.');
	if (!dot || (slash && dot < slash))
		return;
	snprintf(dest, dest_size, "%s", dot + 1);
}

static int write_meda_chunk(snapshot_writer_t *w, int drive,
                            const uint8_t *bytes, size_t size)
{
	if (!snapshot_writer_begin_chunk(w, ARCSNAP_CHUNK_MEDA, 1u))
		return 0;
	snapshot_writer_append_i32(w, (int32_t)drive);
	if (size)
		snapshot_writer_append(w, bytes, size);
	return snapshot_writer_end_chunk(w);
}

/* Writes a chunk whose payload is a single contiguous byte buffer.
 * On failure sets `err` to "writer failed (<label> <stage>)" and
 * returns 0. */
static int write_data_chunk(snapshot_writer_t *w, uint32_t tag,
                            const uint8_t *bytes, size_t size,
                            const char *label,
                            char *err, size_t err_size)
{
	if (!snapshot_writer_begin_chunk(w, tag, 1u))
	{
		set_errorf(err, err_size, "writer failed (%s begin)", label);
		return 0;
	}
	if (size && !snapshot_writer_append(w, bytes, size))
	{
		set_errorf(err, err_size, "writer failed (%s payload)", label);
		return 0;
	}
	if (!snapshot_writer_end_chunk(w))
	{
		set_errorf(err, err_size, "writer failed (%s end)", label);
		return 0;
	}
	return 1;
}

static int save_subsystem_chunks(snapshot_writer_t *w)
{
	if (!arm_save_state(w)) return 0;
	if (arm_has_cp15 && !cp15_save_state(w)) return 0;
	if (fpaena && !fpa_save_state(w)) return 0;
	if (!mem_save_state(w)) return 0;
	if (!memc_save_state(w)) return 0;
	if (!ioc_save_state(w)) return 0;
	if (!vidc_save_state(w)) return 0;
	if (!keyboard_save_state(w)) return 0;
	if (!cmos_save_state(w)) return 0;
	if (!ds2401_save_state(w)) return 0;
	if (!sound_save_state(w)) return 0;
	if (!ioeb_save_state(w)) return 0;
	if (machine_type == MACHINE_TYPE_A4 && !lc_save_state(w)) return 0;
	if (fdctype != FDC_82C711)
	{
		if (!wd1770_save_state(w)) return 0;
	}
	else
	{
		if (!c82c711_fdc_save_state(w)) return 0;
	}
	if (!disc_save_state(w)) return 0;
	if (!timer_save_global(w)) return 0;

	if (!snapshot_writer_begin_chunk(w, ARCSNAP_CHUNK_END, 1u)) return 0;
	if (!snapshot_writer_end_chunk(w)) return 0;
	return 1;
}

static void fill_manifest(arcsnap_manifest_t *m,
                          const uint8_t *preview_png, size_t preview_png_size,
                          int preview_w, int preview_h)
{
	int i;

	memset(m, 0, sizeof(*m));
	m->version = ARCSNAP_MNFT_VERSION;

	snprintf(m->original_config_name, sizeof(m->original_config_name),
	         "%s", machine_config_name);
	snprintf(m->machine, sizeof(m->machine), "%s", machine);
	m->fdctype      = fdctype;
	m->romset       = romset;
	m->memsize      = memsize;
	m->machine_type = machine_type;

	if (arm_has_cp15) m->scope_flags |= ARCSNAP_SCOPE_HAS_CP15;
	if (fpaena)       m->scope_flags |= ARCSNAP_SCOPE_HAS_FPA;
	m->scope_flags |= ARCSNAP_SCOPE_HAS_IOEB;
	if (machine_type == MACHINE_TYPE_A4)
		m->scope_flags |= ARCSNAP_SCOPE_HAS_LC;
	if (preview_png && preview_png_size)
	{
		m->scope_flags |= ARCSNAP_SCOPE_HAS_PREV;
		m->preview_width  = preview_w;
		m->preview_height = preview_h;
	}

	m->floppy_count = 0;
	for (i = 0; i < 4 && m->floppy_count < ARCSNAP_MNFT_MAX_FLOPPIES; i++)
	{
		arcsnap_manifest_floppy_t *f;
		struct stat st;

		if (!discname[i][0])
			continue;

		f = &m->floppies[m->floppy_count++];
		f->drive_index = i;
		snprintf(f->original_path, sizeof(f->original_path),
		         "%s", discname[i]);
		f->file_size = 0;
		if (stat(discname[i], &st) == 0)
			f->file_size = (uint64_t)st.st_size;
		f->write_protect = writeprot[i];
		extract_extension(discname[i], f->extension, sizeof(f->extension));
	}
}

int snapshot_save(const char *path,
                  const uint8_t *preview_png, size_t preview_png_size,
                  int preview_w, int preview_h,
                  const arcsnap_meta_t *meta,
                  char *err, size_t err_size)
{
	snapshot_writer_t *w = NULL;
	arcsnap_manifest_t manifest;
	uint8_t *cfg_bytes = NULL;
	size_t   cfg_size  = 0;
	int      rc        = 0;
	int      i;

	if (err && err_size)
		err[0] = 0;

	if (!path || !path[0])
	{
		set_error(err, err_size, "no snapshot path");
		return 0;
	}

	/* Defensive re-check: the menu / UI guards against this already,
	 * but by the time we get to the emulation thread the state could
	 * have changed. */
	if (!snapshot_can_save(err, err_size))
		return 0;

	if (!machine_config_file[0])
	{
		set_error(err, err_size,
		          "no machine config file is loaded");
		return 0;
	}

	w = snapshot_writer_create();
	if (!w)
	{
		set_error(err, err_size, "out of memory");
		return 0;
	}
	if (!snapshot_writer_write_header(w))
	{
		set_error(err, err_size, "writer failed (header)");
		goto out;
	}

	fill_manifest(&manifest, preview_png, preview_png_size,
	              preview_w, preview_h);
	if (!snapshot_writer_write_manifest(w, &manifest))
	{
		set_error(err, err_size, "writer failed (manifest)");
		goto out;
	}

	if (!read_file_contents(machine_config_file, &cfg_bytes, &cfg_size,
	                        err, err_size))
		goto out;
	if (!write_data_chunk(w, ARCSNAP_CHUNK_CFG, cfg_bytes, cfg_size,
	                      "CFG", err, err_size))
		goto out;

	for (i = 0; i < 4; i++)
	{
		uint8_t *disc_bytes = NULL;
		size_t   disc_size  = 0;
		int      ok;

		if (!discname[i][0])
			continue;
		if (!read_file_contents(discname[i], &disc_bytes, &disc_size,
		                        err, err_size))
			goto out;
		ok = write_meda_chunk(w, i, disc_bytes, disc_size);
		free(disc_bytes);
		if (!ok)
		{
			set_errorf(err, err_size,
			           "writer failed (MEDA drive %d)", i);
			goto out;
		}
	}

	if (preview_png && preview_png_size)
	{
		if (!write_data_chunk(w, ARCSNAP_CHUNK_PREV,
		                      preview_png, preview_png_size,
		                      "PREV", err, err_size))
			goto out;
	}

	if (meta)
	{
		if (!snapshot_writer_write_meta(w, meta))
		{
			set_error(err, err_size, "writer failed (meta)");
			goto out;
		}
	}

	if (!save_subsystem_chunks(w))
	{
		set_error(err, err_size,
		          "writer failed (subsystem chunk; out of memory?)");
		goto out;
	}

	if (!snapshot_writer_save_to_file(w, path))
	{
		set_errorf(err, err_size,
		           "cannot write snapshot to '%s': %s",
		           path, strerror(errno));
		goto out;
	}

	rc = 1;

out:
	free(cfg_bytes);
	snapshot_writer_destroy(w);
	return rc;
}

/*
 * Snapshot loader: runtime bundle preparation and per-subsystem state
 * dispatch.
 *
 * Split out from snapshot.c so the standalone format tests can link
 * against snapshot.c without pulling in the full machine-config,
 * platform-paths, and per-subsystem load_state symbols.
 *
 * The loader's two entry points are intentionally public via
 * snapshot.h and are called in order:
 *
 *   1. snapshot_prepare_runtime() — called while the emulation is idle,
 *      before any arc_init() has been run. Materialises a private
 *      runtime directory under <support>/snapshots/runtime/<id>/
 *      containing an extracted machine.cfg and disc<N>.<ext> files,
 *      and rewrites disc_name_* in the extracted config so the normal
 *      arc_init() → loadconfig() → disc_load() chain picks up the
 *      isolated media.
 *
 *   2. snapshot_apply_machine_state() — called after arc_init() has
 *      built a fresh emulator against the rebased runtime config.
 *      Iterates the remaining chunks in the .arcsnap stream and
 *      dispatches each one to the owning subsystem's `*_load_state`
 *      entry point. End-of-stream is marked by an END chunk (if
 *      present) or simply by running out of chunks.
 */

#include "snapshot.h"
#include "snapshot_chunks.h"
#include "snapshot_internal.h"
#include "snapshot_subsystems.h"

#include <errno.h>
#include <limits.h>
#include <stdarg.h>
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

/* ----- error helpers -------------------------------------------------- */

static void set_error(char *buf, size_t buf_size, const char *msg)
{
	if (!buf || !buf_size)
		return;
	snprintf(buf, buf_size, "%s", msg ? msg : "");
}

static void set_errorf(char *buf, size_t buf_size, const char *fmt, ...)
{
	va_list args;
	if (!buf || !buf_size)
		return;
	va_start(args, fmt);
	vsnprintf(buf, buf_size, fmt, args);
	va_end(args);
}

/* ----- runtime-id generation ----------------------------------------- *
 *
 * We want a 16-character lowercase hex token, stable for the lifetime
 * of a single load session and collision-resistant enough that two
 * adjacent loads can't collide. We mix gettimeofday(), getpid(), and
 * a monotonically-increasing counter. This intentionally avoids
 * perturbing the global rand() state, which other parts of the
 * emulator consume. */

static void format_hex64(char out[17], uint64_t value)
{
	static const char hex[] = "0123456789abcdef";
	int i;
	for (i = 15; i >= 0; i--)
	{
		out[i] = hex[value & 0xfu];
		value >>= 4;
	}
	out[16] = 0;
}

static void generate_runtime_id(char out[64])
{
	static uint64_t counter = 0;
	struct timeval tv;
	uint64_t seed;
	char hex[17];

	if (gettimeofday(&tv, NULL) != 0)
	{
		tv.tv_sec = 0;
		tv.tv_usec = 0;
	}

	seed =  ((uint64_t)tv.tv_sec  * 1000003ULL) ^
	        ((uint64_t)tv.tv_usec * 0x9e3779b97f4a7c15ULL) ^
	        ((uint64_t)(uintptr_t)&counter) ^
	        (uint64_t)getpid() ^
	        (counter++ * 0xbf58476d1ce4e5b9ULL);

	/* One extra round of mixing so adjacent counter values don't
	 * produce obviously sequential tokens. */
	seed ^= seed >> 30;
	seed *= 0xbf58476d1ce4e5b9ULL;
	seed ^= seed >> 27;
	seed *= 0x94d049bb133111ebULL;
	seed ^= seed >> 31;

	format_hex64(hex, seed);
	snprintf(out, 64, "__snapshot_%s", hex);
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

static int sanitize_extension(char *dest, size_t dest_size, const char *src)
{
	size_t i, o = 0;
	if (!dest || dest_size < 2)
		return 0;
	if (!src || !src[0])
	{
		snprintf(dest, dest_size, "adf");
		return 1;
	}
	for (i = 0; src[i] && o + 1 < dest_size && o < 15; i++)
	{
		char c = src[i];
		if ((c >= 'a' && c <= 'z') ||
		    (c >= 'A' && c <= 'Z') ||
		    (c >= '0' && c <= '9'))
			dest[o++] = c;
	}
	if (!o)
	{
		snprintf(dest, dest_size, "adf");
		return 1;
	}
	dest[o] = 0;
	return 1;
}

/* Look up an extension for a drive_index from the manifest's floppy
 * table. Falls back to "adf" if the drive wasn't listed. */
static void extension_for_drive(const arcsnap_manifest_t *manifest,
                                int drive_index,
                                char *dest, size_t dest_size)
{
	int i;
	for (i = 0; i < manifest->floppy_count; i++)
	{
		if (manifest->floppies[i].drive_index == drive_index)
		{
			sanitize_extension(dest, dest_size,
			                   manifest->floppies[i].extension);
			return;
		}
	}
	sanitize_extension(dest, dest_size, NULL);
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
	char id[64];
	const char *id_suffix;
	int cfg_extracted = 0;
	int meda_count = 0;
	size_t cursor_before_chunk;
	uint32_t id_cc, version;
	const uint8_t *payload;
	uint64_t payload_size;
	int rc;
	char disc_key[32];
	char disc_path[PATH_MAX];
	int c;

	if (err && err_size)
		err[0] = 0;

	if (!ctx || !ctx->reader || !ctx->manifest_loaded)
	{
		set_error(err, err_size, "snapshot context not initialised");
		return 0;
	}
	if (ctx->runtime_prepared)
	{
		set_error(err, err_size, "snapshot runtime already prepared");
		return 0;
	}

	generate_runtime_id(id);
	/* The on-disk directory uses just the 16-hex-char suffix, not the
	 * full synthetic name — matches how the macOS cleanup path prefixes
	 * runtime dirs with the id suffix only. */
	id_suffix = strchr(id, '_');
	if (id_suffix && *id_suffix)
	{
		/* skip "__snapshot_" so we end up with just the hex */
		const char *p = id_suffix;
		while (*p == '_')
			p++;
		id_suffix = p;
	}
	else
		id_suffix = id;

	platform_path_snapshot_runtime_dir(runtime_dir, sizeof(runtime_dir),
	                                   id_suffix);

	snprintf(runtime_config, sizeof(runtime_config),
	         "%s/machine.cfg", runtime_dir);

	/* Rewind to the first post-MNFT chunk so we can walk CFG/MEDA/PREV
	 * regardless of how we were positioned before. */
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
			break;  /* clean EOF */

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
			int32_t drive_index;
			char ext[16];
			const uint8_t *image_bytes;
			size_t image_size;

			if (payload_size < 4)
			{
				set_error(err, err_size,
				          "snapshot MEDA chunk is truncated");
				return 0;
			}
			/* First 4 bytes: drive_index (i32, little-endian). */
			drive_index =
			    (int32_t)((uint32_t)payload[0]        |
			              ((uint32_t)payload[1] <<  8) |
			              ((uint32_t)payload[2] << 16) |
			              ((uint32_t)payload[3] << 24));
			if (drive_index < 0 || drive_index >= 4)
			{
				set_errorf(err, err_size,
				           "snapshot MEDA chunk has invalid drive index %d",
				           (int)drive_index);
				return 0;
			}
			image_bytes = payload + 4;
			image_size = (size_t)(payload_size - 4);

			extension_for_drive(&ctx->manifest, (int)drive_index,
			                    ext, sizeof(ext));
			snprintf(disc_path, sizeof(disc_path),
			         "%s/disc%d.%s", runtime_dir, (int)drive_index, ext);
			if (!write_file(disc_path, image_bytes, image_size,
			                err, err_size))
				return 0;
			meda_count++;
		}
		else if (id_cc == ARCSNAP_CHUNK_PREV)
		{
			/* Screenshot preview: not needed by the loader. */
		}
		else
		{
			/* First state chunk — rewind so the apply phase sees it. */
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

	/* Rewrite disc_name_0..3 in the extracted config to reference the
	 * newly-extracted disc files so that arc_init()'s autoload picks
	 * them up. Drives without a corresponding MEDA chunk are cleared
	 * so arc_init() boots without attempting to load a ghost path. */
	config_load(CFG_MACHINE, runtime_config);
	for (c = 0; c < 4; c++)
	{
		int have_media = 0;
		int i;

		for (i = 0; i < ctx->manifest.floppy_count; i++)
		{
			if (ctx->manifest.floppies[i].drive_index == c)
			{
				char ext[16];
				extension_for_drive(&ctx->manifest, c,
				                    ext, sizeof(ext));
				snprintf(disc_path, sizeof(disc_path),
				         "%s/disc%d.%s", runtime_dir, c, ext);
				have_media = 1;
				break;
			}
		}

		snprintf(disc_key, sizeof(disc_key), "disc_name_%d", c);
		if (have_media)
			config_set_string(CFG_MACHINE, NULL, disc_key, disc_path);
		else
			config_set_string(CFG_MACHINE, NULL, disc_key, "");
	}
	config_save(CFG_MACHINE, runtime_config);

	(void)meda_count;
	ctx->state_chunks_cursor = snapshot_reader_cursor(ctx->reader);
	snprintf(ctx->runtime_id, sizeof(ctx->runtime_id), "%s", id);
	snprintf(ctx->runtime_dir, sizeof(ctx->runtime_dir), "%s", runtime_dir);
	snprintf(ctx->runtime_config, sizeof(ctx->runtime_config), "%s",
	         runtime_config);
	ctx->runtime_prepared = 1;

	if (runtime_dir_out && runtime_dir_out_len)
		snprintf(runtime_dir_out, runtime_dir_out_len, "%s", runtime_dir);
	if (runtime_config_out && runtime_config_out_len)
		snprintf(runtime_config_out, runtime_config_out_len, "%s",
		         runtime_config);
	if (runtime_name_out && runtime_name_out_len)
		snprintf(runtime_name_out, runtime_name_out_len, "%s", id);
	return 1;
}

/* ----- apply_machine_state -------------------------------------------- *
 *
 * Dispatches each state chunk to the owning subsystem's load function.
 * The caller is responsible for having run arc_init() beforehand so
 * that every subsystem is already initialised, its module-level statics
 * are wired up, and its timers are registered with the global timer
 * list.
 */

struct chunk_decode_result {
	int handled;   /* 1 = dispatched, 0 = skipped (ignore) */
	int ok;        /* 1 = success, 0 = decode failure */
};

static struct chunk_decode_result dispatch_chunk(snapshot_load_ctx_t *ctx,
                                                 uint32_t id,
                                                 uint32_t version,
                                                 const uint8_t *payload,
                                                 uint64_t payload_size)
{
	snapshot_payload_reader_t pr;
	struct chunk_decode_result r = {0, 0};

	snapshot_payload_reader_init(&pr, payload, (size_t)payload_size);

	switch (id)
	{
	case ARCSNAP_CHUNK_CPU:
		r.handled = 1; r.ok = arm_load_state(&pr, version);
		break;
	case ARCSNAP_CHUNK_CP15:
		r.handled = 1;
		if (!arm_has_cp15)
		{
			/* Snapshot contains CP15 state for a config that no
			 * longer has a CP15 — silently skip. Scope-flag
			 * mismatches are already rejected in snapshot_open(). */
			r.ok = 1;
		}
		else
			r.ok = cp15_load_state(&pr, version);
		break;
	case ARCSNAP_CHUNK_FPA:
		r.handled = 1;
		if (!fpaena)
			r.ok = 1;
		else
			r.ok = fpa_load_state(&pr, version);
		break;
	case ARCSNAP_CHUNK_MEM:
		r.handled = 1; r.ok = mem_load_state(&pr, version);
		break;
	case ARCSNAP_CHUNK_MEMC:
		r.handled = 1; r.ok = memc_load_state(&pr, version);
		break;
	case ARCSNAP_CHUNK_IOC:
		r.handled = 1; r.ok = ioc_load_state(&pr, version);
		break;
	case ARCSNAP_CHUNK_VIDC:
		r.handled = 1; r.ok = vidc_load_state(&pr, version);
		break;
	case ARCSNAP_CHUNK_KBD:
		r.handled = 1; r.ok = keyboard_load_state(&pr, version);
		break;
	case ARCSNAP_CHUNK_CMOS:
		r.handled = 1; r.ok = cmos_load_state(&pr, version);
		break;
	case ARCSNAP_CHUNK_DS24:
		r.handled = 1; r.ok = ds2401_load_state(&pr, version);
		break;
	case ARCSNAP_CHUNK_SND:
		r.handled = 1; r.ok = sound_load_state(&pr, version);
		break;
	case ARCSNAP_CHUNK_IOEB:
		r.handled = 1; r.ok = ioeb_load_state(&pr, version);
		break;
	case ARCSNAP_CHUNK_LC:
		r.handled = 1;
		if (machine_type != MACHINE_TYPE_A4)
			r.ok = 1;
		else
			r.ok = lc_load_state(&pr, version);
		break;
	case ARCSNAP_CHUNK_FDCW:
		r.handled = 1;
		if (fdctype == FDC_82C711)
			r.ok = 1;  /* mismatch: tolerate and skip */
		else
			r.ok = wd1770_load_state(&pr, version);
		break;
	case ARCSNAP_CHUNK_FDCS:
		r.handled = 1;
		if (fdctype != FDC_82C711)
			r.ok = 1;
		else
			r.ok = c82c711_fdc_load_state(&pr, version);
		break;
	case ARCSNAP_CHUNK_DISC:
		r.handled = 1; r.ok = disc_load_state(&pr, version);
		break;
	case ARCSNAP_CHUNK_TIMR:
		r.handled = 1; r.ok = timer_load_global(&pr, version);
		break;
	case ARCSNAP_CHUNK_CFG:
	case ARCSNAP_CHUNK_MEDA:
	case ARCSNAP_CHUNK_PREV:
	case ARCSNAP_CHUNK_MNFT:
		/* Already handled by snapshot_open / prepare_runtime. If
		 * apply_machine_state is called without prepare_runtime
		 * (shouldn't happen), skip silently. */
		r.handled = 0;
		r.ok = 1;
		break;
	case ARCSNAP_CHUNK_END:
		r.handled = 0;
		r.ok = 1;
		break;
	default:
		/* Unknown chunk — skip but don't fail so future writers can
		 * add new chunks without breaking old readers. */
		r.handled = 0;
		r.ok = 1;
		break;
	}

	(void)ctx;
	return r;
}

int snapshot_apply_machine_state(snapshot_load_ctx_t *ctx,
                                 char *err, size_t err_size)
{
	uint32_t id_cc, version;
	const uint8_t *payload;
	uint64_t payload_size;
	int rc;
	int saw_end = 0;

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
		struct chunk_decode_result result;

		rc = snapshot_reader_next_chunk(ctx->reader, &id_cc, &version,
		                                &payload, &payload_size,
		                                err, err_size);
		if (rc < 0)
			return 0;
		if (rc == 0)
			break;  /* clean EOF */

		if (id_cc == ARCSNAP_CHUNK_END)
		{
			saw_end = 1;
			break;
		}

		result = dispatch_chunk(ctx, id_cc, version, payload, payload_size);
		if (!result.ok)
		{
			char tag[5];
			tag[0] = (char)(id_cc        & 0xffu);
			tag[1] = (char)((id_cc >>  8) & 0xffu);
			tag[2] = (char)((id_cc >> 16) & 0xffu);
			tag[3] = (char)((id_cc >> 24) & 0xffu);
			tag[4] = 0;
			set_errorf(err, err_size,
			           "failed to apply '%s' chunk (truncated or malformed)",
			           tag);
			return 0;
		}
	}

	(void)saw_end;
	return 1;
}

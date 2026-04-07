#ifndef SNAPSHOT_INTERNAL_H
#define SNAPSHOT_INTERNAL_H

/*
 * Internal definitions shared between snapshot.c (format primitives,
 * scope guards, manifest decode) and snapshot_load.c (runtime bundle
 * preparation and machine-state dispatch).
 *
 * This header is NOT part of the public snapshot API and must not be
 * included by code outside the snapshot subsystem.
 */

#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>

#include "snapshot.h"

#ifdef __cplusplus
extern "C" {
#endif

struct snapshot_load_ctx_t {
	snapshot_reader_t *reader;
	arcsnap_manifest_t manifest;
	int                manifest_loaded;

	/* Cursor position immediately after the MNFT chunk — set by
	 * snapshot_open() and used to rewind for prepare_runtime(). */
	size_t             post_manifest_cursor;

	/* Cursor position of the first machine-state chunk (CPU et al.).
	 * Populated by snapshot_prepare_runtime() after it has consumed
	 * the CFG, MEDA and optional PREV chunks. */
	size_t             state_chunks_cursor;
};

/* Shared error-buffer helpers used by snapshot.c and snapshot_load.c. */
static inline void set_error(char *buf, size_t buf_size, const char *msg)
{
	if (!buf || !buf_size)
		return;
	snprintf(buf, buf_size, "%s", msg ? msg : "");
}

static inline void set_errorf(char *buf, size_t buf_size, const char *fmt, ...)
{
	va_list args;
	if (!buf || !buf_size)
		return;
	va_start(args, fmt);
	vsnprintf(buf, buf_size, fmt, args);
	va_end(args);
}

#ifdef __cplusplus
}
#endif

#endif /* SNAPSHOT_INTERNAL_H */

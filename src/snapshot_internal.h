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

#include <stddef.h>

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
	int                runtime_prepared;

	/* Populated once prepare_runtime has materialised the bundle. */
	char               runtime_id[64];         /* "__snapshot_<16hex>" */
	char               runtime_dir[4096];      /* absolute path */
	char               runtime_config[4096];   /* absolute path to machine.cfg */
};

#ifdef __cplusplus
}
#endif

#endif /* SNAPSHOT_INTERNAL_H */

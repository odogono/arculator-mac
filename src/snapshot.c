/*
 * .arcsnap file format primitives and serialization framework.
 *
 * This file owns:
 *   - the on-disk header / chunk encoding
 *   - a small in-memory growable writer
 *   - a memory-resident reader with per-chunk CRC validation
 *   - manifest encode / decode
 *   - snapshot_open() / snapshot_close() and the scope-flag guard
 */

#include "snapshot.h"
#include "snapshot_chunks.h"
#include "snapshot_internal.h"
#include "config.h"

#include <errno.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* ----- CRC32 (IEEE 802.3) --------------------------------------------- */

static uint32_t crc32_table[256];
static int crc32_table_ready = 0;

static void crc32_init_table(void)
{
	uint32_t c;
	int i, j;

	for (i = 0; i < 256; i++)
	{
		c = (uint32_t)i;
		for (j = 0; j < 8; j++)
			c = (c & 1u) ? (0xedb88320u ^ (c >> 1)) : (c >> 1);
		crc32_table[i] = c;
	}
	crc32_table_ready = 1;
}

uint32_t snapshot_crc32(const void *data, size_t size)
{
	const uint8_t *bytes = (const uint8_t *)data;
	uint32_t c = 0xffffffffu;
	size_t i;

	if (!crc32_table_ready)
		crc32_init_table();

	for (i = 0; i < size; i++)
		c = crc32_table[(c ^ bytes[i]) & 0xffu] ^ (c >> 8);

	return c ^ 0xffffffffu;
}

/* ----- little-endian primitives --------------------------------------- */

static void put_u16_le(uint8_t *p, uint16_t v)
{
	p[0] = (uint8_t)(v       & 0xffu);
	p[1] = (uint8_t)((v >> 8) & 0xffu);
}

static void put_u32_le(uint8_t *p, uint32_t v)
{
	p[0] = (uint8_t)(v        & 0xffu);
	p[1] = (uint8_t)((v >>  8) & 0xffu);
	p[2] = (uint8_t)((v >> 16) & 0xffu);
	p[3] = (uint8_t)((v >> 24) & 0xffu);
}

static void put_u64_le(uint8_t *p, uint64_t v)
{
	put_u32_le(p,     (uint32_t)(v        & 0xffffffffu));
	put_u32_le(p + 4, (uint32_t)((v >> 32) & 0xffffffffu));
}

static uint32_t get_u32_le(const uint8_t *p)
{
	return  (uint32_t)p[0]        |
	       ((uint32_t)p[1] <<  8) |
	       ((uint32_t)p[2] << 16) |
	       ((uint32_t)p[3] << 24);
}

static uint64_t get_u64_le(const uint8_t *p)
{
	return (uint64_t)get_u32_le(p) | ((uint64_t)get_u32_le(p + 4) << 32);
}

/* ----- writer --------------------------------------------------------- */

struct snapshot_writer_t {
	uint8_t *buf;
	size_t   size;
	size_t   capacity;
	int      header_written;
	int      in_chunk;
	/* Latched sticky-ok flag: once any append/reserve fails, every
	 * subsequent operation is a no-op that returns 0. This lets
	 * subsystem save functions chain appends without a per-call
	 * error check — they only need to check the final end_chunk(). */
	int      ok;
	size_t   chunk_header_offset;
	uint32_t chunk_id;
	uint32_t chunk_version;
};

snapshot_writer_t *snapshot_writer_create(void)
{
	snapshot_writer_t *w = (snapshot_writer_t *)calloc(1, sizeof(*w));
	if (!w)
		return NULL;
	w->capacity = 4096;
	w->buf = (uint8_t *)malloc(w->capacity);
	if (!w->buf)
	{
		free(w);
		return NULL;
	}
	w->ok = 1;
	return w;
}

void snapshot_writer_destroy(snapshot_writer_t *w)
{
	if (!w)
		return;
	free(w->buf);
	free(w);
}

static int writer_reserve(snapshot_writer_t *w, size_t extra)
{
	size_t needed;
	size_t new_capacity;
	uint8_t *new_buf;

	if (!w || !w->ok)
		return 0;
	if (extra > (size_t)-1 - w->size)
	{
		w->ok = 0;
		return 0;
	}
	needed = w->size + extra;
	if (needed <= w->capacity)
		return 1;

	new_capacity = w->capacity ? w->capacity : 4096;
	while (new_capacity < needed)
	{
		if (new_capacity > (size_t)-1 / 2)
		{
			new_capacity = needed;
			break;
		}
		new_capacity *= 2;
	}
	new_buf = (uint8_t *)realloc(w->buf, new_capacity);
	if (!new_buf)
	{
		w->ok = 0;
		return 0;
	}
	w->buf = new_buf;
	w->capacity = new_capacity;
	return 1;
}

int snapshot_writer_append(snapshot_writer_t *w, const void *data, size_t size)
{
	if (!w || !w->ok)
		return 0;
	if (!data && size)
	{
		w->ok = 0;
		return 0;
	}
	if (!writer_reserve(w, size))
		return 0;
	if (size)
		memcpy(w->buf + w->size, data, size);
	w->size += size;
	return 1;
}

int snapshot_writer_append_u8(snapshot_writer_t *w, uint8_t v)
{
	return snapshot_writer_append(w, &v, 1);
}

int snapshot_writer_append_u16(snapshot_writer_t *w, uint16_t v)
{
	uint8_t tmp[2];
	put_u16_le(tmp, v);
	return snapshot_writer_append(w, tmp, sizeof(tmp));
}

int snapshot_writer_append_u32(snapshot_writer_t *w, uint32_t v)
{
	uint8_t tmp[4];
	put_u32_le(tmp, v);
	return snapshot_writer_append(w, tmp, sizeof(tmp));
}

int snapshot_writer_append_u64(snapshot_writer_t *w, uint64_t v)
{
	uint8_t tmp[8];
	put_u64_le(tmp, v);
	return snapshot_writer_append(w, tmp, sizeof(tmp));
}

int snapshot_writer_append_i32(snapshot_writer_t *w, int32_t v)
{
	return snapshot_writer_append_u32(w, (uint32_t)v);
}

int snapshot_writer_append_f64(snapshot_writer_t *w, double v)
{
	uint64_t bits;
	memcpy(&bits, &v, sizeof(bits));
	return snapshot_writer_append_u64(w, bits);
}

int snapshot_writer_append_string(snapshot_writer_t *w, const char *s)
{
	size_t len = s ? strlen(s) : 0;
	if (len > 0xffffffffu)
		return 0;
	if (!snapshot_writer_append_u32(w, (uint32_t)len))
		return 0;
	return snapshot_writer_append(w, s, len);
}

int snapshot_writer_write_header(snapshot_writer_t *w)
{
	uint8_t header[ARCSNAP_HEADER_DISK_SIZE];
	uint32_t crc;

	if (!w)
		return 0;
	if (w->header_written)
		return 0;

	memset(header, 0, sizeof(header));
	memcpy(header, ARCSNAP_MAGIC, ARCSNAP_MAGIC_SIZE);
	put_u32_le(header +  8, ARCSNAP_FORMAT_VERSION);
	put_u32_le(header + 12, 0u); /* emulator_version: filled by Phase 5 */
	put_u32_le(header + 16, 0u); /* flags */
	crc = snapshot_crc32(header, ARCSNAP_HEADER_DISK_SIZE - 4);
	put_u32_le(header + 20, crc);

	if (!snapshot_writer_append(w, header, sizeof(header)))
		return 0;
	w->header_written = 1;
	return 1;
}

int snapshot_writer_begin_chunk(snapshot_writer_t *w, uint32_t id, uint32_t version)
{
	uint8_t placeholder[ARCSNAP_CHUNK_HEADER_DISK_SIZE];

	if (!w || !w->ok || w->in_chunk || !w->header_written)
	{
		if (w)
			w->ok = 0;
		return 0;
	}

	w->chunk_header_offset = w->size;
	w->chunk_id = id;
	w->chunk_version = version;

	memset(placeholder, 0, sizeof(placeholder));
	put_u32_le(placeholder + 0, id);
	put_u32_le(placeholder + 4, version);
	/* size, crc32, reserved are backpatched in end_chunk */
	if (!snapshot_writer_append(w, placeholder, sizeof(placeholder)))
		return 0;
	w->in_chunk = 1;
	return 1;
}

int snapshot_writer_end_chunk(snapshot_writer_t *w)
{
	uint8_t *header;
	uint64_t payload_size;
	uint32_t crc;

	if (!w || !w->in_chunk)
		return 0;
	if (!w->ok)
	{
		w->in_chunk = 0;
		return 0;
	}

	payload_size = (uint64_t)(w->size - w->chunk_header_offset - ARCSNAP_CHUNK_HEADER_DISK_SIZE);
	header = w->buf + w->chunk_header_offset;
	crc = snapshot_crc32(header + ARCSNAP_CHUNK_HEADER_DISK_SIZE, (size_t)payload_size);

	put_u64_le(header +  8, payload_size);
	put_u32_le(header + 16, crc);
	put_u32_le(header + 20, 0u);

	w->in_chunk = 0;
	return 1;
}

int snapshot_writer_write_manifest(snapshot_writer_t *w, const arcsnap_manifest_t *m)
{
	int i;

	if (!w || !m)
		return 0;
	{
		uint32_t ver = m->version ? m->version : ARCSNAP_MNFT_VERSION;
		if (!snapshot_writer_begin_chunk(w, ARCSNAP_CHUNK_MNFT, ver))
			return 0;
		if (!snapshot_writer_append_u32(w, ver))                        goto fail;
	}
	if (!snapshot_writer_append_string(w, m->original_config_name)) goto fail;
	if (!snapshot_writer_append_string(w, m->machine))              goto fail;
	if (!snapshot_writer_append_i32   (w, m->fdctype))              goto fail;
	if (!snapshot_writer_append_i32   (w, m->romset))               goto fail;
	if (!snapshot_writer_append_i32   (w, m->memsize))              goto fail;
	if (!snapshot_writer_append_i32   (w, m->machine_type))         goto fail;
	if (!snapshot_writer_append_u32   (w, m->scope_flags))          goto fail;
	if (!snapshot_writer_append_i32   (w, m->preview_width))        goto fail;
	if (!snapshot_writer_append_i32   (w, m->preview_height))       goto fail;
	if (!snapshot_writer_append_u32   (w, (uint32_t)m->floppy_count)) goto fail;
	for (i = 0; i < m->floppy_count && i < ARCSNAP_MNFT_MAX_FLOPPIES; i++)
	{
		const arcsnap_manifest_floppy_t *f = &m->floppies[i];
		if (!snapshot_writer_append_i32   (w, f->drive_index))      goto fail;
		if (!snapshot_writer_append_string(w, f->original_path))    goto fail;
		if (!snapshot_writer_append_u64   (w, f->file_size))        goto fail;
		if (!snapshot_writer_append_i32   (w, f->write_protect))    goto fail;
		if (!snapshot_writer_append_string(w, f->extension))        goto fail;
	}
	if (m->version >= ARCSNAP_MNFT_VERSION_HD)
	{
		if (!snapshot_writer_append_u32(w, (uint32_t)m->hd_count))  goto fail;
		for (i = 0; i < m->hd_count && i < ARCSNAP_MNFT_MAX_HDS; i++)
		{
			const arcsnap_manifest_hd_t *h = &m->hds[i];
			if (!snapshot_writer_append_i32   (w, h->drive_index))  goto fail;
			if (!snapshot_writer_append_string(w, h->original_path)) goto fail;
			if (!snapshot_writer_append_u64   (w, h->file_size))    goto fail;
			if (!snapshot_writer_append_i32   (w, h->spt))          goto fail;
			if (!snapshot_writer_append_i32   (w, h->hpc))          goto fail;
			if (!snapshot_writer_append_i32   (w, h->cyl))          goto fail;
		}
	}
	return snapshot_writer_end_chunk(w);

fail:
	w->in_chunk = 0; /* abort the chunk; bytes remain in buffer */
	return 0;
}

int snapshot_writer_write_meta(snapshot_writer_t *w, const arcsnap_meta_t *meta)
{
	uint32_t prop_count;
	uint32_t i;

	if (!w || !meta)
		return 0;
	if (!snapshot_writer_begin_chunk(w, ARCSNAP_CHUNK_META, ARCSNAP_META_VERSION))
		return 0;

	prop_count = meta->property_count;
	if (prop_count > ARCSNAP_META_MAX_PROPS)
		prop_count = ARCSNAP_META_MAX_PROPS;

	if (!snapshot_writer_append_u32(w, meta->version ? meta->version : ARCSNAP_META_VERSION)) goto fail;
	if (!snapshot_writer_append_string(w, meta->name))                   goto fail;
	if (!snapshot_writer_append_string(w, meta->description))            goto fail;
	if (!snapshot_writer_append_u64   (w, meta->created_at_unix_ms_utc)) goto fail;
	if (!snapshot_writer_append_u32   (w, prop_count))                   goto fail;
	for (i = 0; i < prop_count; i++)
	{
		const arcsnap_meta_property_t *p = &meta->properties[i];
		if (!snapshot_writer_append_string(w, p->key))   goto fail;
		if (!snapshot_writer_append_string(w, p->value)) goto fail;
	}
	return snapshot_writer_end_chunk(w);

fail:
	w->in_chunk = 0;
	return 0;
}

int snapshot_writer_save_to_file(snapshot_writer_t *w, const char *path)
{
	char tmp_path[4096];
	FILE *fp;
	size_t written;

	if (!w || !path || !path[0])
		return 0;
	if (w->in_chunk || !w->header_written)
		return 0;

	snprintf(tmp_path, sizeof(tmp_path), "%s.tmp", path);
	fp = fopen(tmp_path, "wb");
	if (!fp)
		return 0;
	written = fwrite(w->buf, 1, w->size, fp);
	if (written != w->size)
	{
		fclose(fp);
		remove(tmp_path);
		return 0;
	}
	if (fclose(fp))
	{
		remove(tmp_path);
		return 0;
	}
	if (rename(tmp_path, path))
	{
		remove(tmp_path);
		return 0;
	}
	return 1;
}

const uint8_t *snapshot_writer_data(const snapshot_writer_t *w)
{
	return w ? w->buf : NULL;
}

size_t snapshot_writer_size(const snapshot_writer_t *w)
{
	return w ? w->size : 0;
}

/* ----- reader --------------------------------------------------------- */

struct snapshot_reader_t {
	uint8_t          *buf;
	size_t            size;
	size_t            cursor;          /* offset of next chunk header to read */
	arcsnap_header_t  header;
	uint8_t          *current_payload; /* borrowed pointer into buf */
};

static int reader_validate_header(snapshot_reader_t *r,
                                  char *err, size_t err_size)
{
	const uint8_t *p;
	uint32_t got_crc, want_crc;

	if (r->size < ARCSNAP_HEADER_DISK_SIZE)
	{
		set_error(err, err_size, "snapshot file too small (truncated header)");
		return 0;
	}
	p = r->buf;
	if (memcmp(p, ARCSNAP_MAGIC, ARCSNAP_MAGIC_SIZE))
	{
		set_error(err, err_size, "not an arcsnap file (bad magic)");
		return 0;
	}
	memcpy(r->header.magic, p, ARCSNAP_MAGIC_SIZE);
	r->header.format_version   = get_u32_le(p +  8);
	r->header.emulator_version = get_u32_le(p + 12);
	r->header.flags            = get_u32_le(p + 16);
	r->header.header_crc32     = get_u32_le(p + 20);

	want_crc = snapshot_crc32(p, ARCSNAP_HEADER_DISK_SIZE - 4);
	got_crc  = r->header.header_crc32;
	if (want_crc != got_crc)
	{
		set_error(err, err_size, "snapshot header CRC mismatch");
		return 0;
	}
	if (r->header.format_version != ARCSNAP_FORMAT_VERSION)
	{
		set_errorf(err, err_size,
		           "unsupported snapshot format version %u (expected %u)",
		           r->header.format_version, (unsigned)ARCSNAP_FORMAT_VERSION);
		return 0;
	}
	r->cursor = ARCSNAP_HEADER_DISK_SIZE;
	return 1;
}

snapshot_reader_t *snapshot_reader_open_mem(const void *data, size_t size,
                                            char *err, size_t err_size)
{
	snapshot_reader_t *r;

	if (!data && size)
	{
		set_error(err, err_size, "null buffer");
		return NULL;
	}
	r = (snapshot_reader_t *)calloc(1, sizeof(*r));
	if (!r)
	{
		set_error(err, err_size, "out of memory");
		return NULL;
	}
	r->size = size;
	if (size)
	{
		r->buf = (uint8_t *)malloc(size);
		if (!r->buf)
		{
			free(r);
			set_error(err, err_size, "out of memory");
			return NULL;
		}
		memcpy(r->buf, data, size);
	}
	if (!reader_validate_header(r, err, err_size))
	{
		snapshot_reader_close(r);
		return NULL;
	}
	return r;
}

snapshot_reader_t *snapshot_reader_open(const char *path,
                                        char *err, size_t err_size)
{
	FILE *fp;
	long size_long;
	size_t size;
	uint8_t *buf;
	snapshot_reader_t *r;

	if (!path || !path[0])
	{
		set_error(err, err_size, "no snapshot path");
		return NULL;
	}
	fp = fopen(path, "rb");
	if (!fp)
	{
		set_errorf(err, err_size, "cannot open snapshot: %s", strerror(errno));
		return NULL;
	}
	if (fseek(fp, 0, SEEK_END) != 0)
	{
		fclose(fp);
		set_error(err, err_size, "cannot seek snapshot file");
		return NULL;
	}
	size_long = ftell(fp);
	if (size_long < 0)
	{
		fclose(fp);
		set_error(err, err_size, "cannot determine snapshot size");
		return NULL;
	}
	size = (size_t)size_long;
	rewind(fp);

	buf = (uint8_t *)malloc(size ? size : 1);
	if (!buf)
	{
		fclose(fp);
		set_error(err, err_size, "out of memory");
		return NULL;
	}
	if (size && fread(buf, 1, size, fp) != size)
	{
		free(buf);
		fclose(fp);
		set_error(err, err_size, "snapshot read failed");
		return NULL;
	}
	fclose(fp);

	r = (snapshot_reader_t *)calloc(1, sizeof(*r));
	if (!r)
	{
		free(buf);
		set_error(err, err_size, "out of memory");
		return NULL;
	}
	r->buf = buf;
	r->size = size;
	if (!reader_validate_header(r, err, err_size))
	{
		snapshot_reader_close(r);
		return NULL;
	}
	return r;
}

void snapshot_reader_close(snapshot_reader_t *r)
{
	if (!r)
		return;
	free(r->buf);
	free(r);
}

const arcsnap_header_t *snapshot_reader_header(const snapshot_reader_t *r)
{
	return r ? &r->header : NULL;
}

int snapshot_reader_next_chunk(snapshot_reader_t *r,
                               uint32_t *id_out, uint32_t *version_out,
                               const uint8_t **payload_out, uint64_t *size_out,
                               char *err, size_t err_size)
{
	uint8_t *p;
	uint32_t id, version, want_crc, got_crc, reserved;
	uint64_t payload_size;

	if (!r)
	{
		set_error(err, err_size, "null reader");
		return -1;
	}
	if (r->cursor == r->size)
		return 0;
	if (r->cursor > r->size || r->size - r->cursor < ARCSNAP_CHUNK_HEADER_DISK_SIZE)
	{
		set_error(err, err_size, "truncated snapshot (chunk header runs past EOF)");
		return -1;
	}
	p = r->buf + r->cursor;
	id           = get_u32_le(p +  0);
	version      = get_u32_le(p +  4);
	payload_size = get_u64_le(p +  8);
	want_crc     = get_u32_le(p + 16);
	reserved     = get_u32_le(p + 20);
	(void)reserved;

	if (payload_size > (uint64_t)(r->size - r->cursor - ARCSNAP_CHUNK_HEADER_DISK_SIZE))
	{
		set_error(err, err_size, "truncated snapshot (chunk payload runs past EOF)");
		return -1;
	}
	got_crc = snapshot_crc32(p + ARCSNAP_CHUNK_HEADER_DISK_SIZE, (size_t)payload_size);
	if (got_crc != want_crc)
	{
		set_error(err, err_size, "snapshot chunk CRC mismatch");
		return -1;
	}

	r->current_payload = p + ARCSNAP_CHUNK_HEADER_DISK_SIZE;
	r->cursor += ARCSNAP_CHUNK_HEADER_DISK_SIZE + (size_t)payload_size;

	if (id_out)      *id_out = id;
	if (version_out) *version_out = version;
	if (payload_out) *payload_out = r->current_payload;
	if (size_out)    *size_out = payload_size;
	return 1;
}

size_t snapshot_reader_cursor(const snapshot_reader_t *r)
{
	return r ? r->cursor : 0;
}

void snapshot_reader_set_cursor(snapshot_reader_t *r, size_t cursor)
{
	if (!r)
		return;
	if (cursor > r->size)
		cursor = r->size;
	r->cursor = cursor;
	r->current_payload = NULL;
}

/* ----- payload reader (per-chunk decoder used by *_load_state) -------- */

void snapshot_payload_reader_init(snapshot_payload_reader_t *r,
                                  const uint8_t *data, size_t size)
{
	if (!r)
		return;
	r->data = data;
	r->size = size;
	r->cursor = 0;
	r->ok = (data || !size) ? 1 : 0;
}

int snapshot_payload_reader_ok(const snapshot_payload_reader_t *r)
{
	return r ? r->ok : 0;
}

int snapshot_payload_reader_at_end(const snapshot_payload_reader_t *r)
{
	return r ? (r->ok && r->cursor == r->size) : 0;
}

int snapshot_payload_reader_read(snapshot_payload_reader_t *r,
                                 void *dest, size_t size)
{
	if (!r || !r->ok)
		return 0;
	if (size > r->size - r->cursor)
	{
		r->ok = 0;
		return 0;
	}
	if (size && dest)
		memcpy(dest, r->data + r->cursor, size);
	r->cursor += size;
	return 1;
}

int snapshot_payload_reader_skip(snapshot_payload_reader_t *r, size_t size)
{
	return snapshot_payload_reader_read(r, NULL, size);
}

int snapshot_payload_reader_read_u8(snapshot_payload_reader_t *r, uint8_t *out)
{
	uint8_t tmp;
	if (!snapshot_payload_reader_read(r, &tmp, 1))
		return 0;
	if (out)
		*out = tmp;
	return 1;
}

int snapshot_payload_reader_read_u16(snapshot_payload_reader_t *r, uint16_t *out)
{
	uint8_t tmp[2];
	if (!snapshot_payload_reader_read(r, tmp, sizeof(tmp)))
		return 0;
	if (out)
		*out = (uint16_t)tmp[0] | ((uint16_t)tmp[1] << 8);
	return 1;
}

int snapshot_payload_reader_read_u32(snapshot_payload_reader_t *r, uint32_t *out)
{
	uint8_t tmp[4];
	if (!snapshot_payload_reader_read(r, tmp, sizeof(tmp)))
		return 0;
	if (out)
		*out = get_u32_le(tmp);
	return 1;
}

int snapshot_payload_reader_read_u64(snapshot_payload_reader_t *r, uint64_t *out)
{
	uint8_t tmp[8];
	if (!snapshot_payload_reader_read(r, tmp, sizeof(tmp)))
		return 0;
	if (out)
		*out = get_u64_le(tmp);
	return 1;
}

int snapshot_payload_reader_read_i32(snapshot_payload_reader_t *r, int32_t *out)
{
	uint32_t v;
	if (!snapshot_payload_reader_read_u32(r, &v))
		return 0;
	if (out)
		*out = (int32_t)v;
	return 1;
}

int snapshot_payload_reader_read_f64(snapshot_payload_reader_t *r, double *out)
{
	uint64_t bits;
	if (!snapshot_payload_reader_read_u64(r, &bits))
		return 0;
	if (out)
		memcpy(out, &bits, sizeof(*out));
	return 1;
}

/* ----- manifest decode ------------------------------------------------ */

typedef struct {
	const uint8_t *data;
	uint64_t       size;
	uint64_t       cursor;
	int            ok;
} mnft_decoder_t;

static int mnft_read(mnft_decoder_t *d, void *dest, size_t size)
{
	if (!d->ok)
		return 0;
	if (d->cursor + size > d->size)
	{
		d->ok = 0;
		return 0;
	}
	memcpy(dest, d->data + d->cursor, size);
	d->cursor += size;
	return 1;
}

static int mnft_read_u32(mnft_decoder_t *d, uint32_t *out)
{
	uint8_t tmp[4];
	if (!mnft_read(d, tmp, 4))
		return 0;
	*out = get_u32_le(tmp);
	return 1;
}

static int mnft_read_i32(mnft_decoder_t *d, int32_t *out)
{
	uint32_t v;
	if (!mnft_read_u32(d, &v))
		return 0;
	*out = (int32_t)v;
	return 1;
}

static int mnft_read_u64(mnft_decoder_t *d, uint64_t *out)
{
	uint8_t tmp[8];
	if (!mnft_read(d, tmp, 8))
		return 0;
	*out = get_u64_le(tmp);
	return 1;
}

static int mnft_read_string(mnft_decoder_t *d, char *dest, size_t dest_size)
{
	uint32_t len;
	size_t copy;

	if (!mnft_read_u32(d, &len))
		return 0;
	if ((uint64_t)len > d->size - d->cursor)
	{
		d->ok = 0;
		return 0;
	}
	if (dest && dest_size)
	{
		copy = (len < dest_size - 1) ? len : (dest_size - 1);
		memcpy(dest, d->data + d->cursor, copy);
		dest[copy] = 0;
	}
	d->cursor += len;
	return 1;
}

int snapshot_decode_manifest(const uint8_t *payload, uint64_t size,
                             arcsnap_manifest_t *out,
                             char *err, size_t err_size)
{
	mnft_decoder_t d;
	uint32_t floppy_count;
	int32_t  i32;
	uint32_t u32;
	int      i;

	if (!payload || !out)
	{
		set_error(err, err_size, "manifest decode: bad arguments");
		return 0;
	}
	memset(out, 0, sizeof(*out));
	d.data = payload;
	d.size = size;
	d.cursor = 0;
	d.ok = 1;

	if (!mnft_read_u32(&d, &out->version))
		goto truncated;
	if (out->version != ARCSNAP_MNFT_VERSION &&
	    out->version != ARCSNAP_MNFT_VERSION_HD)
	{
		set_errorf(err, err_size,
		           "unsupported manifest version %u (expected %u or %u)",
		           out->version,
		           (unsigned)ARCSNAP_MNFT_VERSION,
		           (unsigned)ARCSNAP_MNFT_VERSION_HD);
		return 0;
	}
	if (!mnft_read_string(&d, out->original_config_name, sizeof(out->original_config_name))) goto truncated;
	if (!mnft_read_string(&d, out->machine, sizeof(out->machine))) goto truncated;
	if (!mnft_read_i32(&d, &i32)) goto truncated; out->fdctype      = (int)i32;
	if (!mnft_read_i32(&d, &i32)) goto truncated; out->romset       = (int)i32;
	if (!mnft_read_i32(&d, &i32)) goto truncated; out->memsize      = (int)i32;
	if (!mnft_read_i32(&d, &i32)) goto truncated; out->machine_type = (int)i32;
	if (!mnft_read_u32(&d, &u32)) goto truncated; out->scope_flags  = u32;
	if (!mnft_read_i32(&d, &i32)) goto truncated; out->preview_width  = (int)i32;
	if (!mnft_read_i32(&d, &i32)) goto truncated; out->preview_height = (int)i32;
	if (!mnft_read_u32(&d, &floppy_count)) goto truncated;

	if (floppy_count > ARCSNAP_MNFT_MAX_FLOPPIES)
	{
		set_errorf(err, err_size,
		           "manifest declares %u floppies (max %u)",
		           floppy_count, (unsigned)ARCSNAP_MNFT_MAX_FLOPPIES);
		return 0;
	}
	out->floppy_count = (int)floppy_count;
	for (i = 0; i < (int)floppy_count; i++)
	{
		arcsnap_manifest_floppy_t *f = &out->floppies[i];
		if (!mnft_read_i32(&d, &i32)) goto truncated; f->drive_index = (int)i32;
		if (!mnft_read_string(&d, f->original_path, sizeof(f->original_path))) goto truncated;
		if (!mnft_read_u64(&d, &f->file_size)) goto truncated;
		if (!mnft_read_i32(&d, &i32)) goto truncated; f->write_protect = (int)i32;
		if (!mnft_read_string(&d, f->extension, sizeof(f->extension))) goto truncated;
	}
	if (out->version >= ARCSNAP_MNFT_VERSION_HD)
	{
		uint32_t hd_count;
		if (!mnft_read_u32(&d, &hd_count)) goto truncated;
		if (hd_count > ARCSNAP_MNFT_MAX_HDS)
		{
			set_errorf(err, err_size,
			           "manifest declares %u hard discs (max %u)",
			           hd_count, (unsigned)ARCSNAP_MNFT_MAX_HDS);
			return 0;
		}
		out->hd_count = (int)hd_count;
		for (i = 0; i < (int)hd_count; i++)
		{
			arcsnap_manifest_hd_t *h = &out->hds[i];
			if (!mnft_read_i32(&d, &i32)) goto truncated; h->drive_index = (int)i32;
			if (!mnft_read_string(&d, h->original_path, sizeof(h->original_path))) goto truncated;
			if (!mnft_read_u64(&d, &h->file_size)) goto truncated;
			if (!mnft_read_i32(&d, &i32)) goto truncated; h->spt = (int)i32;
			if (!mnft_read_i32(&d, &i32)) goto truncated; h->hpc = (int)i32;
			if (!mnft_read_i32(&d, &i32)) goto truncated; h->cyl = (int)i32;
		}
	}
	if (d.cursor != d.size)
	{
		set_error(err, err_size, "manifest has trailing bytes");
		return 0;
	}
	return 1;

truncated:
	set_error(err, err_size, "manifest decode: truncated payload");
	return 0;
}

/* ----- META decode ---------------------------------------------------- */

/* Reads a length-prefixed string and writes it into `dest` with a
 * guaranteed trailing NUL. Rejects strings whose declared length does
 * not leave room for the NUL in `dest_cap`, so decoders stay strict
 * about overflow rather than silently truncating. */
static int meta_read_string(snapshot_payload_reader_t *r,
                            char *dest, size_t dest_cap,
                            const char *field_name,
                            char *err, size_t err_size)
{
	uint32_t len;

	if (!snapshot_payload_reader_read_u32(r, &len))
	{
		set_errorf(err, err_size,
		           "meta decode: truncated '%s' length", field_name);
		return 0;
	}
	if ((uint64_t)len >= (uint64_t)dest_cap)
	{
		set_errorf(err, err_size,
		           "meta decode: '%s' too long (%u bytes, max %zu)",
		           field_name, (unsigned)len, (size_t)(dest_cap - 1));
		return 0;
	}
	if (!snapshot_payload_reader_read(r, dest, (size_t)len))
	{
		set_errorf(err, err_size,
		           "meta decode: truncated '%s' payload", field_name);
		return 0;
	}
	dest[len] = 0;
	return 1;
}

int snapshot_decode_meta(const uint8_t *payload, uint64_t size,
                         arcsnap_meta_t *out,
                         char *err, size_t err_size)
{
	snapshot_payload_reader_t r;
	uint32_t prop_count;
	uint32_t i;

	if (!payload || !out)
	{
		set_error(err, err_size, "meta decode: bad arguments");
		return 0;
	}
	memset(out, 0, sizeof(*out));

	if (size > (uint64_t)(size_t)-1)
	{
		set_error(err, err_size, "meta decode: payload too large");
		return 0;
	}
	snapshot_payload_reader_init(&r, payload, (size_t)size);

	if (!snapshot_payload_reader_read_u32(&r, &out->version))
	{
		set_error(err, err_size, "meta decode: truncated version");
		return 0;
	}
	if (out->version != ARCSNAP_META_VERSION)
	{
		set_errorf(err, err_size,
		           "unsupported meta version %u (expected %u)",
		           out->version, (unsigned)ARCSNAP_META_VERSION);
		return 0;
	}
	if (!meta_read_string(&r, out->name, sizeof(out->name),
	                      "name", err, err_size))
		return 0;
	if (!meta_read_string(&r, out->description, sizeof(out->description),
	                      "description", err, err_size))
		return 0;
	if (!snapshot_payload_reader_read_u64(&r, &out->created_at_unix_ms_utc))
	{
		set_error(err, err_size, "meta decode: truncated created_at");
		return 0;
	}
	if (!snapshot_payload_reader_read_u32(&r, &prop_count))
	{
		set_error(err, err_size, "meta decode: truncated property_count");
		return 0;
	}
	if (prop_count > ARCSNAP_META_MAX_PROPS)
	{
		set_errorf(err, err_size,
		           "meta declares %u properties (max %u)",
		           (unsigned)prop_count, (unsigned)ARCSNAP_META_MAX_PROPS);
		return 0;
	}
	out->property_count = prop_count;
	for (i = 0; i < prop_count; i++)
	{
		char key_field[32], val_field[32];
		snprintf(key_field, sizeof(key_field), "properties[%u].key",   (unsigned)i);
		snprintf(val_field, sizeof(val_field), "properties[%u].value", (unsigned)i);
		if (!meta_read_string(&r, out->properties[i].key,
		                      sizeof(out->properties[i].key),
		                      key_field, err, err_size))
			return 0;
		if (!meta_read_string(&r, out->properties[i].value,
		                      sizeof(out->properties[i].value),
		                      val_field, err, err_size))
			return 0;
	}
	if (r.cursor != r.size)
	{
		set_error(err, err_size, "meta has trailing bytes");
		return 0;
	}
	return 1;
}

/* ----- high-level public API ------------------------------------------ */

/* Externs from across the emulator that the scope guard inspects.
 *
 * These are deliberately declared inline rather than #include'd from
 * config.h / disc.h / podules.h / st506.h, so the standalone format
 * tests can compile snapshot.c against simple stub definitions
 * without dragging in the full machine-config / hardware headers. */
extern int  st506_present;
extern int  fdctype;
extern char hd_fn[2][512];
extern char podule_names[4][16];
extern char joystick_if[16];
extern char _5th_column_fn[512];
extern int  arc_is_paused(void);
extern int  floppy_is_idle(void);
extern int  ide_internal_is_idle(void);

static int snapshot_internal_hd_is_configured(void)
{
	int has_internal_controller = (fdctype == FDC_82C711) || st506_present;
	int has_internal_image = hd_fn[0][0] || hd_fn[1][0];

	return has_internal_controller && has_internal_image;
}

static int snapshot_joystick_is_configured(void)
{
	if (!joystick_if[0])
		return 0;
	if (!strcmp(joystick_if, "none"))
		return 0;
	return 1;
}

int snapshot_can_save(char *err, size_t err_size)
{
	int i;

	if (err && err_size)
		err[0] = 0;

	if (snapshot_internal_hd_is_configured())
	{
		if (fdctype == FDC_82C711)
		{
			if (!ide_internal_is_idle())
			{
				set_errorf(err, err_size,
				           "IDE hard disc controller is busy; wait and try again");
				return 0;
			}
		}
		else if (st506_present)
		{
			set_errorf(err, err_size,
			           "ST506 hard disc not yet supported in snapshots");
			return 0;
		}
	}
	for (i = 0; i < 4; i++)
	{
		/* The "arculator_rom" support podule is treated as
		 * static / stateless and is allowed by the v1 guard. */
		if (podule_names[i][0] &&
		    strcmp(podule_names[i], "arculator_rom") != 0)
		{
			set_errorf(err, err_size,
			           "podule '%s' in slot %d not supported in v1",
			           podule_names[i], i);
			return 0;
		}
	}
	if (_5th_column_fn[0])
	{
		set_errorf(err, err_size, "5th-column ROM not supported in v1");
		return 0;
	}
	if (snapshot_joystick_is_configured())
	{
		set_errorf(err, err_size, "joystick interface not supported in v1");
		return 0;
	}
	if (!floppy_is_idle())
	{
		set_errorf(err, err_size,
		           "floppy controller is busy; wait and try again");
		return 0;
	}
	return 1;
}

/* snapshot_save() lives in snapshot_load.c because it links against
 * every per-subsystem `*_save_state` symbol, which the standalone
 * format tests deliberately avoid. */

snapshot_load_ctx_t *snapshot_open(const char *path, char *err, size_t err_size)
{
	snapshot_load_ctx_t *ctx;
	uint32_t id, version;
	const uint8_t *payload;
	uint64_t payload_size;
	int rc;

	ctx = (snapshot_load_ctx_t *)calloc(1, sizeof(*ctx));
	if (!ctx)
	{
		set_error(err, err_size, "out of memory");
		return NULL;
	}
	ctx->reader = snapshot_reader_open(path, err, err_size);
	if (!ctx->reader)
	{
		free(ctx);
		return NULL;
	}

	/* Eagerly parse the first chunk: it must be MNFT in v1. */
	rc = snapshot_reader_next_chunk(ctx->reader, &id, &version, &payload, &payload_size,
	                                err, err_size);
	if (rc < 0)
	{
		snapshot_close(ctx);
		return NULL;
	}
	if (rc == 0)
	{
		set_error(err, err_size, "snapshot is empty (no chunks)");
		snapshot_close(ctx);
		return NULL;
	}
	if (id != ARCSNAP_CHUNK_MNFT)
	{
		set_error(err, err_size, "snapshot is missing manifest chunk");
		snapshot_close(ctx);
		return NULL;
	}
	if (!snapshot_decode_manifest(payload, payload_size, &ctx->manifest, err, err_size))
	{
		snapshot_close(ctx);
		return NULL;
	}

	/* Symmetrical scope check: even though the v1 save side
	 * refuses to emit these, defend the load path against a
	 * snapshot built by a future writer or by hand. */
	if (ctx->manifest.scope_flags & ARCSNAP_SCOPE_UNSUPPORTED_MASK)
	{
		uint32_t bad = ctx->manifest.scope_flags & ARCSNAP_SCOPE_UNSUPPORTED_MASK;
		const char *what = "unsupported subsystem";
		if      (bad & ARCSNAP_SCOPE_HAS_PODULE)     what = "podule";
		else if (bad & ARCSNAP_SCOPE_HAS_5TH_COLUMN) what = "5th-column ROM";
		else if (bad & ARCSNAP_SCOPE_HAS_JOYSTICK)   what = "joystick interface";
		set_errorf(err, err_size,
		           "snapshot declares %s state, which is not supported in v1",
		           what);
		snapshot_close(ctx);
		return NULL;
	}

	ctx->manifest_loaded = 1;
	ctx->post_manifest_cursor = snapshot_reader_cursor(ctx->reader);
	ctx->state_chunks_cursor = ctx->post_manifest_cursor;
	return ctx;
}

/* snapshot_prepare_runtime() and snapshot_apply_machine_state() live in
 * snapshot_load.c so the standalone format tests can link against
 * snapshot.c without pulling in config / platform / per-subsystem
 * load_state dependencies. */

const char *snapshot_original_config_name(const snapshot_load_ctx_t *ctx)
{
	if (!ctx || !ctx->manifest_loaded || !ctx->manifest.original_config_name[0])
		return NULL;
	return ctx->manifest.original_config_name;
}

void snapshot_close(snapshot_load_ctx_t *ctx)
{
	if (!ctx)
		return;
	snapshot_reader_close(ctx->reader);
	free(ctx);
}

/* ----- snapshot_peek_summary ------------------------------------------ *
 *
 * Read-only inspector: opens a snapshot, parses MNFT plus any optional
 * summary chunks (META, PREV), and closes the reader. Never touches
 * emulation state, never calls into snapshot_load.c, and never enforces
 * the scope flags — browsers should be able to list snapshots that the
 * loader would refuse (e.g. future HD-scope snapshots) and surface the
 * refusal later, at actual load time.
 *
 * Kept deliberately in snapshot.c so it links cleanly in standalone
 * tooling that does not pull in config / platform / per-subsystem code.
 */

void snapshot_summary_dispose(arcsnap_summary_t *summary)
{
	if (!summary)
		return;
	free(summary->preview_png);
	memset(summary, 0, sizeof(*summary));
}

int snapshot_peek_summary(const char *path,
                          arcsnap_summary_t *out,
                          char *err, size_t err_size)
{
	snapshot_reader_t *r = NULL;
	uint32_t id, version;
	const uint8_t *payload;
	uint64_t payload_size;
	int rc;

	if (err && err_size)
		err[0] = 0;
	if (!out)
	{
		set_error(err, err_size, "snapshot_peek_summary: null output");
		return 0;
	}
	memset(out, 0, sizeof(*out));

	r = snapshot_reader_open(path, err, err_size);
	if (!r)
		return 0;

	/* First chunk must be MNFT. */
	rc = snapshot_reader_next_chunk(r, &id, &version, &payload, &payload_size,
	                                err, err_size);
	if (rc < 0)
		goto fail;
	if (rc == 0)
	{
		set_error(err, err_size, "snapshot is empty (no chunks)");
		goto fail;
	}
	if (id != ARCSNAP_CHUNK_MNFT)
	{
		set_error(err, err_size, "snapshot is missing manifest chunk");
		goto fail;
	}
	if (!snapshot_decode_manifest(payload, payload_size, &out->manifest,
	                              err, err_size))
		goto fail;

	/* Walk remaining chunks, collecting optional summary data. Stop
	 * at the first chunk that is not a known summary chunk; those
	 * are either machine-state chunks or end-of-stream. Unknown
	 * chunks between MNFT and the first state chunk are a decode
	 * error in this strict peek path — if a future format adds a
	 * new summary chunk, this function must learn about it before
	 * it starts appearing in the wild. */
	for (;;)
	{
		rc = snapshot_reader_next_chunk(r, &id, &version, &payload, &payload_size,
		                                err, err_size);
		if (rc < 0)
			goto fail;
		if (rc == 0)
			break;
		if (id == ARCSNAP_CHUNK_META)
		{
			if (out->has_meta)
			{
				set_error(err, err_size,
				          "snapshot contains duplicate META chunk");
				goto fail;
			}
			if (!snapshot_decode_meta(payload, payload_size, &out->meta,
			                          err, err_size))
				goto fail;
			out->has_meta = 1;
		}
		else if (id == ARCSNAP_CHUNK_PREV)
		{
			if (out->has_preview)
			{
				set_error(err, err_size,
				          "snapshot contains duplicate PREV chunk");
				goto fail;
			}
			if (payload_size == 0)
			{
				set_error(err, err_size,
				          "snapshot PREV chunk is empty");
				goto fail;
			}
			if (payload_size > (uint64_t)(size_t)-1)
			{
				set_error(err, err_size,
				          "snapshot PREV chunk too large");
				goto fail;
			}
			out->preview_png = (uint8_t *)malloc((size_t)payload_size);
			if (!out->preview_png)
			{
				set_error(err, err_size, "out of memory");
				goto fail;
			}
			memcpy(out->preview_png, payload, (size_t)payload_size);
			out->preview_png_size = (size_t)payload_size;
			out->preview_width    = out->manifest.preview_width;
			out->preview_height   = out->manifest.preview_height;
			out->has_preview      = 1;
		}
		else if (id == ARCSNAP_CHUNK_CFG  ||
		         id == ARCSNAP_CHUNK_MEDA ||
		         id == ARCSNAP_CHUNK_MHDA)
		{
			/* Pre-state chunks that peek does not care about —
			 * skipping them cleanly keeps peek tolerant of the
			 * current writer order without needing to fully
			 * parse the runtime bundle. */
		}
		else
		{
			/* First machine-state chunk (or END) — stop. */
			break;
		}
	}

	snapshot_reader_close(r);
	return 1;

fail:
	snapshot_reader_close(r);
	snapshot_summary_dispose(out);
	return 0;
}

/* ----- snapshot_rewrite_metadata --------------------------------------- *
 *
 * Opens an existing .arcsnap, copies all chunks to a new writer while
 * selectively replacing META and/or PREV, then atomically overwrites
 * the original file. Non-summary chunks (state, END) are preserved
 * byte-for-byte.
 */

/* Helper: is this chunk a "pre-state" chunk that precedes machine
 * state data in the canonical save order? */
static int is_pre_state_chunk(uint32_t id)
{
	return id == ARCSNAP_CHUNK_MNFT ||
	       id == ARCSNAP_CHUNK_CFG  ||
	       id == ARCSNAP_CHUNK_MEDA ||
	       id == ARCSNAP_CHUNK_MHDA ||
	       id == ARCSNAP_CHUNK_META ||
	       id == ARCSNAP_CHUNK_PREV;
}

int snapshot_rewrite_metadata(const char *path,
                              int update_meta,
                              const arcsnap_meta_t *new_meta,
                              int update_preview,
                              const uint8_t *new_preview_png,
                              size_t new_preview_png_size,
                              char *error_buf, size_t error_buf_len)
{
	snapshot_reader_t *r = NULL;
	snapshot_writer_t *w = NULL;
	uint32_t id, version;
	const uint8_t *payload;
	uint64_t payload_size;
	int rc;
	int new_chunks_emitted = 0;

	if (error_buf && error_buf_len)
		error_buf[0] = 0;

	if (!path || !path[0])
	{
		set_error(error_buf, error_buf_len, "no snapshot path");
		return 0;
	}

	r = snapshot_reader_open(path, error_buf, error_buf_len);
	if (!r)
		return 0;

	w = snapshot_writer_create();
	if (!w)
	{
		set_error(error_buf, error_buf_len, "out of memory");
		goto fail;
	}
	if (!snapshot_writer_write_header(w))
	{
		set_error(error_buf, error_buf_len, "writer failed (header)");
		goto fail;
	}

	for (;;)
	{
		rc = snapshot_reader_next_chunk(r, &id, &version, &payload,
		                               &payload_size, error_buf, error_buf_len);
		if (rc < 0)
			goto fail;
		if (rc == 0)
			break;

		/* Skip META/PREV when they are being replaced. */
		if (id == ARCSNAP_CHUNK_META && update_meta)
			continue;
		if (id == ARCSNAP_CHUNK_PREV && update_preview)
			continue;

		/* Before the first non-pre-state chunk, emit the new META
		 * and PREV so they appear in the canonical position (after
		 * CFG/MEDA/MHDA, before state chunks). This ensures
		 * snapshot_peek_summary() can find them. */
		if (!new_chunks_emitted && !is_pre_state_chunk(id))
		{
			if (update_preview && new_preview_png && new_preview_png_size)
			{
				if (!snapshot_writer_begin_chunk(w, ARCSNAP_CHUNK_PREV, 1u))
				{
					set_error(error_buf, error_buf_len,
					          "writer failed (PREV begin)");
					goto fail;
				}
				if (!snapshot_writer_append(w, new_preview_png,
				                           new_preview_png_size))
				{
					set_error(error_buf, error_buf_len,
					          "writer failed (PREV payload)");
					goto fail;
				}
				if (!snapshot_writer_end_chunk(w))
				{
					set_error(error_buf, error_buf_len,
					          "writer failed (PREV end)");
					goto fail;
				}
			}
			if (update_meta && new_meta)
			{
				if (!snapshot_writer_write_meta(w, new_meta))
				{
					set_error(error_buf, error_buf_len,
					          "writer failed (META)");
					goto fail;
				}
			}
			new_chunks_emitted = 1;
		}

		/* Copy this chunk verbatim. */
		if (!snapshot_writer_begin_chunk(w, id, version))
		{
			set_errorf(error_buf, error_buf_len,
			           "writer failed (copy chunk 0x%08x begin)", id);
			goto fail;
		}
		if (payload_size &&
		    !snapshot_writer_append(w, payload, (size_t)payload_size))
		{
			set_errorf(error_buf, error_buf_len,
			           "writer failed (copy chunk 0x%08x payload)", id);
			goto fail;
		}
		if (!snapshot_writer_end_chunk(w))
		{
			set_errorf(error_buf, error_buf_len,
			           "writer failed (copy chunk 0x%08x end)", id);
			goto fail;
		}
	}

	/* Edge case: file had only pre-state chunks and no state/END. */
	if (!new_chunks_emitted)
	{
		if (update_preview && new_preview_png && new_preview_png_size)
		{
			if (!snapshot_writer_begin_chunk(w, ARCSNAP_CHUNK_PREV, 1u) ||
			    !snapshot_writer_append(w, new_preview_png,
			                           new_preview_png_size) ||
			    !snapshot_writer_end_chunk(w))
			{
				set_error(error_buf, error_buf_len,
				          "writer failed (trailing PREV)");
				goto fail;
			}
		}
		if (update_meta && new_meta)
		{
			if (!snapshot_writer_write_meta(w, new_meta))
			{
				set_error(error_buf, error_buf_len,
				          "writer failed (trailing META)");
				goto fail;
			}
		}
	}

	if (!snapshot_writer_save_to_file(w, path))
	{
		set_errorf(error_buf, error_buf_len,
		           "failed to write '%s'", path);
		goto fail;
	}

	snapshot_writer_destroy(w);
	snapshot_reader_close(r);
	return 1;

fail:
	snapshot_writer_destroy(w);
	snapshot_reader_close(r);
	return 0;
}

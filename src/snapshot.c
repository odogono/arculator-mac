/*
 * .arcsnap file format primitives and serialization framework.
 *
 * This file owns:
 *   - the on-disk header / chunk encoding
 *   - a small in-memory growable writer
 *   - a memory-resident reader with per-chunk CRC validation
 *   - manifest encode / decode
 *   - stubs for the high-level save() / load() entry points
 */

#include "snapshot.h"
#include "snapshot_chunks.h"

#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* ----- helpers --------------------------------------------------------- */

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
	if (!snapshot_writer_begin_chunk(w, ARCSNAP_CHUNK_MNFT, ARCSNAP_MNFT_VERSION))
		return 0;
	if (!snapshot_writer_append_u32(w, m->version ? m->version : ARCSNAP_MNFT_VERSION)) goto fail;
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
	return snapshot_writer_end_chunk(w);

fail:
	w->in_chunk = 0; /* abort the chunk; bytes remain in buffer */
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
	if (out->version != ARCSNAP_MNFT_VERSION)
	{
		set_errorf(err, err_size,
		           "unsupported manifest version %u (expected %u)",
		           out->version, (unsigned)ARCSNAP_MNFT_VERSION);
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

/* ----- high-level public API ------------------------------------------ */

struct snapshot_load_ctx_t {
	snapshot_reader_t *reader;
	arcsnap_manifest_t manifest;
	int                manifest_loaded;
};

int snapshot_can_save(char *err, size_t err_size)
{
	(void)err;
	(void)err_size;
	/* Phase 1 stub: real scope guards arrive in Phase 3. */
	return 1;
}

int snapshot_save(const char *path,
                  const uint8_t *preview_png, size_t preview_png_size,
                  int preview_w, int preview_h,
                  char *err, size_t err_size)
{
	(void)path;
	(void)preview_png;
	(void)preview_png_size;
	(void)preview_w;
	(void)preview_h;
	/* Phase 1 stub: per-subsystem serializers arrive in Phase 2; the
	 * full save flow is wired up in Phases 3-5. */
	set_error(err, err_size, "snapshot save not yet implemented");
	return 0;
}

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
	ctx->manifest_loaded = 1;
	return ctx;
}

int snapshot_prepare_runtime(snapshot_load_ctx_t *ctx,
                             char *runtime_dir_out, size_t runtime_dir_out_len,
                             char *runtime_config_out, size_t runtime_config_out_len,
                             char *runtime_name_out, size_t runtime_name_out_len,
                             char *err, size_t err_size)
{
	(void)ctx;
	(void)runtime_dir_out;
	(void)runtime_dir_out_len;
	(void)runtime_config_out;
	(void)runtime_config_out_len;
	(void)runtime_name_out;
	(void)runtime_name_out_len;
	/* Phase 1 stub: real implementation lives in Phase 4. */
	set_error(err, err_size, "snapshot prepare_runtime not yet implemented");
	return 0;
}

int snapshot_apply_machine_state(snapshot_load_ctx_t *ctx, char *err, size_t err_size)
{
	(void)ctx;
	(void)err;
	(void)err_size;
	/* Phase 1 stub: real implementation lives in Phases 2-4. */
	return 1;
}

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

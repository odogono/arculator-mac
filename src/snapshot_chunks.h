#ifndef SNAPSHOT_CHUNKS_H
#define SNAPSHOT_CHUNKS_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Internal definitions for the .arcsnap file format.
 *
 * On-disk byte order is little-endian. FourCC values are stored as a
 * little-endian uint32_t whose four bytes spell the chunk tag in order.
 * For example, ARCSNAP_FOURCC('C','F','G',' ') stores the bytes
 * { 'C', 'F', 'G', ' ' } when written as a uint32_t in little-endian.
 */

#define ARCSNAP_MAGIC          "ARCSNAP"          /* 7 chars + trailing NUL */
#define ARCSNAP_MAGIC_SIZE     8
#define ARCSNAP_FORMAT_VERSION 1u

#define ARCSNAP_FOURCC(a, b, c, d) \
	(((uint32_t)(uint8_t)(a))        | \
	 ((uint32_t)(uint8_t)(b) <<  8)  | \
	 ((uint32_t)(uint8_t)(c) << 16)  | \
	 ((uint32_t)(uint8_t)(d) << 24))

#define ARCSNAP_CHUNK_MNFT ARCSNAP_FOURCC('M','N','F','T')
#define ARCSNAP_CHUNK_CFG  ARCSNAP_FOURCC('C','F','G',' ')
#define ARCSNAP_CHUNK_MEDA ARCSNAP_FOURCC('M','E','D','A')
#define ARCSNAP_CHUNK_PREV ARCSNAP_FOURCC('P','R','E','V')
#define ARCSNAP_CHUNK_CPU  ARCSNAP_FOURCC('C','P','U',' ')
#define ARCSNAP_CHUNK_CP15 ARCSNAP_FOURCC('C','P','1','5')
#define ARCSNAP_CHUNK_FPA  ARCSNAP_FOURCC('F','P','A',' ')
#define ARCSNAP_CHUNK_MEM  ARCSNAP_FOURCC('M','E','M',' ')
#define ARCSNAP_CHUNK_MEMC ARCSNAP_FOURCC('M','E','M','C')
#define ARCSNAP_CHUNK_IOC  ARCSNAP_FOURCC('I','O','C',' ')
#define ARCSNAP_CHUNK_VIDC ARCSNAP_FOURCC('V','I','D','C')
#define ARCSNAP_CHUNK_KBD  ARCSNAP_FOURCC('K','B','D',' ')
#define ARCSNAP_CHUNK_CMOS ARCSNAP_FOURCC('C','M','O','S')
#define ARCSNAP_CHUNK_DS24 ARCSNAP_FOURCC('D','S','2','4')
#define ARCSNAP_CHUNK_SND  ARCSNAP_FOURCC('S','N','D',' ')
#define ARCSNAP_CHUNK_IOEB ARCSNAP_FOURCC('I','O','E','B')
#define ARCSNAP_CHUNK_LC   ARCSNAP_FOURCC('L','C',' ',' ')
#define ARCSNAP_CHUNK_FDC  ARCSNAP_FOURCC('F','D','C',' ')
#define ARCSNAP_CHUNK_DISC ARCSNAP_FOURCC('D','I','S','C')
#define ARCSNAP_CHUNK_TIMR ARCSNAP_FOURCC('T','I','M','R')
#define ARCSNAP_CHUNK_END  ARCSNAP_FOURCC('E','N','D',' ')

#define ARCSNAP_MNFT_VERSION 1u
#define ARCSNAP_MNFT_MAX_FLOPPIES 4

/* Scope flag bitmap (declares which optional subsystems are present). */
#define ARCSNAP_SCOPE_HAS_CP15  (1u << 0)
#define ARCSNAP_SCOPE_HAS_FPA   (1u << 1)
#define ARCSNAP_SCOPE_HAS_IOEB  (1u << 2)
#define ARCSNAP_SCOPE_HAS_LC    (1u << 3)
#define ARCSNAP_SCOPE_HAS_PREV  (1u << 4)

/* On-disk header. Layout matches the format documented in
 * docs/SNAPSHOT_IMPLEMENTATION_PLAN.md. */
typedef struct {
	char     magic[ARCSNAP_MAGIC_SIZE];
	uint32_t format_version;
	uint32_t emulator_version;
	uint32_t flags;
	uint32_t header_crc32;
} arcsnap_header_t;

/* On-disk chunk header (precedes each chunk's payload). */
typedef struct {
	uint32_t id;
	uint32_t version;
	uint64_t size;
	uint32_t crc32;
	uint32_t reserved;
} arcsnap_chunk_header_t;

#define ARCSNAP_HEADER_DISK_SIZE       24u  /* 8 + 4 + 4 + 4 + 4 */
#define ARCSNAP_CHUNK_HEADER_DISK_SIZE 24u  /* 4 + 4 + 8 + 4 + 4 */

#ifdef __cplusplus
}
#endif

#endif /* SNAPSHOT_CHUNKS_H */

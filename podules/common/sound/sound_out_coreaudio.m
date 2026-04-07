#import <AudioToolbox/AudioToolbox.h>

#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "sound_out.h"

#define AUDIO_QUEUE_BUFFER_COUNT 3
#define BYTES_PER_FRAME (sizeof(int16_t) * 2)

typedef struct ring_buffer_t
{
	uint8_t *data;
	size_t capacity;
	size_t read_pos;
	size_t write_pos;
	size_t size;
} ring_buffer_t;

typedef struct coreaudio_sound_t
{
	AudioQueueRef queue;
	AudioQueueBufferRef buffers[AUDIO_QUEUE_BUFFER_COUNT];
	UInt32 buffer_payload_bytes[AUDIO_QUEUE_BUFFER_COUNT];
	pthread_mutex_t mutex;
	ring_buffer_t ring;
	size_t queued_bytes;
	size_t drop_threshold_bytes;
	UInt32 queue_buffer_bytes;
	int started;
} coreaudio_sound_t;

static size_t max_size(size_t a, size_t b)
{
	return (a > b) ? a : b;
}

static void ring_init(ring_buffer_t *ring, size_t capacity)
{
	ring->data = malloc(capacity);
	ring->capacity = ring->data ? capacity : 0;
	ring->read_pos = 0;
	ring->write_pos = 0;
	ring->size = 0;
}

static void ring_free(ring_buffer_t *ring)
{
	free(ring->data);
	memset(ring, 0, sizeof(*ring));
}

static size_t ring_write(ring_buffer_t *ring, const void *src, size_t bytes)
{
	size_t bytes_to_write = bytes;
	size_t first_chunk;

	if (bytes_to_write > (ring->capacity - ring->size))
		bytes_to_write = ring->capacity - ring->size;
	if (!bytes_to_write)
		return 0;

	first_chunk = ring->capacity - ring->write_pos;
	if (first_chunk > bytes_to_write)
		first_chunk = bytes_to_write;

	memcpy(ring->data + ring->write_pos, src, first_chunk);
	if (bytes_to_write > first_chunk)
		memcpy(ring->data, (const uint8_t *)src + first_chunk, bytes_to_write - first_chunk);

	ring->write_pos = (ring->write_pos + bytes_to_write) % ring->capacity;
	ring->size += bytes_to_write;
	return bytes_to_write;
}

static size_t ring_read(ring_buffer_t *ring, void *dst, size_t bytes)
{
	size_t bytes_to_read = bytes;
	size_t first_chunk;

	if (bytes_to_read > ring->size)
		bytes_to_read = ring->size;
	if (!bytes_to_read)
		return 0;

	first_chunk = ring->capacity - ring->read_pos;
	if (first_chunk > bytes_to_read)
		first_chunk = bytes_to_read;

	memcpy(dst, ring->data + ring->read_pos, first_chunk);
	if (bytes_to_read > first_chunk)
		memcpy((uint8_t *)dst + first_chunk, ring->data, bytes_to_read - first_chunk);

	ring->read_pos = (ring->read_pos + bytes_to_read) % ring->capacity;
	ring->size -= bytes_to_read;
	return bytes_to_read;
}

static int find_buffer_index(coreaudio_sound_t *sound, AudioQueueBufferRef buffer)
{
	int i;

	for (i = 0; i < AUDIO_QUEUE_BUFFER_COUNT; i++)
	{
		if (sound->buffers[i] == buffer)
			return i;
	}
	return -1;
}

static void audio_queue_callback(void *user_data, AudioQueueRef queue, AudioQueueBufferRef buffer)
{
	coreaudio_sound_t *sound = (coreaudio_sound_t *)user_data;
	int buffer_index = find_buffer_index(sound, buffer);
	size_t bytes_read;

	(void)queue;

	pthread_mutex_lock(&sound->mutex);

	if (buffer_index >= 0 && sound->buffer_payload_bytes[buffer_index] <= sound->queued_bytes)
		sound->queued_bytes -= sound->buffer_payload_bytes[buffer_index];
	else if (buffer_index >= 0)
		sound->queued_bytes = 0;

	if (buffer_index >= 0)
		sound->buffer_payload_bytes[buffer_index] = 0;

	bytes_read = ring_read(&sound->ring, buffer->mAudioData, sound->queue_buffer_bytes);
	if (bytes_read < sound->queue_buffer_bytes)
		memset((uint8_t *)buffer->mAudioData + bytes_read, 0, sound->queue_buffer_bytes - bytes_read);

	if (buffer_index >= 0)
		sound->buffer_payload_bytes[buffer_index] = (UInt32)bytes_read;

	pthread_mutex_unlock(&sound->mutex);

	buffer->mAudioDataByteSize = sound->queue_buffer_bytes;
	AudioQueueEnqueueBuffer(sound->queue, buffer, 0, NULL);
}

void *sound_out_init(void *p, int freq, int buffer_size, void (*log)(const char *format, ...), const podule_callbacks_t *podule_callbacks, podule_t *podule)
{
	AudioStreamBasicDescription format = {0};
	coreaudio_sound_t *sound;
	OSStatus status;
	size_t ring_capacity;
	int i;

	(void)p;
	(void)log;
	(void)podule_callbacks;
	(void)podule;

	sound = calloc(1, sizeof(coreaudio_sound_t));
	if (!sound)
		return NULL;

	sound->queue_buffer_bytes = (UInt32)max_size((size_t)buffer_size * BYTES_PER_FRAME, (size_t)512 * BYTES_PER_FRAME);
	sound->drop_threshold_bytes = (size_t)buffer_size * BYTES_PER_FRAME * 4;
	ring_capacity = max_size((size_t)freq * BYTES_PER_FRAME, sound->queue_buffer_bytes * 8);
	ring_init(&sound->ring, ring_capacity);
	if (!sound->ring.data)
	{
		free(sound);
		return NULL;
	}

	pthread_mutex_init(&sound->mutex, NULL);

	format.mSampleRate = freq;
	format.mFormatID = kAudioFormatLinearPCM;
	format.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
	format.mBitsPerChannel = 16;
	format.mChannelsPerFrame = 2;
	format.mBytesPerFrame = BYTES_PER_FRAME;
	format.mFramesPerPacket = 1;
	format.mBytesPerPacket = BYTES_PER_FRAME;

	status = AudioQueueNewOutput(&format, audio_queue_callback, sound, NULL, NULL, 0, &sound->queue);
	if (status != noErr)
	{
		pthread_mutex_destroy(&sound->mutex);
		ring_free(&sound->ring);
		free(sound);
		return NULL;
	}

	for (i = 0; i < AUDIO_QUEUE_BUFFER_COUNT; i++)
	{
		status = AudioQueueAllocateBuffer(sound->queue, sound->queue_buffer_bytes, &sound->buffers[i]);
		if (status != noErr)
		{
			AudioQueueDispose(sound->queue, true);
			pthread_mutex_destroy(&sound->mutex);
			ring_free(&sound->ring);
			free(sound);
			return NULL;
		}

		memset(sound->buffers[i]->mAudioData, 0, sound->queue_buffer_bytes);
		sound->buffers[i]->mAudioDataByteSize = sound->queue_buffer_bytes;
		status = AudioQueueEnqueueBuffer(sound->queue, sound->buffers[i], 0, NULL);
		if (status != noErr)
		{
			AudioQueueDispose(sound->queue, true);
			pthread_mutex_destroy(&sound->mutex);
			ring_free(&sound->ring);
			free(sound);
			return NULL;
		}
	}

	status = AudioQueueStart(sound->queue, NULL);
	if (status != noErr)
	{
		AudioQueueDispose(sound->queue, true);
		pthread_mutex_destroy(&sound->mutex);
		ring_free(&sound->ring);
		free(sound);
		return NULL;
	}

	sound->started = 1;
	return sound;
}

void sound_out_close(void *p)
{
	coreaudio_sound_t *sound = (coreaudio_sound_t *)p;

	if (!sound)
		return;

	if (sound->queue)
	{
		if (sound->started)
			AudioQueueStop(sound->queue, true);
		AudioQueueDispose(sound->queue, true);
	}

	pthread_mutex_destroy(&sound->mutex);
	ring_free(&sound->ring);
	free(sound);
}

void sound_out_buffer(void *p, int16_t *buffer, int len)
{
	coreaudio_sound_t *sound = (coreaudio_sound_t *)p;
	size_t bytes = (size_t)len * BYTES_PER_FRAME;

	if (!sound || !buffer)
		return;

	pthread_mutex_lock(&sound->mutex);

	if (sound->queued_bytes > sound->drop_threshold_bytes)
	{
		pthread_mutex_unlock(&sound->mutex);
		return;
	}

	bytes = ring_write(&sound->ring, buffer, bytes);
	sound->queued_bytes += bytes;

	pthread_mutex_unlock(&sound->mutex);
}

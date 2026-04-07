#import <AudioToolbox/AudioToolbox.h>

#include <math.h>
#include <pthread.h>
#include <stdint.h>
#include <string.h>

#include "arc.h"
#include "disc.h"
#include "plat_sound.h"
#include "sound.h"

#define DDNOISE_FREQ 44100
#define OUTPUT_FREQ 48000
#define OUTPUT_CHANNELS 2
#define OUTPUT_BYTES_PER_FRAME (sizeof(int16_t) * OUTPUT_CHANNELS)
#define OUTPUT_FRAMES_PER_BUFFER 2400
#define OUTPUT_BUFFER_BYTES (OUTPUT_FRAMES_PER_BUFFER * OUTPUT_BYTES_PER_FRAME)

#define DDNOISE_INPUT_SAMPLES 4410
#define DDNOISE_OUTPUT_FRAMES 4800
#define DDNOISE_OUTPUT_SAMPLES (DDNOISE_OUTPUT_FRAMES * OUTPUT_CHANNELS)

#define RING_CAPACITY (OUTPUT_FREQ * OUTPUT_BYTES_PER_FRAME)

#define MAX_QUEUED_SIZE ((OUTPUT_FREQ * 4) / 5) /*200ms*/
#define MAX_DDNOISE_STREAM_SIZE ((DDNOISE_FREQ * 4) / 5) /*200ms*/

#define AUDIO_QUEUE_BUFFER_COUNT 3

typedef struct ring_buffer_t
{
	uint8_t data[RING_CAPACITY];
	size_t capacity;
	size_t read_pos;
	size_t write_pos;
	size_t size;
} ring_buffer_t;

typedef struct coreaudio_backend_t
{
	AudioQueueRef queue;
	AudioQueueBufferRef buffers[AUDIO_QUEUE_BUFFER_COUNT];
	UInt32 buffer_payload_bytes[AUDIO_QUEUE_BUFFER_COUNT];
	pthread_mutex_t mutex;
	ring_buffer_t playback_ring;
	ring_buffer_t ddnoise_ring;
	size_t playback_queued_bytes;
	size_t ddnoise_queued_bytes;
	int cached_sound_gain;
	int cached_ddnoise_gain;
	int sound_gain_linear;
	int ddnoise_gain_linear;
	int started;
	int available;
} coreaudio_backend_t;

static coreaudio_backend_t backend;

static int db_to_linear(int gain_db)
{
	return (int)(pow(10.0, (double)gain_db / 20.0) * 256.0);
}

static void ring_init(ring_buffer_t *ring, size_t capacity)
{
	ring->capacity = capacity;
	ring->read_pos = 0;
	ring->write_pos = 0;
	ring->size = 0;
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

static int16_t clamp_sample(int32_t sample)
{
	if (sample < INT16_MIN)
		return INT16_MIN;
	if (sample > INT16_MAX)
		return INT16_MAX;
	return (int16_t)sample;
}

static void resample_ddnoise_chunk(const int16_t *input, int16_t *output)
{
	for (int frame = 0; frame < DDNOISE_OUTPUT_FRAMES; frame++)
	{
		double source_position = ((double)frame * (double)DDNOISE_INPUT_SAMPLES) / (double)DDNOISE_OUTPUT_FRAMES;
		int source_index = (int)source_position;
		double fraction = source_position - (double)source_index;
		int next_index = (source_index + 1 < DDNOISE_INPUT_SAMPLES) ? source_index + 1 : source_index;
		double interpolated = ((double)input[source_index] * (1.0 - fraction)) + ((double)input[next_index] * fraction);
		int16_t sample = clamp_sample((int32_t)lrint(interpolated));

		output[frame * 2] = sample;
		output[frame * 2 + 1] = sample;
	}
}

static int find_buffer_index(AudioQueueBufferRef buffer)
{
	for (int i = 0; i < AUDIO_QUEUE_BUFFER_COUNT; i++)
	{
		if (backend.buffers[i] == buffer)
			return i;
	}
	return -1;
}

static void audio_queue_callback(void *user_data, AudioQueueRef queue, AudioQueueBufferRef buffer)
{
	coreaudio_backend_t *state = (coreaudio_backend_t *)user_data;
	int buffer_index = find_buffer_index(buffer);
	size_t bytes_read = 0;

	(void)queue;

	pthread_mutex_lock(&state->mutex);

	if (buffer_index >= 0 && state->buffer_payload_bytes[buffer_index] <= state->playback_queued_bytes)
		state->playback_queued_bytes -= state->buffer_payload_bytes[buffer_index];
	else if (buffer_index >= 0)
		state->playback_queued_bytes = 0;

	if (buffer_index >= 0)
		state->buffer_payload_bytes[buffer_index] = 0;

	bytes_read = ring_read(&state->playback_ring, buffer->mAudioData, OUTPUT_BUFFER_BYTES);
	if (bytes_read < OUTPUT_BUFFER_BYTES)
		memset((uint8_t *)buffer->mAudioData + bytes_read, 0, OUTPUT_BUFFER_BYTES - bytes_read);

	if (buffer_index >= 0)
		state->buffer_payload_bytes[buffer_index] = (UInt32)bytes_read;

	pthread_mutex_unlock(&state->mutex);

	buffer->mAudioDataByteSize = OUTPUT_BUFFER_BYTES;
	AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
}

void sound_dev_init(void)
{
	AudioStreamBasicDescription format = {0};
	OSStatus status;

	memset(&backend, 0, sizeof(backend));
	ring_init(&backend.playback_ring, RING_CAPACITY);
	ring_init(&backend.ddnoise_ring, RING_CAPACITY);
	pthread_mutex_init(&backend.mutex, NULL);

	backend.cached_sound_gain = sound_gain;
	backend.cached_ddnoise_gain = disc_noise_gain;
	backend.sound_gain_linear = db_to_linear(sound_gain);
	backend.ddnoise_gain_linear = db_to_linear(disc_noise_gain);

	format.mSampleRate = OUTPUT_FREQ;
	format.mFormatID = kAudioFormatLinearPCM;
	format.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
	format.mBitsPerChannel = 16;
	format.mChannelsPerFrame = OUTPUT_CHANNELS;
	format.mBytesPerFrame = OUTPUT_BYTES_PER_FRAME;
	format.mFramesPerPacket = 1;
	format.mBytesPerPacket = OUTPUT_BYTES_PER_FRAME;

	status = AudioQueueNewOutput(&format, audio_queue_callback, &backend, NULL, NULL, 0, &backend.queue);
	if (status != noErr)
	{
		rpclog("AudioQueueNewOutput failed: %d\n", (int)status);
		pthread_mutex_destroy(&backend.mutex);
		return;
	}

	for (int i = 0; i < AUDIO_QUEUE_BUFFER_COUNT; i++)
	{
		status = AudioQueueAllocateBuffer(backend.queue, OUTPUT_BUFFER_BYTES, &backend.buffers[i]);
		if (status != noErr)
		{
			rpclog("AudioQueueAllocateBuffer failed: %d\n", (int)status);
			AudioQueueDispose(backend.queue, true);
			pthread_mutex_destroy(&backend.mutex);
			memset(&backend, 0, sizeof(backend));
			return;
		}

		memset(backend.buffers[i]->mAudioData, 0, OUTPUT_BUFFER_BYTES);
		backend.buffers[i]->mAudioDataByteSize = OUTPUT_BUFFER_BYTES;
		status = AudioQueueEnqueueBuffer(backend.queue, backend.buffers[i], 0, NULL);
		if (status != noErr)
		{
			rpclog("AudioQueueEnqueueBuffer failed during init: %d\n", (int)status);
			AudioQueueDispose(backend.queue, true);
			pthread_mutex_destroy(&backend.mutex);
			memset(&backend, 0, sizeof(backend));
			return;
		}
	}

	status = AudioQueueStart(backend.queue, NULL);
	if (status != noErr)
	{
		rpclog("AudioQueueStart failed: %d\n", (int)status);
		AudioQueueDispose(backend.queue, true);
		pthread_mutex_destroy(&backend.mutex);
		memset(&backend, 0, sizeof(backend));
		return;
	}

	backend.started = 1;
	backend.available = 1;
}

void sound_dev_close(void)
{
	if (!backend.available)
		return;

	if (backend.started)
		AudioQueueStop(backend.queue, true);
	if (backend.queue)
		AudioQueueDispose(backend.queue, true);

	pthread_mutex_destroy(&backend.mutex);
	memset(&backend, 0, sizeof(backend));
}

void sound_givebuffer(int16_t *buf)
{
	int16_t mixed_buffer[OUTPUT_FRAMES_PER_BUFFER * OUTPUT_CHANNELS];
	int16_t ddnoise_buffer[OUTPUT_FRAMES_PER_BUFFER * OUTPUT_CHANNELS];
	size_t ddnoise_bytes = 0;
	size_t mixed_bytes;

	if (!backend.available)
		return;

	if (backend.cached_sound_gain != sound_gain)
	{
		backend.cached_sound_gain = sound_gain;
		backend.sound_gain_linear = db_to_linear(sound_gain);
	}
	if (backend.cached_ddnoise_gain != disc_noise_gain)
	{
		backend.cached_ddnoise_gain = disc_noise_gain;
		backend.ddnoise_gain_linear = db_to_linear(disc_noise_gain);
	}

	pthread_mutex_lock(&backend.mutex);
	if (backend.playback_queued_bytes > MAX_QUEUED_SIZE)
	{
		pthread_mutex_unlock(&backend.mutex);
		return;
	}

	ddnoise_bytes = ring_read(&backend.ddnoise_ring, ddnoise_buffer, sizeof(ddnoise_buffer));
	backend.ddnoise_queued_bytes -= ddnoise_bytes;
	pthread_mutex_unlock(&backend.mutex);

	for (int i = 0; i < OUTPUT_FRAMES_PER_BUFFER * OUTPUT_CHANNELS; i++)
	{
		int32_t sample = (buf[i] * backend.sound_gain_linear) >> 8;
		mixed_buffer[i] = clamp_sample(sample);
	}

	for (size_t i = 0; i < ddnoise_bytes / sizeof(int16_t); i++)
	{
		int32_t sample = mixed_buffer[i] + ((ddnoise_buffer[i] * backend.ddnoise_gain_linear) >> 8);
		mixed_buffer[i] = clamp_sample(sample);
	}

	pthread_mutex_lock(&backend.mutex);
	mixed_bytes = ring_write(&backend.playback_ring, mixed_buffer, sizeof(mixed_buffer));
	backend.playback_queued_bytes += mixed_bytes;
	pthread_mutex_unlock(&backend.mutex);
}

void sound_givebufferdd(int16_t *buf)
{
	int16_t converted[DDNOISE_OUTPUT_SAMPLES];
	size_t converted_bytes;

	if (!backend.available)
		return;
	if (disc_noise_gain == DISC_NOISE_DISABLED)
		return;

	pthread_mutex_lock(&backend.mutex);
	if (backend.ddnoise_queued_bytes > MAX_DDNOISE_STREAM_SIZE)
	{
		pthread_mutex_unlock(&backend.mutex);
		return;
	}

	resample_ddnoise_chunk(buf, converted);
	converted_bytes = ring_write(&backend.ddnoise_ring, converted, sizeof(converted));
	backend.ddnoise_queued_bytes += converted_bytes;
	pthread_mutex_unlock(&backend.mutex);
}

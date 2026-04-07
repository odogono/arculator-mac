#ifndef PLATFORM_PATHS_H
#define PLATFORM_PATHS_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

void platform_paths_init(const char *argv0);

void platform_path_join_resource(char *dest, const char *relative, size_t size);
void platform_path_join_support(char *dest, const char *relative, size_t size);

void platform_path_global_config(char *dest, size_t size);
void platform_path_machine_config(char *dest, size_t size, const char *config_name);
void platform_path_configs_dir(char *dest, size_t size);
void platform_path_drives_dir(char *dest, size_t size);
void platform_path_hostfs_dir(char *dest, size_t size);
void platform_path_podules_user_dir(char *dest, size_t size);
void platform_path_podules_bundle_dir(char *dest, size_t size);
void platform_path_snapshots_dir(char *dest, size_t size);
void platform_path_snapshot_runtime_dir(char *dest, size_t size, const char *id);

int platform_path_find_rom_path(char *dest, const char *relative, size_t size);

void platform_paths_init_test(const char *support, const char *resources);
void platform_paths_reset(void);

#ifdef __cplusplus
}
#endif

#endif

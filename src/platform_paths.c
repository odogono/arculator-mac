#include "platform_paths.h"

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#ifdef __APPLE__
#include <CoreFoundation/CoreFoundation.h>
#endif

static char legacy_root[PATH_MAX];
static char resources_root[PATH_MAX];
static char support_root[PATH_MAX];
static int paths_initialized = 0;

static void ensure_paths_initialized(void)
{
	if (!paths_initialized)
		platform_paths_init(NULL);
}

static void copy_string(char *dest, size_t size, const char *src)
{
	if (!size)
		return;

	if (!src)
		src = "";

	snprintf(dest, size, "%s", src);
}

static void dirname_from_argv0(char *dest, size_t size, const char *argv0)
{
	char temp[PATH_MAX];
	char *slash;

	if (!argv0 || !argv0[0])
	{
		if (!getcwd(temp, sizeof(temp)))
			copy_string(temp, sizeof(temp), ".");
	}
	else
		copy_string(temp, sizeof(temp), argv0);

	slash = strrchr(temp, '/');
	if (!slash)
		slash = strrchr(temp, '\\');

	if (slash)
		slash[1] = 0;
	else
		copy_string(temp, sizeof(temp), "./");

	copy_string(dest, size, temp);
}

static void join_path(char *dest, size_t size, const char *base, const char *relative)
{
	size_t len;

	if (!relative || !relative[0])
	{
		copy_string(dest, size, base);
		return;
	}

	len = strlen(base);
	if (len && (base[len - 1] == '/' || base[len - 1] == '\\'))
		snprintf(dest, size, "%s%s", base, relative);
	else
		snprintf(dest, size, "%s/%s", base, relative);
}

static int path_exists(const char *path)
{
	struct stat st;

	return path && !stat(path, &st);
}

static void trim_trailing_whitespace(char *value)
{
	size_t len = strlen(value);

	while (len && (value[len - 1] == ' ' || value[len - 1] == '\t' || value[len - 1] == '\r' || value[len - 1] == '\n'))
		value[--len] = 0;
}

static const char *skip_whitespace(const char *value)
{
	while (*value == ' ' || *value == '\t')
		value++;

	return value;
}

static int read_rom_root_from_config_file(char *dest, size_t size, const char *config_path)
{
	char line[PATH_MAX];
	FILE *config_file;

	config_file = fopen(config_path, "r");
	if (!config_file)
		return 0;

	while (fgets(line, sizeof(line), config_file))
	{
		char *equals;
		char *value;

		if (line[0] == '[')
			break;

		equals = strchr(line, '=');
		if (!equals)
			continue;

		*equals = 0;
		trim_trailing_whitespace(line);
		if (strcmp(skip_whitespace(line), "rom_path"))
			continue;

		value = equals + 1;
		value = (char *)skip_whitespace(value);
		trim_trailing_whitespace(value);
		if (!value[0])
			break;

		copy_string(dest, size, value);
		fclose(config_file);
		return 1;
	}

	fclose(config_file);
	return 0;
}

static char cached_rom_root[PATH_MAX];
static int rom_root_cached = 0; /* 0 = not checked, 1 = checked but empty, 2 = found */

static int read_configured_rom_root(char *dest, size_t size)
{
	char config_path[PATH_MAX];

	if (rom_root_cached)
	{
		if (rom_root_cached == 2)
		{
			copy_string(dest, size, cached_rom_root);
			return 1;
		}
		return 0;
	}

	platform_path_global_config(config_path, sizeof(config_path));
	if (read_rom_root_from_config_file(cached_rom_root, sizeof(cached_rom_root), config_path))
	{
		rom_root_cached = 2;
		copy_string(dest, size, cached_rom_root);
		return 1;
	}

	if (strcmp(support_root, legacy_root))
	{
		join_path(config_path, sizeof(config_path), legacy_root, "arc.cfg");
		if (read_rom_root_from_config_file(cached_rom_root, sizeof(cached_rom_root), config_path))
		{
			rom_root_cached = 2;
			copy_string(dest, size, cached_rom_root);
			return 1;
		}
	}

	rom_root_cached = 1;
	return 0;
}

static int mkdir_if_needed(const char *path)
{
	struct stat st;

	if (!stat(path, &st))
		return S_ISDIR(st.st_mode) ? 0 : -1;

	return mkdir(path, 0777);
}

static void ensure_dir_recursive(const char *path)
{
	char temp[PATH_MAX];
	size_t len;
	size_t i;

	copy_string(temp, sizeof(temp), path);
	len = strlen(temp);

	if (!len)
		return;

	for (i = 1; i < len; i++)
	{
		if (temp[i] != '/')
			continue;

		temp[i] = 0;
		if (temp[0])
			(void)mkdir_if_needed(temp);
		temp[i] = '/';
	}

	(void)mkdir_if_needed(temp);
}

void platform_paths_init(const char *argv0)
{
	char path[PATH_MAX];

	if (paths_initialized)
		return;

	dirname_from_argv0(legacy_root, sizeof(legacy_root), argv0);
	copy_string(resources_root, sizeof(resources_root), legacy_root);
	copy_string(support_root, sizeof(support_root), legacy_root);

#ifdef __APPLE__
	{
		CFBundleRef bundle = CFBundleGetMainBundle();
		CFURLRef resources_url;
		char cf_path[PATH_MAX];

		if (bundle)
		{
			resources_url = CFBundleCopyResourcesDirectoryURL(bundle);
			if (resources_url)
			{
				if (CFURLGetFileSystemRepresentation(resources_url, true, (UInt8 *)cf_path, sizeof(cf_path)))
					copy_string(resources_root, sizeof(resources_root), cf_path);
				CFRelease(resources_url);
			}
		}
	}

	{
		const char *home = getenv("HOME");

		if (home && home[0])
			snprintf(support_root, sizeof(support_root), "%s/Library/Application Support/Arculator", home);
	}

	ensure_dir_recursive(support_root);
	join_path(path, sizeof(path), support_root, "configs");
	ensure_dir_recursive(path);
	join_path(path, sizeof(path), support_root, "cmos");
	ensure_dir_recursive(path);
	join_path(path, sizeof(path), support_root, "hostfs");
	ensure_dir_recursive(path);
	join_path(path, sizeof(path), support_root, "podules");
	ensure_dir_recursive(path);
	join_path(path, sizeof(path), support_root, "roms");
	ensure_dir_recursive(path);
#endif

	paths_initialized = 1;
}

void platform_path_join_resource(char *dest, const char *relative, size_t size)
{
	ensure_paths_initialized();
	join_path(dest, size, resources_root, relative);
}

void platform_path_join_support(char *dest, const char *relative, size_t size)
{
	ensure_paths_initialized();
	join_path(dest, size, support_root, relative);
}

void platform_path_global_config(char *dest, size_t size)
{
	platform_path_join_support(dest, "arc.cfg", size);
}

void platform_path_machine_config(char *dest, size_t size, const char *config_name)
{
	char relative[PATH_MAX];

	snprintf(relative, sizeof(relative), "configs/%s.cfg", config_name);
	platform_path_join_support(dest, relative, size);
}

void platform_path_configs_dir(char *dest, size_t size)
{
	platform_path_join_support(dest, "configs", size);
}

void platform_path_hostfs_dir(char *dest, size_t size)
{
	platform_path_join_support(dest, "hostfs", size);
}

void platform_path_podules_user_dir(char *dest, size_t size)
{
	platform_path_join_support(dest, "podules", size);
}

void platform_path_podules_bundle_dir(char *dest, size_t size)
{
	platform_path_join_resource(dest, "podules", size);
}

int platform_path_find_rom_path(char *dest, const char *relative, size_t size)
{
	char candidate[PATH_MAX];
	char legacy_candidate[PATH_MAX];

	ensure_paths_initialized();

	if (read_configured_rom_root(candidate, sizeof(candidate)))
	{
		join_path(dest, size, candidate, relative);
		if (path_exists(dest))
			return 1;
	}

	platform_path_join_support(candidate, "roms", sizeof(candidate));
	join_path(dest, size, candidate, relative);
	if (path_exists(dest))
		return 1;

	platform_path_join_resource(candidate, "roms", sizeof(candidate));
	join_path(dest, size, candidate, relative);
	if (path_exists(dest))
		return 1;

	join_path(legacy_candidate, sizeof(legacy_candidate), legacy_root, "roms");
	join_path(dest, size, legacy_candidate, relative);
	return path_exists(dest);
}

#include <dlfcn.h>
#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "arc.h"
#include "config.h"
#include "platform_paths.h"
#include "podules.h"

typedef struct dll_t
{
	void *lib;
	struct dll_t *next;
} dll_t;

static dll_t *dll_head = NULL;

static void closedlls(void)
{
	dll_t *dll = dll_head;

	while (dll)
	{
		dll_t *dll_next = dll->next;

		if (dll->lib)
			dlclose(dll->lib);
		free(dll);

		dll = dll_next;
	}
}

static void opendlls_from_path(const char *podule_path)
{
	DIR *dirp;
	struct dirent *dp;

	rpclog("Looking for podules in %s\n", podule_path);
	dirp = opendir(podule_path);
	if (!dirp)
	{
		return;
	}

	while (((dp = readdir(dirp)) != NULL))
	{
		const podule_header_t *(*podule_probe)(const podule_callbacks_t *callbacks, char *path);
		const podule_header_t *header;
		char so_fn[512], so_name[512], podule_dir[512];
		dll_t *dll;

		if (!strcmp(dp->d_name, ".") || !strcmp(dp->d_name, ".."))
			continue;

		if (dp->d_type == DT_DIR)
		{
			snprintf(so_name, sizeof(so_name), "%s.dylib", dp->d_name);
			append_filename(podule_dir, podule_path, dp->d_name, sizeof(podule_dir));
			append_filename(so_fn, podule_dir, so_name, sizeof(so_fn));
			append_filename(podule_dir, podule_dir, "/", sizeof(podule_dir));
		}
		else if (dp->d_type == DT_REG)
		{
			const char *ext = strrchr(dp->d_name, '.');

			if (!ext || strcmp(ext, ".dylib"))
				continue;

			append_filename(so_fn, podule_path, dp->d_name, sizeof(so_fn));
			append_filename(podule_dir, podule_path, "/", sizeof(podule_dir));
		}
		else
		{
			continue;
		}

		dll = malloc(sizeof(dll_t));
		memset(dll, 0, sizeof(dll_t));

		dll->lib = dlopen(so_fn, RTLD_NOW);
		if (dll->lib == NULL)
		{
			char *lasterror = dlerror();
			rpclog("Failed to open dylib %s %s\n", dp->d_name, lasterror);
			free(dll);
			continue;
		}
		podule_probe = (const void *)dlsym(dll->lib, "podule_probe");
		if (podule_probe == NULL)
		{
			rpclog("Couldn't find podule_probe in %s\n", dp->d_name);
			dlclose(dll->lib);
			free(dll);
			continue;
		}
		header = podule_probe(&podule_callbacks_def, podule_dir);
		if (!header)
		{
			rpclog("podule_probe failed %s\n", dp->d_name);
			dlclose(dll->lib);
			free(dll);
			continue;
		}
		rpclog("podule_probe returned %p\n", header);

		uint32_t valid_flags = podule_validate_and_get_valid_flags(header);
		if (!valid_flags)
		{
			rpclog("podule_probe failed validation %s\n", dp->d_name);
			dlclose(dll->lib);
			free(dll);
			continue;
		}

		uint32_t flags;
		do
		{
			flags = header->flags;
			if (flags & ~valid_flags)
			{
				rpclog("podule_probe: podule header fails flags validation\n");
				break;
			}

			if (!podule_find(header->short_name))
				podule_add(header);
			header++;
		} while (flags & PODULE_FLAGS_NEXT);

		dll->next = dll_head;
		dll_head = dll;
	}

	(void)closedir(dirp);
}

void opendlls(void)
{
	char user_path[512];
	char bundle_path[512];

	atexit(closedlls);

	platform_path_podules_user_dir(user_path, sizeof(user_path));
	platform_path_podules_bundle_dir(bundle_path, sizeof(bundle_path));

	opendlls_from_path(user_path);
	if (strcmp(user_path, bundle_path))
		opendlls_from_path(bundle_path);
}

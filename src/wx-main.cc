/*Arculator 2.1 by Sarah Walker
  Main function*/
#include "wx-app.h"
#include <SDL.h>
#include <wx/filename.h>
#include "wx-config_sel.h"

extern "C"
{
#if !defined(_WIN32) && !defined(__APPLE__)
#include <X11/Xlib.h>
#endif
#include "arc.h"
#include "config.h"
#include "platform_paths.h"
#include "podules.h"
}

int main(int argc, char **argv)
{
#if !defined(_WIN32) && !defined(__APPLE__)
	XInitThreads();
#endif

	strncpy(exname, argv[0], 511);
	char *p = (char *)get_filename(exname);
	*p = 0;
	platform_paths_init(argv[0]);

	const char *config_arg = NULL;
	for (int i = 1; i < argc; i++)
	{
		if (argv[i][0] != '-')
		{
			config_arg = argv[i];
			break;
		}
		else if (i + 1 < argc && argv[i + 1][0] != '-')
			i++; /* skip value of flag arguments like -NSDocumentRevisionsDebugMode YES */
	}

	if (config_arg)
	{
		wxString config_path = GetConfigPath(config_arg);

		if (wxFileName(config_path).Exists())
		{
			strcpy(machine_config_file, config_path.mb_str());
			strcpy(machine_config_name, config_arg);
		}
		else
		{
			wxMessageBox("A configuration with the name '" + wxString(config_arg) + "' does not exist", "Arculator", wxOK | wxCENTRE | wxSTAY_ON_TOP);
			exit(-1);
		}
	}

	podule_build_list();
	opendlls();
#ifdef _WIN32
	SDL_SetHint(SDL_HINT_WINDOWS_DISABLE_THREAD_NAMING, "1");
#endif

	wxApp::SetInstance(new App());
	wxEntry(argc, argv);

	return 0;
}

/*Arculator 2.1 by Sarah Walker
  Configuration selector dialogue*/
#include <wx/wxprec.h>

#ifndef WX_PRECOMP
#include <wx/wx.h>
#endif

#include <wx/xrc/xmlres.h>
#include "wx-config.h"
#include "wx-config_sel.h"

extern "C"
{
	#include "arc.h"
	#include "config.h"
	#include "platform_paths.h"
	void rpclog(const char *format, ...);
};

class ConfigSelDialog: public wxDialog
{
public:
	ConfigSelDialog(wxWindow* parent);
private:
	bool EnsureSelection();
	bool LoadSelectedConfig();
	void OnOK(wxCommandEvent &event);
	void OnCancel(wxCommandEvent &event);
	void OnNew(wxCommandEvent &event);
	void OnRename(wxCommandEvent &event);
	void OnCopy(wxCommandEvent &event);
	void OnDelete(wxCommandEvent &event);
	void OnConfig(wxCommandEvent &event);
	void OnDClickConfig(wxCommandEvent &event);

	void BuildConfigList();
};

ConfigSelDialog::ConfigSelDialog(wxWindow* parent)
{
	wxXmlResource::Get()->LoadDialog(this, parent, "ConfigureSelectionDlg");

	Bind(wxEVT_BUTTON, &ConfigSelDialog::OnOK, this, wxID_OK);
	Bind(wxEVT_BUTTON, &ConfigSelDialog::OnCancel, this, wxID_CANCEL);
	Bind(wxEVT_BUTTON, &ConfigSelDialog::OnNew, this, XRCID("IDC_NEW"));
	Bind(wxEVT_BUTTON, &ConfigSelDialog::OnRename, this, XRCID("IDC_RENAME"));
	Bind(wxEVT_BUTTON, &ConfigSelDialog::OnCopy, this, XRCID("IDC_COPY"));
	Bind(wxEVT_BUTTON, &ConfigSelDialog::OnDelete, this, XRCID("IDC_DELETE"));
	Bind(wxEVT_BUTTON, &ConfigSelDialog::OnConfig, this, XRCID("IDC_CONFIG"));
	Bind(wxEVT_LISTBOX_DCLICK, &ConfigSelDialog::OnDClickConfig, this, XRCID("IDC_LIST"));
	BuildConfigList();
}

void ConfigSelDialog::BuildConfigList()
{
	wxListBox* list = (wxListBox*)FindWindow(XRCID("IDC_LIST"));
	wxString current_selection = list->GetStringSelection();
	char config_dir[512];
	list->Clear();
	wxArrayString items;
	platform_path_configs_dir(config_dir, sizeof(config_dir));
	wxString path(config_dir);
	path += "/*.cfg";
	wxString f = wxFindFirstFile(path);
	while (!f.empty())
	{
		wxFileName file(f);
		items.Add(file.GetName());
		f = wxFindNextFile();
	}
	items.Sort();
	list->Set(items);

	if (!current_selection.IsEmpty())
	{
		int index = list->FindString(current_selection);
		if (index != wxNOT_FOUND)
		{
			list->SetSelection(index);
			return;
		}
	}

	if (list->GetCount() > 0)
		list->SetSelection(0);
}

bool ConfigSelDialog::EnsureSelection()
{
	wxListBox *list = (wxListBox*)FindWindow(XRCID("IDC_LIST"));

	if (list->GetCount() == 0)
		return false;

	if (list->GetSelection() == wxNOT_FOUND)
		list->SetSelection(0);

	return list->GetSelection() != wxNOT_FOUND;
}

bool ConfigSelDialog::LoadSelectedConfig()
{
	wxListBox *list = (wxListBox*)FindWindow(XRCID("IDC_LIST"));

	if (!EnsureSelection())
		return false;

	wxString selection = list->GetStringSelection();
	if (selection.IsEmpty())
		return false;

	wxString config_path = GetConfigPath(selection);
	strcpy(machine_config_file, config_path.mb_str());
	strcpy(machine_config_name, selection.mb_str());
	return true;
}

void ConfigSelDialog::OnOK(wxCommandEvent &event)
{
	if (!EnsureSelection())
	{
		if (wxMessageBox("No machine configurations exist yet. Create one now?",
				 "Arculator", wxYES_NO | wxCENTRE | wxSTAY_ON_TOP, this) == wxYES)
		{
			wxCommandEvent dummy;
			OnNew(dummy);
		}
	}

	if (LoadSelectedConfig())
	{
		EndModal(0);
	}
	else
	{
		wxMessageBox("Select a configuration first.", "Arculator",
			     wxOK | wxCENTRE | wxSTAY_ON_TOP, this);
	}
}
void ConfigSelDialog::OnDClickConfig(wxCommandEvent &event)
{
	if (LoadSelectedConfig())
		EndModal(0);
}
void ConfigSelDialog::OnCancel(wxCommandEvent &event)
{
	EndModal(-1);
}
void ConfigSelDialog::OnNew(wxCommandEvent &event)
{
	wxTextEntryDialog dlg(this, "Enter name:", "New config");
	dlg.SetMaxLength(64);
	if (dlg.ShowModal() == wxID_OK)
	{
		wxString config_name = dlg.GetValue();
		config_name.Trim(true).Trim(false);
		if (config_name.IsEmpty())
		{
			wxMessageBox("Configuration name cannot be empty", "Arculator", wxOK | wxCENTRE | wxSTAY_ON_TOP, this);
			return;
		}

		wxString config_path = GetConfigPath(config_name);

		if (wxFileName(config_path).Exists())
		{
			wxMessageBox("A configuration with that name already exists", "Arculator", wxOK | wxCENTRE | wxSTAY_ON_TOP, this);
		}
		else
		{
			int preset = ShowPresetList();
			if (preset != -1)
			{
				strcpy(machine_config_file, config_path.mb_str());
				strcpy(machine_config_name, config_name.mb_str());

				loadconfig();
				ShowConfigWithPreset(preset);
				BuildConfigList();

				wxListBox *list = (wxListBox*)FindWindow(XRCID("IDC_LIST"));
				int index = list->FindString(config_name);
				if (index != wxNOT_FOUND)
					list->SetSelection(index);
			}
		}
	}
}
void ConfigSelDialog::OnRename(wxCommandEvent &event)
{
	if (!EnsureSelection())
	{
		wxMessageBox("Select a configuration first.", "Arculator", wxOK | wxCENTRE | wxSTAY_ON_TOP, this);
		return;
	}

	wxTextEntryDialog dlg(this, "Enter name:", "Rename config");
	dlg.SetMaxLength(64);
	if (dlg.ShowModal() == wxID_OK)
	{
		wxString config_name = dlg.GetValue();
		config_name.Trim(true).Trim(false);
		if (config_name.IsEmpty())
		{
			wxMessageBox("Configuration name cannot be empty", "Arculator", wxOK | wxCENTRE | wxSTAY_ON_TOP, this);
			return;
		}

		wxString new_config_path = GetConfigPath(config_name);

		wxListBox *list = (wxListBox*)FindWindow(XRCID("IDC_LIST"));
		wxString old_config_path = GetConfigPath(list->GetStringSelection());

		if (wxFileName(new_config_path).Exists())
		{
			wxMessageBox("A configuration with that name already exists", "Arculator", wxOK | wxCENTRE | wxSTAY_ON_TOP, this);
		}
		else
		{
			wxRenameFile(old_config_path, new_config_path, false);
			BuildConfigList();
			int index = list->FindString(config_name);
			if (index != wxNOT_FOUND)
				list->SetSelection(index);
		}
	}
}

void ConfigSelDialog::OnCopy(wxCommandEvent &event)
{
	if (!EnsureSelection())
	{
		wxMessageBox("Select a configuration first.", "Arculator", wxOK | wxCENTRE | wxSTAY_ON_TOP, this);
		return;
	}

	wxTextEntryDialog dlg(this, "Enter name:", "Copy config");
	dlg.SetMaxLength(64);
	if (dlg.ShowModal() == wxID_OK)
	{
		wxString config_name = dlg.GetValue();
		config_name.Trim(true).Trim(false);
		if (config_name.IsEmpty())
		{
			wxMessageBox("Configuration name cannot be empty", "Arculator", wxOK | wxCENTRE | wxSTAY_ON_TOP, this);
			return;
		}

		wxString new_config_path = GetConfigPath(config_name);

		wxListBox *list = (wxListBox*)FindWindow(XRCID("IDC_LIST"));
		wxString old_config_path = GetConfigPath(list->GetStringSelection());

		if (wxFileName(new_config_path).Exists())
		{
			wxMessageBox("A configuration with that name already exists", "Arculator", wxOK | wxCENTRE | wxSTAY_ON_TOP, this);
		}
		else
		{
			wxCopyFile(old_config_path, new_config_path, false);
			BuildConfigList();
			int index = list->FindString(config_name);
			if (index != wxNOT_FOUND)
				list->SetSelection(index);
		}
	}
}
void ConfigSelDialog::OnDelete(wxCommandEvent &event)
{
	if (!EnsureSelection())
	{
		wxMessageBox("Select a configuration first.", "Arculator", wxOK | wxCENTRE | wxSTAY_ON_TOP, this);
		return;
	}

	wxListBox *list = (wxListBox*)FindWindow(XRCID("IDC_LIST"));
	wxString config_name = list->GetStringSelection();

	if (wxMessageBox("Are you sure you want to delete " + config_name + "?", "Arculator", wxYES_NO | wxCENTRE | wxSTAY_ON_TOP, this) == wxYES)
	{
		wxString config_path = GetConfigPath(config_name);

		wxRemoveFile(config_path);
		BuildConfigList();
	}
}
void ConfigSelDialog::OnConfig(wxCommandEvent &event)
{
	if (!LoadSelectedConfig())
	{
		wxMessageBox("Select a configuration first.", "Arculator", wxOK | wxCENTRE | wxSTAY_ON_TOP, this);
		return;
	}

	loadconfig();
	ShowConfig(false);
}

int ShowConfigSelection()
{
	ConfigSelDialog dlg(NULL);

	return dlg.ShowModal();
}

wxString GetConfigPath(wxString config_name)
{
	char path[512];
	platform_path_machine_config(path, sizeof(path), config_name.mb_str());
	return wxString(path);
}

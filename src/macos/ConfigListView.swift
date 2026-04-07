//
//  ConfigListView.swift
//  Arculator
//
//  Sidebar config list shown when emulation is idle. Displays saved
//  configs with selection, context menu (rename/duplicate/delete),
//  and a + button with preset picker popover for creating new configs.
//

import SwiftUI

// MARK: - Config List View

struct ConfigListView: View {

    @ObservedObject var configList: ConfigListModel

    @State private var showingNewConfig = false
    @State private var renamingConfig: String?
    @State private var renameText = ""
    @State private var duplicatingConfig: String?
    @State private var duplicateText = ""
    @State private var deletingConfig: String?

    var body: some View {
        VStack(spacing: 0) {
            if configList.configNames.isEmpty {
                emptyState
            } else {
                configListContent
            }

            Divider()
            bottomBar
        }
        .alert("Rename Configuration",
               isPresented: Binding(
                   get: { renamingConfig != nil },
                   set: { if !$0 { renamingConfig = nil } }
               )
        ) {
            TextField("New name", text: $renameText)
            Button("Cancel", role: .cancel) { renamingConfig = nil }
            Button("Rename") {
                if let oldName = renamingConfig {
                    configList.rename(oldName: oldName, to: renameText)
                }
                renamingConfig = nil
            }
            .disabled(renameText.isEmpty || renameText == renamingConfig
                      || configList.configExists(renameText))
        }
        .alert("Duplicate Configuration",
               isPresented: Binding(
                   get: { duplicatingConfig != nil },
                   set: { if !$0 { duplicatingConfig = nil } }
               )
        ) {
            TextField("New name", text: $duplicateText)
            Button("Cancel", role: .cancel) { duplicatingConfig = nil }
            Button("Duplicate") {
                if let source = duplicatingConfig {
                    configList.duplicate(sourceName: source, to: duplicateText)
                }
                duplicatingConfig = nil
            }
            .disabled(duplicateText.isEmpty || configList.configExists(duplicateText))
        }
        .alert("Delete Configuration",
               isPresented: Binding(
                   get: { deletingConfig != nil },
                   set: { if !$0 { deletingConfig = nil } }
               )
        ) {
            Button("Cancel", role: .cancel) { deletingConfig = nil }
            Button("Delete", role: .destructive) {
                if let name = deletingConfig {
                    configList.delete(name: name)
                }
                deletingConfig = nil
            }
        } message: {
            if let name = deletingConfig {
                Text("Are you sure you want to delete \"\(name)\"? This cannot be undone.")
            }
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "desktopcomputer")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No Configurations")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Click + to create a machine configuration.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button("Create Your First Machine") {
                showingNewConfig = true
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
        .accessibilityIdentifier("configListEmpty")
    }

    private var configListContent: some View {
        List(configList.configNames, id: \.self, selection: $configList.selectedConfigName) { name in
            Text(name)
                .accessibilityIdentifier("configRow_\(name)")
                .contextMenu {
                    Button("Rename...") {
                        renameText = name
                        renamingConfig = name
                    }
                    Button("Duplicate...") {
                        duplicateText = name + " Copy"
                        duplicatingConfig = name
                    }
                    Divider()
                    Button("Delete...", role: .destructive) {
                        deletingConfig = name
                    }
                }
        }
        .accessibilityIdentifier("configList")
    }

    private var bottomBar: some View {
        HStack {
            Button {
                showingNewConfig = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("addConfigButton")
            .popover(isPresented: $showingNewConfig) {
                NewConfigPopover(configList: configList, isPresented: $showingNewConfig)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - New Config Popover

struct NewConfigPopover: View {

    @ObservedObject var configList: ConfigListModel
    @Binding var isPresented: Bool

    @State private var selectedPresetIndex = 0
    @State private var configName = ""

    private var presets: [MachinePreset] { MachinePresets.all }

    private var canCreate: Bool {
        !configName.isEmpty && !configList.configExists(configName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Configuration")
                .font(.headline)

            Picker("Machine", selection: $selectedPresetIndex) {
                ForEach(presets) { preset in
                    Text(preset.name).tag(preset.index)
                }
            }

            if selectedPresetIndex < presets.count {
                Text(presets[selectedPresetIndex].description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField("Configuration name", text: $configName)
                .textFieldStyle(.roundedBorder)

            if !configName.isEmpty && configList.configExists(configName) {
                Text("A configuration with this name already exists.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    configList.create(name: configName, presetIndex: selectedPresetIndex)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear {
            if let first = presets.first {
                configName = first.configName
            }
        }
        .onChange(of: selectedPresetIndex) { newIndex in
            if newIndex < presets.count {
                configName = presets[newIndex].configName
            }
        }
    }
}

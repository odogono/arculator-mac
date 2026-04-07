//
//  DisplaySettingsView.swift
//  Arculator
//
//  Support ROM toggle and placeholder for future display settings.
//

import SwiftUI

struct DisplaySettingsView: View {
    @ObservedObject var config: MachineConfigModel
    @ObservedObject var emulatorState: EmulatorState

    var body: some View {
        Form {
            if config.isSupportROMAvailable {
                supportROMSection
            } else {
                noSettingsPlaceholder
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.visible)
    }

    private var supportROMSection: some View {
        Section("Support ROM") {
            Toggle("Enable Support ROM", isOn: Binding(
                get: { config.supportRomEnabled },
                set: { newValue in
                    config.supportRomEnabled = newValue
                    config.markResetIfNeeded(for: ARCSettingSupportROM)
                }
            ))
            .mutabilityGated(ARCSettingSupportROM, emulatorState: emulatorState)

            Text("Provides additional system utilities for RISC OS 3.0 and later.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var noSettingsPlaceholder: some View {
        Section {
            Text("No display settings available for this configuration.")
                .foregroundStyle(.secondary)
        }
    }
}

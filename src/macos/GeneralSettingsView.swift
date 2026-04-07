//
//  GeneralSettingsView.swift
//  Arculator
//
//  Machine preset picker, CPU, Memory, MEMC, FPU, ROM, Monitor type,
//  IO type display, and Unique ID. Preset changes cascade through
//  dependent fields via MachineConfigModel.
//

import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var config: MachineConfigModel
    @ObservedObject var emulatorState: EmulatorState

    private var presets: [MachinePreset] { MachinePresets.all }

    var body: some View {
        Form {
            machineSection
            processorSection
            memorySection
            systemSection
            if config.ioType == .new_ {
                identitySection
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.visible)
    }

    // MARK: - Machine

    private var machineSection: some View {
        Section("Machine") {
            Picker("Preset", selection: Binding(
                get: { config.presetIndex },
                set: { newValue in
                    config.changePreset(to: newValue)
                    config.markResetIfNeeded(for: ARCSettingMachinePreset)
                }
            )) {
                ForEach(presets) { preset in
                    Text(preset.name).tag(preset.index)
                }
            }
            .mutabilityGated(ARCSettingMachinePreset, emulatorState: emulatorState)

            if let preset = presets.first(where: { $0.index == config.presetIndex }) {
                Text(preset.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Processor

    private var processorSection: some View {
        Section("Processor") {
            Picker("CPU", selection: Binding(
                get: { config.cpu },
                set: { newValue in
                    config.changeCPU(to: newValue)
                    config.markResetIfNeeded(for: ARCSettingCPU)
                }
            )) {
                ForEach(config.allowedCPUs) { cpu in
                    Text(cpu.displayName).tag(cpu)
                }
            }
            .mutabilityGated(ARCSettingCPU, emulatorState: emulatorState)

            Picker("FPU", selection: Binding(
                get: { config.fpu },
                set: { newValue in
                    config.fpu = newValue
                    config.markResetIfNeeded(for: ARCSettingFPU)
                }
            )) {
                Text("None").tag(FPUType.none)
                if config.isFPPCAvailable {
                    Text("FPPC").tag(FPUType.fppc)
                }
                if config.isFPA10Available {
                    Text("FPA10").tag(FPUType.fpa10)
                }
            }
            .mutabilityGated(ARCSettingFPU, emulatorState: emulatorState)
        }
    }

    // MARK: - Memory

    private var memorySection: some View {
        Section("Memory") {
            Picker("RAM", selection: Binding(
                get: { config.memory },
                set: { newValue in
                    config.memory = newValue
                    config.markResetIfNeeded(for: ARCSettingMemory)
                }
            )) {
                ForEach(config.allowedMemory) { mem in
                    Text(mem.displayName).tag(mem)
                }
            }
            .mutabilityGated(ARCSettingMemory, emulatorState: emulatorState)

            Picker("MEMC", selection: Binding(
                get: { config.memc },
                set: { newValue in
                    config.memc = newValue
                    config.markResetIfNeeded(for: ARCSettingMEMC)
                }
            )) {
                ForEach(config.allowedMEMC) { memc in
                    Text(memc.displayName).tag(memc)
                }
            }
            .mutabilityGated(ARCSettingMEMC, emulatorState: emulatorState)
        }
    }

    // MARK: - System

    private var systemSection: some View {
        Section("System") {
            Picker("OS / ROM", selection: Binding(
                get: { config.rom },
                set: { newValue in
                    config.rom = newValue
                    config.markResetIfNeeded(for: ARCSettingROM)
                }
            )) {
                ForEach(config.allowedROMs) { rom in
                    Text(rom.displayName).tag(rom)
                }
            }
            .mutabilityGated(ARCSettingROM, emulatorState: emulatorState)

            Picker("Monitor", selection: Binding(
                get: { config.monitor },
                set: { newValue in
                    config.monitor = newValue
                    config.markResetIfNeeded(for: ARCSettingMonitor)
                }
            )) {
                ForEach(config.allowedMonitors) { mon in
                    Text(mon.displayName).tag(mon)
                }
            }
            .mutabilityGated(ARCSettingMonitor, emulatorState: emulatorState)

            LabeledContent("I/O") {
                Text(config.ioType.displayName)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Identity

    private var identitySection: some View {
        Section("Identity") {
            HStack {
                Text("Unique ID")
                Spacer()
                TextField("Unique ID", text: Binding(
                    get: { String(format: "%08X", config.uniqueId) },
                    set: { newValue in
                        if let val = UInt32(newValue.prefix(8), radix: 16) {
                            config.uniqueId = val
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
                .multilineTextAlignment(.trailing)
                .font(.system(.body, design: .monospaced))
            }
            .mutabilityGated(ARCSettingUniqueID, emulatorState: emulatorState)
        }
    }
}

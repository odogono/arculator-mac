//
//  PeripheralsSettingsView.swift
//  Arculator
//
//  4 podule slots with type-filtered dropdown and Configure button,
//  plus joystick interface picker. Podule enumeration at runtime via
//  HardwareEnumeration; unique-flag constraint enforced on selection.
//

import SwiftUI

struct PeripheralsSettingsView: View {
    @ObservedObject var config: MachineConfigModel
    @ObservedObject var emulatorState: EmulatorState

    private var isA3010: Bool {
        MachinePresets.isA3010(preset: config.presetIndex)
    }

    var body: some View {
        Form {
            podulesSection
            joystickSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.visible)
    }

    // MARK: - Podules

    private var podulesSection: some View {
        Section("Expansion Slots") {
            ForEach(0..<4, id: \.self) { slot in
                poduleRow(slot: slot)
            }
        }
        .mutabilityGated(ARCSettingPodules, emulatorState: emulatorState)
    }

    private func poduleRow(slot: Int) -> some View {
        let slotType = MachinePresetBridge.poduleType(forPreset: config.presetIndex, slot: Int32(slot))
        let available = HardwareEnumeration.availablePodules(forSlotType: slotType)
        let label = "Slot \(slot) (\(HardwareEnumeration.slotTypeLabel(slotType)))"

        return VStack(alignment: .leading, spacing: 4) {
            if slotType == HardwareEnumeration.slotNone {
                LabeledContent(label) {
                    Text("Not available")
                        .foregroundStyle(.tertiary)
                }
            } else {
                Picker(label, selection: poduleBinding(slot: slot, available: available)) {
                    Text("None").tag("")
                    ForEach(available) { podule in
                        Text(podule.name).tag(podule.shortName)
                    }
                }

                if !config.podules[slot].isEmpty {
                    let hasConfig = HardwareEnumeration.poduleHasConfig(config.podules[slot])
                    Button("Configure...") {
                        ConfigEditorBridge.showPoduleConfig(
                            forShortName: config.podules[slot],
                            running: emulatorState.isActive,
                            slot: Int32(slot)
                        )
                    }
                    .controlSize(.small)
                    .disabled(!hasConfig)
                }
            }
        }
    }

    /// Binding that enforces the UNIQUE constraint: selecting a unique podule
    /// clears it from all other slots.
    private func poduleBinding(slot: Int, available: [PoduleInfo]) -> Binding<String> {
        Binding(
            get: { config.podules[slot] },
            set: { newValue in
                config.podules[slot] = newValue

                // Enforce unique constraint
                if !newValue.isEmpty,
                   let info = available.first(where: { $0.shortName == newValue }),
                   info.isUnique {
                    for other in 0..<4 where other != slot {
                        if config.podules[other] == newValue {
                            config.podules[other] = ""
                        }
                    }
                }
            }
        )
    }

    // MARK: - Joystick

    private var joystickSection: some View {
        Section("Joystick") {
            let interfaces = HardwareEnumeration.availableJoystickInterfaces(isA3010: isA3010)
            Picker("Interface", selection: Binding(
                get: { config.joystickInterface },
                set: { newValue in
                    config.joystickInterface = newValue
                    config.markResetIfNeeded(for: ARCSettingJoystickInterface)
                }
            )) {
                ForEach(interfaces) { iface in
                    Text(iface.name).tag(iface.configName)
                }
            }
            .mutabilityGated(ARCSettingJoystickInterface, emulatorState: emulatorState)

            if config.joystickInterface != "none" {
                let typeIdx = ConfigEditorBridge.joystickTypeIndex(forConfigName: config.joystickInterface)
                HStack(spacing: 12) {
                    Button("Configure Joy 1...") {
                        ConfigEditorBridge.showJoystickConfig(forPlayer: 0, type: typeIdx)
                    }
                    Button("Configure Joy 2...") {
                        ConfigEditorBridge.showJoystickConfig(forPlayer: 1, type: typeIdx)
                    }
                }
                .controlSize(.small)
            }
        }
    }
}

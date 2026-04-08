//
//  RunningControlsView.swift
//  Arculator
//
//  Sidebar content shown when emulation is active: config name,
//  status indicator with speed, and floppy disc slot controls.
//

import SwiftUI

struct RunningControlsView: View {

    @ObservedObject var configModel: MachineConfigModel
    @ObservedObject var emulatorState: EmulatorState
    var onOpenAppSettings: () -> Void = {}

    private var visibleDriveIndices: [Int] {
        let driveCount = (configModel.ioType == .new_) ? 2 : 4
        return Array(emulatorState.discNames.indices.prefix(driveCount))
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {

                // Active config name
                Text(emulatorState.activeConfigName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityIdentifier("activeConfigName")

                // Status row
                HStack(spacing: 6) {
                    Circle()
                        .fill(emulatorState.isRunning ? .green : .orange)
                        .frame(width: 8, height: 8)

                    Text(emulatorState.isRunning ? "Running" : "Paused")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("emulatorStatus")

                    Spacer()

                    Text("\(emulatorState.speedPercent)%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("emulatorSpeed")
                }

                Divider()

                // Floppy drives
                Text("Floppy Drives")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                ForEach(visibleDriveIndices, id: \.self) { index in
                    DiscSlotView(
                        driveIndex: index,
                        discName: emulatorState.discNames[index]
                    )
                }

                Spacer()
            }
            .padding()

            Divider()
            bottomBar
        }
        .accessibilityIdentifier("runningControls")
    }

    private var bottomBar: some View {
        HStack {
            Button {
                onOpenAppSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
            .accessibilityIdentifier("runningControlsAppSettingsButton")

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

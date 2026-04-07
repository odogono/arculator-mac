//
//  RunningControlsView.swift
//  Arculator
//
//  Sidebar content shown when emulation is active: config name,
//  status indicator with speed, and floppy disc slot controls.
//

import SwiftUI

struct RunningControlsView: View {

    @ObservedObject var emulatorState: EmulatorState

    var body: some View {
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

            ForEach(emulatorState.discNames.indices, id: \.self) { index in
                DiscSlotView(
                    driveIndex: index,
                    discName: emulatorState.discNames[index]
                )
            }

            Spacer()
        }
        .padding()
        .accessibilityIdentifier("runningControls")
    }
}

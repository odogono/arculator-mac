//
//  MutabilityGating.swift
//  Arculator
//
//  Reusable SwiftUI view modifier for gating settings based on the
//  mutability matrix and current emulator session state. Also provides
//  the "pending reset" banner view.
//

import SwiftUI

// MARK: - Mutability Gating Modifier

/// Disables a view and shows a hint when the setting cannot be changed
/// in the current emulator state.
struct MutabilityGatedModifier: ViewModifier {
    let settingKey: String
    @ObservedObject var emulatorState: EmulatorState

    private var mutability: ARCSettingMutability {
        MachineConfigModel.mutability(for: settingKey)
    }

    private var isDisabled: Bool {
        guard emulatorState.isActive else { return false }
        return mutability == .stop
    }

    private var hint: String? {
        guard isDisabled else { return nil }
        return "Stop emulation to change"
    }

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            content
                .disabled(isDisabled)
            if let hint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("mutabilityHint_\(settingKey)")
            }
        }
    }
}

extension View {
    func mutabilityGated(_ settingKey: String, emulatorState: EmulatorState) -> some View {
        modifier(MutabilityGatedModifier(settingKey: settingKey, emulatorState: emulatorState))
    }
}

// MARK: - Pending Reset Banner

/// Shows an informational banner when settings have been changed that
/// require a reset to take effect.
struct PendingResetBanner: View {
    @Binding var pendingReset: Bool
    var onApplyAndReset: () -> Void

    var body: some View {
        if pendingReset {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Settings changed. Reset required to take effect.")
                    .font(.callout)
                Spacer()
                Button("Apply and Reset") {
                    onApplyAndReset()
                    pendingReset = false
                }
                .controlSize(.small)
                .accessibilityIdentifier("applyAndResetButton")
            }
            .padding(8)
            .background(.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityIdentifier("pendingResetBanner")
        }
    }
}

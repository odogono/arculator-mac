//
//  ConfigEditorView.swift
//  Arculator
//
//  Top-level config editor with a two-column System Settings-style layout:
//  category list on the left, settings form on the right.
//

import SwiftUI

// MARK: - Category Enum

enum ConfigCategory: String, CaseIterable, Identifiable {
    case general = "General"
    case storage = "Storage"
    case peripherals = "Peripherals"
    case display = "Display"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general:     return "cpu"
        case .storage:     return "externaldrive"
        case .peripherals: return "cable.connector"
        case .display:     return "display"
        }
    }
}

// MARK: - Config Editor View

struct ConfigEditorView: View {
    @ObservedObject var config: MachineConfigModel
    @ObservedObject var emulatorState: EmulatorState
    @State private var selectedCategory: ConfigCategory = .general

    var body: some View {
        NavigationSplitView {
            List(ConfigCategory.allCases, selection: $selectedCategory) { category in
                Label(category.rawValue, systemImage: category.icon)
            }
            .navigationSplitViewColumnWidth(min: 140, ideal: 160, max: 200)
        } detail: {
            VStack(spacing: 0) {
                PendingResetBanner(pendingReset: $config.pendingReset) {
                    config.applyAndReset()
                }
                .padding(.horizontal)
                .padding(.top, config.pendingReset ? 8 : 0)

                detailView
            }
        }
        .navigationSplitViewStyle(.balanced)
        .accessibilityIdentifier("configEditor")
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedCategory {
        case .general:
            GeneralSettingsView(config: config, emulatorState: emulatorState)
        case .storage:
            StorageSettingsView(config: config, emulatorState: emulatorState)
        case .peripherals:
            PeripheralsSettingsView(config: config, emulatorState: emulatorState)
        case .display:
            DisplaySettingsView(config: config, emulatorState: emulatorState)
        }
    }
}

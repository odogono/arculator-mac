//
//  SidebarView.swift
//  Arculator
//
//  Top-level sidebar view that switches between idle content
//  (config list) and running content (active controls) based
//  on emulation state.
//

import SwiftUI

struct SidebarView: View {

    @ObservedObject var configList: ConfigListModel
    @ObservedObject var emulatorState: EmulatorState

    var body: some View {
        Group {
            if emulatorState.isIdle {
                ConfigListView(configList: configList)
            } else {
                RunningControlsView(emulatorState: emulatorState)
            }
        }
        // Note: no accessibilityIdentifier here — child views
        // (ConfigListView, RunningControlsView) set their own identifiers
        // and a Group identifier would override them in the accessibility tree.
    }
}

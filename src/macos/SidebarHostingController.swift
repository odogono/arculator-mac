//
//  SidebarHostingController.swift
//  Arculator
//
//  Hosts the sidebar SwiftUI view, switching between config list
//  (idle) and running controls (active) based on emulation state.
//

import Cocoa
import SwiftUI

class SidebarHostingController: NSHostingController<SidebarView> {

    init(configList: ConfigListModel) {
        let rootView = SidebarView(
            configList: configList,
            emulatorState: EmulatorState.shared
        )
        super.init(rootView: rootView)
    }

    @MainActor @preconcurrency required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

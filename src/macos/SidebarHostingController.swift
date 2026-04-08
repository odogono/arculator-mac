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

    init(configList: ConfigListModel,
         configModel: MachineConfigModel,
         onOpenAppSettings: @escaping () -> Void) {
        let rootView = SidebarView(
            configList: configList,
            configModel: configModel,
            emulatorState: EmulatorState.shared,
            onOpenAppSettings: onOpenAppSettings
        )
        super.init(rootView: rootView)
    }

    @MainActor @preconcurrency required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

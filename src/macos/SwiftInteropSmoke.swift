//
//  SwiftInteropSmoke.swift
//  Arculator
//
//  Minimal Swift file to verify Swift compilation and bridging header interop.
//

import Foundation

/// Smoke test: verifies Swift can access C and ObjC symbols through the bridging header.
enum SwiftInteropSmoke {

    static func verifyBridgingHeader() -> Bool {
        let name = config_get_romset_name(0)
        return name != nil
    }

    static func verifyEmulatorBridge() -> Bool {
        let active = EmulatorBridge.isSessionActive()
        return !active
    }

    // Phase 2: verify config and preset bridge types accessible from Swift
    static func verifyConfigBridge() -> Bool {
        let names = ConfigBridge.listConfigNames()
        _ = names.count
        return true
    }

    static func verifyPresetBridge() -> Bool {
        let count = MachinePresetBridge.presetCount()
        if count > 0 {
            _ = MachinePresetBridge.presetName(at: 0)
        }
        return count > 0
    }

    static func verifySessionState() -> Bool {
        let state = EmulatorBridge.sessionState()
        return state == .idle
    }

    static func verifyMachineConfig() -> Bool {
        let cfg = ARCMachineConfig.fromGlobals()
        _ = cfg.cpu
        return true
    }

    // Phase 3: verify data model layer types

    static func verifyMachinePresets() -> Bool {
        let all = MachinePresets.all
        guard !all.isEmpty else { return false }
        let cpus = MachinePresets.allowedCPUs(forPreset: 0)
        return !cpus.isEmpty
    }

    static func verifyMachineConfigModel() -> Bool {
        let model = MachineConfigModel()
        model.loadFromGlobals()
        return model.allowedCPUs.contains(model.cpu)
    }

    static func verifyConfigListModel() -> Bool {
        let model = ConfigListModel()
        _ = model.configNames
        return true
    }

    static func verifyEmulatorState() -> Bool {
        let state = EmulatorState()
        defer { state.stopPolling() }
        return state.isIdle
    }

    // Phase 4: verify ArcMetalView accessible from Swift and EmulatorMetalView exists

    static func verifyArcMetalViewFromSwift() -> Bool {
        let view = ArcMetalView(frame: .zero, device: nil)
        return view.acceptsFirstResponder
    }

    static func verifyEmulatorMetalView() -> Bool {
        _ = EmulatorMetalView.self
        return true
    }

    // Phase 5: verify window shell types

    static func verifyMainSplitViewController() -> Bool {
        let vc = MainSplitViewController()
        _ = vc.view // trigger viewDidLoad
        return vc.splitViewItems.count == 2 && vc.contentController != nil
    }

    static func verifyContentHostingController() -> Bool {
        let vc = ContentHostingController(configList: ConfigListModel())
        _ = vc.view // trigger loadView + viewDidLoad
        return true
    }

    static func verifySidebarHostingController() -> Bool {
        let vc = SidebarHostingController(
            configList: ConfigListModel(),
            configModel: MachineConfigModel(),
            onOpenAppSettings: {}
        )
        _ = vc.view
        return true
    }

    static func verifyToolbarManager() -> Bool {
        let mgr = ToolbarManager()
        let tb = mgr.createToolbar()
        return tb.identifier == ToolbarManager.toolbarIdentifier
    }

    static func verifyNewWindowBridge() -> Bool {
        guard let window = NewWindowBridge.createMainWindow(with: nil) else { return false }
        let ok = window.contentViewController is MainSplitViewController
        window.close()
        return ok
    }

    // Phase 6: verify config editor types

    static func verifyHardwareEnumeration() -> Bool {
        // Podule enumeration for a 16-bit slot
        _ = HardwareEnumeration.availablePodules(forSlotType: HardwareEnumeration.slot16Bit)
        // Joystick enumeration
        _ = HardwareEnumeration.availableJoystickInterfaces(isA3010: false)
        // Slot type label
        let label = HardwareEnumeration.slotTypeLabel(HardwareEnumeration.slot16Bit)
        return label == "Podule"
    }

    static func verifyConfigEditorBridge() -> Bool {
        // Verify the bridge class is accessible
        let typeIdx = ConfigEditorBridge.joystickTypeIndex(forConfigName: "none")
        return typeIdx >= 0
    }

    static func verifyConfigEditorView() -> Bool {
        _ = ConfigEditorView.self
        _ = ConfigCategory.allCases
        return ConfigCategory.allCases.count == 4
    }

    static func verifyMachineConfigModelAutoSave() -> Bool {
        let model = MachineConfigModel()
        model.enableAutoSave()
        model.disableAutoSave()
        return true
    }

    // Phase 7: verify sidebar view types

    static func verifySidebarView() -> Bool {
        _ = SidebarView.self
        _ = ConfigListView.self
        _ = RunningControlsView.self
        _ = DiscSlotView.self
        return true
    }

    static func verifyConfigListViewCreation() -> Bool {
        let configList = ConfigListModel()
        _ = ConfigListView(configList: configList)
        return true
    }

    static func verifyRunningControlsViewCreation() -> Bool {
        _ = RunningControlsView(configModel: MachineConfigModel(), emulatorState: EmulatorState.shared)
        return true
    }

    static func verifyDiscSlotViewCreation() -> Bool {
        _ = DiscSlotView(driveIndex: 0, discName: "")
        _ = DiscSlotView(driveIndex: 1, discName: "/path/to/test.adf")
        return true
    }
}

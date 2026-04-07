//
//  MachineConfigModel.swift
//  Arculator
//
//  ObservableObject holding all editable config fields as @Published
//  properties. Serves as the edit buffer between C globals and SwiftUI.
//  Methods call ConfigBridge / ARCMachineConfig — no logic duplication.
//

import Foundation
import Combine

class MachineConfigModel: ObservableObject {

    // MARK: - Published Properties

    @Published var presetIndex: Int = 0
    @Published var cpu: CPUType = .arm2
    @Published var memory: MemorySize = .mem1M
    @Published var memc: MEMCType = .memc1
    @Published var fpu: FPUType = .none
    @Published var rom: ROMSet = .riscos311
    @Published var monitor: MonitorType = .multisync
    @Published var ioType: IOType = .old
    @Published var uniqueId: UInt32 = 0

    @Published var podules: [String] = ["", "", "", ""]
    @Published var joystickInterface: String = "none"

    @Published var hdPath0: String = ""
    @Published var hdPath1: String = ""
    @Published var hdCyl0: Int32 = 0
    @Published var hdHpc0: Int32 = 0
    @Published var hdSpt0: Int32 = 0
    @Published var hdCyl1: Int32 = 0
    @Published var hdHpc1: Int32 = 0
    @Published var hdSpt1: Int32 = 0

    @Published var fifthColumnPath: String = ""
    @Published var supportRomEnabled: Bool = true

    // MARK: - Computed Properties (derived from current state)

    var allowedCPUs: [CPUType] {
        MachinePresets.allowedCPUs(forPreset: presetIndex)
    }

    var allowedMemory: [MemorySize] {
        MachinePresets.allowedMemory(forPreset: presetIndex)
    }

    var allowedMEMC: [MEMCType] {
        MachinePresets.allowedMEMC(forPreset: presetIndex)
    }

    var allowedROMs: [ROMSet] {
        MachinePresets.allowedROMs(forPreset: presetIndex)
    }

    var allowedMonitors: [MonitorType] {
        MachinePresets.allowedMonitors(forPreset: presetIndex)
    }

    var isFPPCAvailable: Bool {
        MachinePresets.isFPPCAvailable(cpu: cpu.rawValue, memc: memc.rawValue)
    }

    var isFPA10Available: Bool {
        MachinePresets.isFPA10Available(cpu: cpu.rawValue)
    }

    var isSupportROMAvailable: Bool {
        MachinePresets.isSupportROMAvailable(rom: rom.rawValue)
    }

    var has5thColumn: Bool {
        MachinePresets.has5thColumn(preset: presetIndex)
    }

    /// Whether a reset-requiring setting has been changed while a session is active.
    @Published var pendingReset: Bool = false

    // MARK: - Private State

    private var suppressCascade = false
    private var suppressAutoSave = false
    private var autoSaveCancellable: AnyCancellable?

    // MARK: - Auto-Save

    /// Enable auto-save: debounces changes and calls applyToGlobals() after 500ms.
    func enableAutoSave() {
        autoSaveCancellable = objectWillChange
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !self.suppressAutoSave else { return }
                self.applyToGlobals()
            }
    }

    /// Disable auto-save pipeline.
    func disableAutoSave() {
        autoSaveCancellable = nil
    }

    // MARK: - Load Methods

    func loadFromGlobals() {
        suppressCascade = true
        suppressAutoSave = true
        defer {
            suppressCascade = false
            suppressAutoSave = false
        }
        apply(ARCMachineConfig.fromGlobals())
        pendingReset = false
    }

    func loadFromPreset(_ index: Int) {
        suppressCascade = true
        suppressAutoSave = true
        defer {
            suppressCascade = false
            suppressAutoSave = false
        }
        apply(ARCMachineConfig(fromPresetIndex: Int32(index)))
        pendingReset = false
    }

    // MARK: - Mutation Methods (with cascade)

    func changePreset(to index: Int) {
        loadFromPreset(index)
    }

    func changeCPU(to newCPU: CPUType) {
        cpu = newCPU
        cascadeAfterCPUChange()
    }

    // MARK: - Apply to C Globals

    func applyToGlobals() {
        let cfg = buildBridgeConfig()
        cfg.applyToGlobals()
    }

    func applyToGlobalsAndResetIfRunning() {
        let cfg = buildBridgeConfig()
        cfg.applyToGlobalsAndResetIfRunning()
    }

    // MARK: - Reset Tracking

    /// Call after changing a setting to mark pending reset if needed.
    func markResetIfNeeded(for settingKey: String) {
        guard EmulatorState.shared.isActive else { return }
        let mut = ConfigBridge.mutability(forSetting: settingKey)
        if mut == .reset {
            pendingReset = true
        }
    }

    /// Apply settings and reset the emulator, clearing the pending flag.
    func applyAndReset() {
        applyToGlobalsAndResetIfRunning()
        pendingReset = false
    }

    // MARK: - Mutability Query

    static func mutability(for settingKey: String) -> ARCSettingMutability {
        ConfigBridge.mutability(forSetting: settingKey)
    }

    // MARK: - Private

    private func apply(_ cfg: ARCMachineConfig) {
        presetIndex = Int(cfg.preset)
        cpu = CPUType(rawValue: cfg.cpu) ?? .arm2
        memory = MemorySize(rawValue: cfg.mem) ?? .mem1M
        memc = MEMCType(rawValue: cfg.memc) ?? .memc1
        fpu = FPUType(rawValue: cfg.fpu) ?? .none
        rom = ROMSet(rawValue: cfg.rom) ?? .riscos311
        monitor = MonitorType(rawValue: cfg.monitor) ?? .multisync
        ioType = IOType(rawValue: cfg.io) ?? .old
        uniqueId = cfg.uniqueId

        podules = [cfg.podule0, cfg.podule1, cfg.podule2, cfg.podule3]
        joystickInterface = cfg.joystickInterface

        hdPath0 = cfg.hdPath0
        hdPath1 = cfg.hdPath1
        hdCyl0 = cfg.hdCyl0; hdHpc0 = cfg.hdHpc0; hdSpt0 = cfg.hdSpt0
        hdCyl1 = cfg.hdCyl1; hdHpc1 = cfg.hdHpc1; hdSpt1 = cfg.hdSpt1

        fifthColumnPath = cfg.fifthColumnPath
        supportRomEnabled = cfg.supportRomEnabled
    }

    private func cascadeAfterCPUChange() {
        guard !suppressCascade else { return }
        fpu = MachinePresets.adjustFPU(afterCPUChange: fpu.rawValue, newCPU: cpu.rawValue)
        memc = MachinePresets.adjustMEMC(afterCPUChange: memc.rawValue, newCPU: cpu.rawValue)
    }

    private func buildBridgeConfig() -> ARCMachineConfig {
        let cfg = ARCMachineConfig()
        cfg.preset = Int32(presetIndex)
        cfg.cpu = cpu.rawValue
        cfg.mem = memory.rawValue
        cfg.memc = memc.rawValue
        cfg.fpu = fpu.rawValue
        cfg.io = ioType.rawValue
        cfg.rom = rom.rawValue
        cfg.monitor = monitor.rawValue
        cfg.uniqueId = uniqueId

        cfg.podule0 = podules[0]
        cfg.podule1 = podules[1]
        cfg.podule2 = podules[2]
        cfg.podule3 = podules[3]
        cfg.joystickInterface = joystickInterface

        cfg.hdPath0 = hdPath0
        cfg.hdPath1 = hdPath1
        cfg.hdCyl0 = hdCyl0; cfg.hdHpc0 = hdHpc0; cfg.hdSpt0 = hdSpt0
        cfg.hdCyl1 = hdCyl1; cfg.hdHpc1 = hdHpc1; cfg.hdSpt1 = hdSpt1

        cfg.fifthColumnPath = fifthColumnPath
        cfg.supportRomEnabled = supportRomEnabled
        return cfg
    }
}

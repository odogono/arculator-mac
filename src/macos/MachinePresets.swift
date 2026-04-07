//
//  MachinePresets.swift
//  Arculator
//
//  Swift-native enums for hardware options and a thin query wrapper
//  over MachinePresetBridge. Not a second source of truth — every
//  query delegates to the ObjC bridge at call time.
//

import Foundation

// MARK: - Hardware Option Enums

enum CPUType: Int32, CaseIterable, Identifiable {
    case arm2 = 0
    case arm250
    case arm3_20
    case arm3_25
    case arm3_26
    case arm3_30
    case arm3_33
    case arm3_35
    case arm3_24
    case arm3_36
    case arm3_40

    var id: Int32 { rawValue }

    var displayName: String {
        switch self {
        case .arm2:    return "ARM2"
        case .arm250:  return "ARM250"
        case .arm3_20: return "ARM3 @ 20 MHz"
        case .arm3_25: return "ARM3 @ 25 MHz"
        case .arm3_26: return "ARM3 @ 26 MHz"
        case .arm3_30: return "ARM3 @ 30 MHz"
        case .arm3_33: return "ARM3 @ 33 MHz"
        case .arm3_35: return "ARM3 @ 35 MHz"
        case .arm3_24: return "ARM3 @ 24 MHz"
        case .arm3_36: return "ARM3 @ 36 MHz"
        case .arm3_40: return "ARM3 @ 40 MHz"
        }
    }
}

enum MEMCType: Int32, CaseIterable, Identifiable {
    case memc1 = 0
    case memc1a_8
    case memc1a_12
    case memc1a_16
    case memc1a_20
    case memc1a_24

    var id: Int32 { rawValue }

    var displayName: String {
        switch self {
        case .memc1:     return "MEMC1"
        case .memc1a_8:  return "MEMC1a (8 MHz)"
        case .memc1a_12: return "MEMC1a (12 MHz)"
        case .memc1a_16: return "MEMC1a (16 MHz - overclocked)"
        case .memc1a_20: return "MEMC1a (20 MHz - overclocked)"
        case .memc1a_24: return "MEMC1a (24 MHz - overclocked)"
        }
    }
}

enum MemorySize: Int32, CaseIterable, Identifiable {
    case mem512K = 0
    case mem1M
    case mem2M
    case mem4M
    case mem8M
    case mem12M
    case mem16M

    var id: Int32 { rawValue }

    var displayName: String {
        switch self {
        case .mem512K: return "512 kB"
        case .mem1M:   return "1 MB"
        case .mem2M:   return "2 MB"
        case .mem4M:   return "4 MB"
        case .mem8M:   return "8 MB"
        case .mem12M:  return "12 MB"
        case .mem16M:  return "16 MB"
        }
    }
}

enum FPUType: Int32, CaseIterable, Identifiable {
    case none = 0
    case fppc
    case fpa10

    var id: Int32 { rawValue }

    var displayName: String {
        switch self {
        case .none:  return "None"
        case .fppc:  return "FPPC"
        case .fpa10: return "FPA10"
        }
    }
}

enum ROMSet: Int32, CaseIterable, Identifiable {
    case arthur030 = 0
    case arthur120
    case riscos200
    case riscos201
    case riscos300
    case riscos310
    case riscos311
    case riscos319
    case arthur120_a500
    case riscos200_a500
    case riscos310_a500

    var id: Int32 { rawValue }

    var displayName: String {
        switch self {
        case .arthur030:      return "Arthur 0.30"
        case .arthur120:      return "Arthur 1.20"
        case .riscos200:      return "RISC OS 2.00"
        case .riscos201:      return "RISC OS 2.01"
        case .riscos300:      return "RISC OS 3.00"
        case .riscos310:      return "RISC OS 3.10"
        case .riscos311:      return "RISC OS 3.11"
        case .riscos319:      return "RISC OS 3.19"
        case .arthur120_a500: return "Arthur 1.20 (A500)"
        case .riscos200_a500: return "RISC OS 2.00 (A500)"
        case .riscos310_a500: return "RISC OS 3.10 (A500)"
        }
    }
}

enum MonitorType: Int32, CaseIterable, Identifiable {
    case standard = 0
    case multisync
    case vga
    case mono
    case lcd

    var id: Int32 { rawValue }

    var displayName: String {
        switch self {
        case .standard:  return "Standard"
        case .multisync: return "Multisync"
        case .vga:       return "VGA"
        case .mono:      return "High res mono"
        case .lcd:       return "LCD"
        }
    }
}

enum IOType: Int32, CaseIterable, Identifiable {
    case old = 0
    case oldST506
    case new_

    var id: Int32 { rawValue }

    var displayName: String {
        switch self {
        case .old:      return "Old IO"
        case .oldST506: return "Old IO + ST-506"
        case .new_:     return "New IO"
        }
    }
}

// MARK: - Preset Struct

struct MachinePreset: Identifiable {
    let index: Int
    let name: String
    let configName: String
    let description: String

    var id: Int { index }
}

// MARK: - MachinePresets Query Namespace

enum MachinePresets {

    static var all: [MachinePreset] {
        let count = MachinePresetBridge.presetCount()
        return (0..<count).map { i in
            MachinePreset(
                index: i,
                name: MachinePresetBridge.presetName(at: i),
                configName: MachinePresetBridge.presetConfigName(at: i),
                description: MachinePresetBridge.presetDescription(at: i)
            )
        }
    }

    // MARK: Allowed options for a preset (bitmask filtering)

    static func allowedCPUs(forPreset index: Int) -> [CPUType] {
        let mask = MachinePresetBridge.allowedCpuMask(forPreset: index)
        return CPUType.allCases.filter { mask & (1 << UInt32($0.rawValue)) != 0 }
    }

    static func allowedMemory(forPreset index: Int) -> [MemorySize] {
        let mask = MachinePresetBridge.allowedMemMask(forPreset: index)
        return MemorySize.allCases.filter { mask & (1 << UInt32($0.rawValue)) != 0 }
    }

    static func allowedMEMC(forPreset index: Int) -> [MEMCType] {
        let mask = MachinePresetBridge.allowedMemcMask(forPreset: index)
        return MEMCType.allCases.filter { mask & (1 << UInt32($0.rawValue)) != 0 }
    }

    static func allowedROMs(forPreset index: Int) -> [ROMSet] {
        let presetMask = MachinePresetBridge.allowedRomsetMask(forPreset: index)
        let availableMask = UInt32(bitPattern: romset_available_mask)
        let mask = presetMask & availableMask
        return ROMSet.allCases.filter { mask & (1 << UInt32($0.rawValue)) != 0 }
    }

    static func allowedMonitors(forPreset index: Int) -> [MonitorType] {
        let mask = MachinePresetBridge.allowedMonitorMask(forPreset: index)
        return MonitorType.allCases.filter { mask & (1 << UInt32($0.rawValue)) != 0 }
    }

    // MARK: Preset defaults

    static func defaultCPU(forPreset index: Int) -> CPUType {
        CPUType(rawValue: MachinePresetBridge.defaultCpu(forPreset: index)) ?? .arm2
    }

    static func defaultMemory(forPreset index: Int) -> MemorySize {
        MemorySize(rawValue: MachinePresetBridge.defaultMem(forPreset: index)) ?? .mem1M
    }

    static func defaultMEMC(forPreset index: Int) -> MEMCType {
        MEMCType(rawValue: MachinePresetBridge.defaultMemc(forPreset: index)) ?? .memc1
    }

    static func ioType(forPreset index: Int) -> IOType {
        IOType(rawValue: MachinePresetBridge.ioType(forPreset: index)) ?? .old
    }

    // MARK: Validation

    static func isFPPCAvailable(cpu: Int32, memc: Int32) -> Bool {
        MachinePresetBridge.fppcAvailable(forCpu: cpu, memc: memc)
    }

    static func isFPA10Available(cpu: Int32) -> Bool {
        MachinePresetBridge.fpa10Available(forCpu: cpu)
    }

    static func isSupportROMAvailable(rom: Int32) -> Bool {
        MachinePresetBridge.supportRomAvailable(forRom: rom)
    }

    static func isA3010(preset index: Int) -> Bool {
        MachinePresetBridge.isA3010Preset(index)
    }

    static func has5thColumn(preset index: Int) -> Bool {
        MachinePresetBridge.presetHas5thColumn(index)
    }

    // MARK: Cascade logic

    static func adjustFPU(afterCPUChange currentFPU: Int32, newCPU: Int32) -> FPUType {
        let raw = MachinePresetBridge.adjustFpu(afterCpuChange: currentFPU, newCpu: newCPU)
        return FPUType(rawValue: raw) ?? .none
    }

    static func adjustMEMC(afterCPUChange currentMEMC: Int32, newCPU: Int32) -> MEMCType {
        let raw = MachinePresetBridge.adjustMemc(afterCpuChange: currentMEMC, newCpu: newCPU)
        return MEMCType(rawValue: raw) ?? .memc1
    }
}

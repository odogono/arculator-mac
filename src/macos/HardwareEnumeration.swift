//
//  HardwareEnumeration.swift
//  Arculator
//
//  Runtime enumeration of available podules and joystick interfaces
//  by iterating the C registration arrays via bridged functions.
//

import Foundation

// MARK: - Podule Info

struct PoduleInfo: Identifiable, Hashable {
    let index: Int
    let name: String
    let shortName: String
    let flags: UInt32

    var id: Int { index }
    var is8Bit: Bool { flags & UInt32(PODULE_FLAGS_8BIT) != 0 }
    var isNet: Bool { flags & UInt32(PODULE_FLAGS_NET) != 0 }
    var isUnique: Bool { flags & UInt32(PODULE_FLAGS_UNIQUE) != 0 }
}

// MARK: - Joystick Interface Info

struct JoystickInfo: Identifiable, Hashable {
    let index: Int
    let name: String
    let configName: String

    var id: Int { index }
}

// MARK: - Enumeration

enum HardwareEnumeration {

    /// Slot type constants matching MachinePresetData.h
    static let slotNone: Int32 = 0    // PODULE_NONE
    static let slot16Bit: Int32 = 1   // PODULE_16BIT
    static let slot8Bit: Int32 = 2    // PODULE_8BIT
    static let slotNet: Int32 = 3     // PODULE_NET

    /// Returns all podules valid for a given slot type.
    /// Slot type comes from `MachinePresetBridge.poduleType(forPreset:slot:)`.
    static func availablePodules(forSlotType slotType: Int32) -> [PoduleInfo] {
        guard slotType != slotNone else { return [] }

        var result: [PoduleInfo] = []
        var c: Int32 = 0
        while let namePtr = podule_get_name(c) {
            let info = PoduleInfo(
                index: Int(c),
                name: String(cString: namePtr),
                shortName: String(cString: podule_get_short_name(c)),
                flags: podule_get_flags(c)
            )

            let matches: Bool
            switch slotType {
            case slot16Bit:
                matches = !info.is8Bit && !info.isNet
            case slot8Bit:
                matches = info.is8Bit
            case slotNet:
                matches = info.isNet
            default:
                matches = false
            }

            if matches {
                result.append(info)
            }
            c += 1
        }
        return result
    }

    /// Returns all joystick interfaces, filtering A3010-only interface for non-A3010 presets.
    static func availableJoystickInterfaces(isA3010: Bool) -> [JoystickInfo] {
        var result: [JoystickInfo] = []
        var c: Int32 = 0
        while let namePtr = joystick_get_name(c) {
            let configName = String(cString: joystick_get_config_name(c))
            if configName != "a3010" || isA3010 {
                result.append(JoystickInfo(index: Int(c), name: String(cString: namePtr), configName: configName))
            }
            c += 1
        }
        return result
    }

    /// Checks whether a podule (by short name) has a configuration dialog.
    static func poduleHasConfig(_ shortName: String) -> Bool {
        guard !shortName.isEmpty else { return false }
        guard let header = podule_find(shortName) else { return false }
        return header.pointee.config != nil
    }

    /// Returns the slot type label for a given slot type constant.
    static func slotTypeLabel(_ slotType: Int32) -> String {
        switch slotType {
        case slot16Bit: return "Podule"
        case slot8Bit:  return "Minipodule"
        case slotNet:   return "Network"
        default:        return "N/A"
        }
    }
}

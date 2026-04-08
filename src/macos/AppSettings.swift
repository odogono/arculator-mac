//
//  AppSettings.swift
//  Arculator
//
//  App-wide preferences persisted via UserDefaults.standard. The C
//  side reads the same values from CFPreferences (same backing plist),
//  so writes are visible across the Swift/C boundary without IPC.
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

// MARK: - Key Combo

struct KeyCombo: Equatable {
    /// Raw kVK_ virtual key code (no KEYCODE_MACOS bias).
    var keyCode: Int
    /// Subset of NSEvent.ModifierFlags limited to .command/.control/.option/.shift.
    var modifierFlags: NSEvent.ModifierFlags

    static let `default` = KeyCombo(keyCode: kVK_Delete, modifierFlags: .command)

    var displayString: String {
        var s = ""
        if modifierFlags.contains(.control) { s += "⌃" }
        if modifierFlags.contains(.option)  { s += "⌥" }
        if modifierFlags.contains(.shift)   { s += "⇧" }
        if modifierFlags.contains(.command) { s += "⌘" }
        s += KeyCombo.symbolForKeyCode(keyCode)
        return s
    }

    static func symbolForKeyCode(_ code: Int) -> String {
        switch code {
        case kVK_Delete:           return "⌫"
        case kVK_ForwardDelete:    return "⌦"
        case kVK_Return:           return "↩"
        case kVK_Escape:           return "⎋"
        case kVK_Tab:              return "⇥"
        case kVK_Space:            return "Space"
        case kVK_LeftArrow:        return "←"
        case kVK_RightArrow:       return "→"
        case kVK_UpArrow:          return "↑"
        case kVK_DownArrow:        return "↓"
        case kVK_F1:               return "F1"
        case kVK_F2:               return "F2"
        case kVK_F3:               return "F3"
        case kVK_F4:               return "F4"
        case kVK_F5:               return "F5"
        case kVK_F6:               return "F6"
        case kVK_F7:               return "F7"
        case kVK_F8:               return "F8"
        case kVK_F9:               return "F9"
        case kVK_F10:              return "F10"
        case kVK_F11:              return "F11"
        case kVK_F12:              return "F12"
        default:
            return printableCharacter(for: code) ?? "Key\(code)"
        }
    }

    private static func printableCharacter(for keyCode: Int) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutDataRaw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutDataRaw).takeUnretainedValue()
        let layoutPtr = CFDataGetBytePtr(layoutData)
        let keyboardLayout = unsafeBitCast(layoutPtr, to: UnsafePointer<UCKeyboardLayout>.self)

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var actualLength = 0
        let status = UCKeyTranslate(
            keyboardLayout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            chars.count,
            &actualLength,
            &chars
        )
        guard status == noErr, actualLength > 0 else { return nil }
        let str = String(utf16CodeUnits: chars, count: actualLength)
        return str.isEmpty ? nil : str.uppercased()
    }
}

// MARK: - App Settings

@MainActor
final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    private enum Key {
        static let supportPath              = "ArculatorSupportPath"
        static let releaseShortcutKeyCode   = "ArculatorReleaseShortcutKeyCode"
        static let releaseShortcutModFlags  = "ArculatorReleaseShortcutModFlags"
    }

    @Published var supportPath: String? {
        didSet {
            guard supportPath != oldValue else { return }
            UserDefaults.standard.set(supportPath, forKey: Key.supportPath)
            pendingRestart = true
        }
    }

    @Published var releaseShortcut: KeyCombo {
        didSet {
            guard releaseShortcut != oldValue else { return }
            UserDefaults.standard.set(releaseShortcut.keyCode,
                                      forKey: Key.releaseShortcutKeyCode)
            UserDefaults.standard.set(Int(releaseShortcut.modifierFlags.rawValue),
                                      forKey: Key.releaseShortcutModFlags)
        }
    }

    /// Set when supportPath has changed in this session — UI shows a
    /// "Restart Arculator to apply" notice.
    @Published var pendingRestart: Bool = false

    var defaultSupportPath: String {
        "\(NSHomeDirectory())/Library/Application Support/Arculator"
    }

    var effectiveSupportPath: String {
        let path = supportPath ?? defaultSupportPath
        return (path as NSString).expandingTildeInPath
    }

    private init() {
        let defaults = UserDefaults.standard
        self.supportPath = defaults.string(forKey: Key.supportPath)

        if defaults.object(forKey: Key.releaseShortcutKeyCode) != nil {
            let keyCode = defaults.integer(forKey: Key.releaseShortcutKeyCode)
            let rawFlags = defaults.integer(forKey: Key.releaseShortcutModFlags)
            self.releaseShortcut = KeyCombo(
                keyCode: keyCode,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(rawFlags))
            )
        } else {
            self.releaseShortcut = .default
        }
    }

    func chooseSupportPath(presenting window: NSWindow?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Choose User Data Folder"
        panel.message = "Arculator will store its configurations, ROMs, CMOS, and disc images in this folder on next launch."
        panel.prompt = "Choose"
        let current = supportPath ?? defaultSupportPath
        panel.directoryURL = URL(fileURLWithPath: current)

        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.supportPath = url.path
        }

        if let window {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(panel.runModal())
        }
    }

    func revealSupportPathInFinder() {
        let url = URL(fileURLWithPath: effectiveSupportPath)
        // If the directory doesn't exist yet (e.g. user changed path but
        // hasn't restarted), just reveal its parent.
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
        }
    }

    func resetSupportPathToDefault() {
        supportPath = nil
    }

    func resetReleaseShortcutToDefault() {
        releaseShortcut = .default
    }
}

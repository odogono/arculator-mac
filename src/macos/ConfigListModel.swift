//
//  ConfigListModel.swift
//  Arculator
//
//  ObservableObject managing the sorted list of saved machine
//  configurations. All file operations forward to ConfigBridge.
//

import Foundation

class ConfigListModel: NSObject, ObservableObject {

    @Published private(set) var configNames: [String] = []
    @Published var selectedConfigName: String?

    /// ObjC-callable setter for selectedConfigName (Published properties
    /// aren't directly visible to ObjC).
    @objc(selectConfigNamed:)
    func selectConfig(named name: String?) {
        selectedConfigName = name
    }

    override init() {
        super.init()
        refresh()
    }

    func refresh() {
        configNames = ConfigBridge.listConfigNames()
        if let selected = selectedConfigName, !configNames.contains(selected) {
            selectedConfigName = nil
        }
    }

    @discardableResult
    func create(name: String, presetIndex: Int) -> Bool {
        guard ConfigBridge.createConfig(name, withPresetIndex: Int32(presetIndex)) else {
            return false
        }
        refresh()
        selectedConfigName = name
        return true
    }

    @discardableResult
    func rename(oldName: String, to newName: String) -> Bool {
        guard ConfigBridge.renameConfig(oldName, to: newName) else {
            return false
        }
        refresh()
        if selectedConfigName == oldName {
            selectedConfigName = newName
        }
        return true
    }

    @discardableResult
    func duplicate(sourceName: String, to destName: String) -> Bool {
        guard ConfigBridge.copyConfig(sourceName, to: destName) else {
            return false
        }
        refresh()
        selectedConfigName = destName
        return true
    }

    @discardableResult
    func delete(name: String) -> Bool {
        guard ConfigBridge.deleteConfig(name) else {
            return false
        }
        if selectedConfigName == name {
            selectedConfigName = nil
        }
        refresh()
        return true
    }

    @discardableResult
    func loadConfig(named name: String) -> Bool {
        ConfigBridge.loadConfigNamed(name)
    }

    func configExists(_ name: String) -> Bool {
        ConfigBridge.configExists(name)
    }
}

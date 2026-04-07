//
//  ToolbarManager.swift
//  Arculator
//
//  NSToolbarDelegate configuring the main window toolbar with
//  emulation lifecycle controls, fullscreen, and sidebar toggle.
//

import Cocoa
import Combine

@objc class ToolbarManager: NSObject, NSToolbarDelegate, NSToolbarItemValidation {

    @objc static let toolbarIdentifier = NSToolbar.Identifier("ArculatorMainToolbar")

    @objc weak var splitViewController: MainSplitViewController?
    @objc var configListModel: ConfigListModel? {
        didSet { subscribeToSelection() }
    }

    private let emulatorState = EmulatorState.shared
    private var stateSubscription: AnyCancellable?
    private var selectionSubscription: AnyCancellable?
    private weak var toolbar: NSToolbar?

    private enum ItemID {
        static let sidebarToggle = NSToolbarItem.Identifier("sidebarToggle")
        static let run           = NSToolbarItem.Identifier("run")
        static let pause         = NSToolbarItem.Identifier("pause")
        static let stop          = NSToolbarItem.Identifier("stop")
        static let reset         = NSToolbarItem.Identifier("reset")
        static let fullscreen    = NSToolbarItem.Identifier("fullscreen")
    }

    override init() {
        super.init()
        stateSubscription = emulatorState.$sessionState
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let toolbar = self.toolbar else { return }
                for item in toolbar.items {
                    self.updateItemState(item)
                }
            }
    }

    @objc func createToolbar() -> NSToolbar {
        let tb = NSToolbar(identifier: Self.toolbarIdentifier)
        tb.delegate = self
        tb.displayMode = .iconOnly
        tb.allowsUserCustomization = false
        self.toolbar = tb
        return tb
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ItemID.sidebarToggle,
            .flexibleSpace,
            ItemID.run,
            ItemID.pause,
            ItemID.stop,
            .space,
            ItemID.reset,
            .flexibleSpace,
            ItemID.fullscreen
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.target = self

        switch itemIdentifier {
        case ItemID.sidebarToggle:
            item.label = "Sidebar"
            item.toolTip = "Toggle Sidebar"
            item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Toggle Sidebar")
            item.action = #selector(toggleSidebar)

        case ItemID.run:
            item.label = "Run"
            item.toolTip = "Run / Resume Emulation"
            item.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Run")
            item.action = #selector(runEmulation)

        case ItemID.pause:
            item.label = "Pause"
            item.toolTip = "Pause Emulation"
            item.image = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: "Pause")
            item.action = #selector(pauseEmulation)

        case ItemID.stop:
            item.label = "Stop"
            item.toolTip = "Stop Emulation"
            item.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "Stop")
            item.action = #selector(stopEmulation)

        case ItemID.reset:
            item.label = "Reset"
            item.toolTip = "Hard Reset"
            item.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: "Reset")
            item.action = #selector(resetEmulation)

        case ItemID.fullscreen:
            item.label = "Fullscreen"
            item.toolTip = "Toggle Fullscreen"
            item.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "Fullscreen")
            item.action = #selector(toggleFullscreen)

        default:
            return nil
        }

        updateItemState(item)
        return item
    }

    // MARK: - Item Validation

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        updateItemState(item)
        return item.isEnabled
    }

    private func updateItemState(_ item: NSToolbarItem) {
        let state = emulatorState.sessionState
        switch item.itemIdentifier {
        case ItemID.sidebarToggle, ItemID.fullscreen:
            item.isEnabled = true
        case ItemID.run:
            item.isEnabled = state == .paused
                || (state == .idle && configListModel?.selectedConfigName != nil)
        case ItemID.pause:
            item.isEnabled = state == .running
        case ItemID.stop:
            item.isEnabled = state != .idle
        case ItemID.reset:
            item.isEnabled = state != .idle
        default:
            break
        }
    }

    // MARK: - Actions

    @objc private func toggleSidebar() {
        splitViewController?.toggleSidebar()
    }

    @objc private func runEmulation() {
        if emulatorState.isPaused {
            EmulatorBridge.resumeEmulation()
        } else if emulatorState.isIdle,
                  let configName = configListModel?.selectedConfigName,
                  let splitVC = splitViewController {
            splitVC.contentController.installEmulatorView()
            if !EmulatorBridge.startEmulation(forConfig: configName) {
                // Config load failed — remove the Metal view we just installed
                splitVC.contentController.removeEmulatorView()
            }
        }
    }

    @objc private func pauseEmulation() {
        if emulatorState.isRunning {
            EmulatorBridge.pauseEmulation()
        }
    }

    @objc private func stopEmulation() {
        if emulatorState.isActive {
            EmulatorBridge.stopEmulation()
        }
    }

    @objc private func resetEmulation() {
        if emulatorState.isActive {
            EmulatorBridge.resetEmulation()
        }
    }

    @objc private func toggleFullscreen() {
        splitViewController?.view.window?.toggleFullScreen(nil)
    }

    private func subscribeToSelection() {
        selectionSubscription = configListModel?.$selectedConfigName
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let toolbar = self.toolbar else { return }
                for item in toolbar.items where item.itemIdentifier == ItemID.run {
                    self.updateItemState(item)
                }
            }
    }
}

//
//  MainSplitViewController.swift
//  Arculator
//
//  NSSplitViewController managing sidebar (config list / running controls)
//  and content (config editor / emulator Metal view) areas.
//  Owns ConfigListModel and MachineConfigModel, mediating sidebar
//  selection to content display via Combine subscription.
//

import Cocoa
import Combine

@objc class MainSplitViewController: NSSplitViewController {

    private enum PersistenceKey {
        static let sidebarWidth = "ArculatorSidebarWidth"
    }

    @objc private(set) var contentController: ContentHostingController!
    private var sidebarController: SidebarHostingController!

    private let configList = ConfigListModel()
    private let configModel = MachineConfigModel()
    private var selectionSubscription: AnyCancellable?
    private var stateSubscription: AnyCancellable?
    private var restoredSidebarWidth = false
    private var sidebarWidthSaveTimer: Timer?

    @objc var configListModel: ConfigListModel { configList }

    override func viewDidLoad() {
        super.viewDidLoad()

        sidebarController = SidebarHostingController(configList: configList, configModel: configModel)
        contentController = ContentHostingController(configList: configList)

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 400
        sidebarItem.canCollapse = true
        sidebarItem.collapseBehavior = .preferResizingSplitViewWithFixedSiblings

        let contentItem = NSSplitViewItem(contentListWithViewController: contentController)
        contentItem.minimumThickness = 400

        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)
        splitView.delegate = self

        selectionSubscription = configList.$selectedConfigName
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] name in
                guard let self else { return }
                if let name, !name.isEmpty {
                    self.configList.loadConfig(named: name)
                    self.configModel.loadFromGlobals()
                    self.configModel.enableAutoSave()
                    if EmulatorState.shared.isIdle {
                        self.contentController.showConfigEditor(model: self.configModel)
                    }
                } else {
                    self.configModel.disableAutoSave()
                    self.contentController.clearConfigEditor()
                }
            }

        // Refresh model with post-emulation state when returning to idle.
        // ContentHostingController owns the view transition (removing Metal
        // view, restoring config editor).
        stateSubscription = EmulatorState.shared.$sessionState
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self, state == .idle else { return }
                if self.configList.selectedConfigName != nil {
                    self.configModel.loadFromGlobals()
                }
            }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        restoreSidebarWidthIfNeeded()
    }

    @objc func navigateToConfigEditor() {
        guard EmulatorState.shared.isActive else { return }

        EmulatorBridge.pauseEmulation()
        configModel.loadFromGlobals()
        configModel.enableAutoSave()
        contentController.showConfigEditor(model: configModel)

        if let sidebarItem = splitViewItems.first, sidebarItem.isCollapsed {
            sidebarItem.isCollapsed = false
        }
    }

    @objc func toggleSidebar() {
        guard let sidebarItem = splitViewItems.first else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            sidebarItem.animator().isCollapsed = !sidebarItem.isCollapsed
        }
    }

    // MARK: - Fullscreen

    private var sidebarWasCollapsed = false
    private var inFullscreen = false

    @objc func enterFullscreen() {
        guard let window = view.window,
              let sidebarItem = splitViewItems.first,
              !inFullscreen else { return }

        inFullscreen = true
        sidebarWasCollapsed = sidebarItem.isCollapsed
        sidebarItem.isCollapsed = true

        window.toolbar?.isVisible = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
    }

    @objc func exitFullscreen() {
        guard let window = view.window,
              let sidebarItem = splitViewItems.first,
              inFullscreen else { return }

        inFullscreen = false

        window.toolbar?.isVisible = true
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible

        if !sidebarWasCollapsed {
            sidebarItem.isCollapsed = false
        }
    }

    // MARK: - Sidebar Persistence

    override func splitViewDidResizeSubviews(_ notification: Notification) {
        guard notification.object as? NSSplitView === splitView,
              let sidebarItem = splitViewItems.first,
              !sidebarItem.isCollapsed else {
            return
        }

        sidebarWidthSaveTimer?.invalidate()
        sidebarWidthSaveTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            guard let self,
                  let sidebarItem = self.splitViewItems.first,
                  !sidebarItem.isCollapsed else { return }
            UserDefaults.standard.set(sidebarItem.viewController.view.frame.width,
                                      forKey: PersistenceKey.sidebarWidth)
        }
    }

    private func restoreSidebarWidthIfNeeded() {
        guard !restoredSidebarWidth,
              let sidebarItem = splitViewItems.first else {
            return
        }

        restoredSidebarWidth = true

        let savedWidth = UserDefaults.standard.double(forKey: PersistenceKey.sidebarWidth)
        guard savedWidth > 0 else { return }

        let clampedWidth = min(max(CGFloat(savedWidth), sidebarItem.minimumThickness),
                               sidebarItem.maximumThickness)
        splitView.setPosition(clampedWidth, ofDividerAt: 0)
    }

}

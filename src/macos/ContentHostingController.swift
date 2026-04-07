//
//  ContentHostingController.swift
//  Arculator
//
//  Manages the content area: shows an idle placeholder when no emulation
//  is running, and swaps in ArcMetalView when emulation starts.
//

import Cocoa
import SwiftUI
import MetalKit
import Combine

private struct IdlePlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Machine Running")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Select a configuration from the sidebar and click Run.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .accessibilityIdentifier("idlePlaceholder")
    }
}

private struct FirstRunWelcomeView: View {
    @ObservedObject var configList: ConfigListModel
    @State private var showingNewConfig = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkles.tv")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Welcome to Arculator")
                .font(.title2.weight(.semibold))
            Text("Create your first machine to start configuring and running emulation in this window.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Create Your First Machine") {
                showingNewConfig = true
            }
            .buttonStyle(.borderedProminent)
            .popover(isPresented: $showingNewConfig) {
                NewConfigPopover(configList: configList, isPresented: $showingNewConfig)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("firstRunWelcome")
    }
}

private struct IdleContentView: View {
    @ObservedObject var configList: ConfigListModel

    @ViewBuilder var body: some View {
        if configList.configNames.isEmpty {
            FirstRunWelcomeView(configList: configList)
        } else {
            IdlePlaceholderView()
        }
    }
}

@objc class ContentHostingController: NSViewController {

    private let configList: ConfigListModel
    private var emulatorView: ArcMetalView?
    private var idleContentHost: NSHostingView<IdleContentView>?
    private var configEditorHost: NSHostingView<ConfigEditorView>?
    private var transitionSnapshotView: NSImageView?
    private var configModel: MachineConfigModel?
    private let emulatorState = EmulatorState.shared
    private var stateSubscription: AnyCancellable?

    init(configList: ConfigListModel) {
        self.configList = configList
        super.init(nibName: nil, bundle: nil)
    }

    @MainActor @preconcurrency required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 768, height: 576))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        showIdleContent()

        stateSubscription = emulatorState.$sessionState
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                if state == .idle && self.emulatorView != nil {
                    self.removeEmulatorView()
                } else if state == .running && self.emulatorView == nil {
                    // Emulation resumed while config editor was shown (e.g.,
                    // after Settings > Configure paused and user clicked Resume).
                    self.installEmulatorView()
                }
            }
    }

    // MARK: - Emulator View Lifecycle

    @discardableResult
    @objc func installEmulatorView() -> MTKView {
        removeTransitionSnapshot()
        removeIdleContent()
        removeConfigEditor()

        let arcView = ArcMetalView.configuredView(frame: view.bounds)

        view.addSubview(arcView)
        EmulatorBridge.setVideoView(arcView)
        emulatorView = arcView

        DispatchQueue.main.async { [weak self] in
            guard let arcView = self?.emulatorView else { return }
            arcView.window?.makeFirstResponder(arcView)
        }

        return arcView
    }

    @objc func removeEmulatorView() {
        let snapshot = captureSnapshot(from: emulatorView)
        removeEmulatorViewOnly()

        // Restore config editor if a config is loaded, otherwise show idle placeholder
        if let model = configModel {
            showConfigEditorView(model: model)
        } else {
            showIdleContent()
        }

        showStopTransition(with: snapshot)
    }

    // MARK: - Config Editor

    /// Show the config editor for the given model.
    func showConfigEditor(model: MachineConfigModel) {
        configModel = model
        removeTransitionSnapshot()
        removeIdleContent()
        removeEmulatorViewOnly()
        showConfigEditorView(model: model)
    }

    /// Clear the config editor and return to idle placeholder.
    func clearConfigEditor() {
        configModel?.disableAutoSave()
        configModel = nil
        removeConfigEditor()
        if emulatorView == nil {
            showIdleContent()
        }
    }

    private func showConfigEditorView(model: MachineConfigModel) {
        guard configEditorHost == nil else { return }
        let editorView = ConfigEditorView(config: model, emulatorState: emulatorState)
        let host = NSHostingView(rootView: editorView)
        host.frame = view.bounds
        host.autoresizingMask = [.width, .height]
        view.addSubview(host)
        configEditorHost = host
    }

    private func removeConfigEditor() {
        configEditorHost?.removeFromSuperview()
        configEditorHost = nil
    }

    /// Remove the Metal view without restoring any other view.
    private func removeEmulatorViewOnly() {
        emulatorView?.removeFromSuperview()
        emulatorView = nil
    }

    // MARK: - Idle Placeholder

    private func showIdleContent() {
        guard idleContentHost == nil else { return }
        let host = NSHostingView(rootView: IdleContentView(configList: configList))
        host.frame = view.bounds
        host.autoresizingMask = [.width, .height]
        view.addSubview(host)
        idleContentHost = host
    }

    private func removeIdleContent() {
        idleContentHost?.removeFromSuperview()
        idleContentHost = nil
    }

    private func captureSnapshot(from emulatorView: ArcMetalView?) -> NSImage? {
        guard let emulatorView,
              let window = emulatorView.window,
              window.occlusionState.contains(.visible) else {
            return nil
        }

        let rectInWindow = emulatorView.convert(emulatorView.bounds, to: nil)
        let rectInScreen = window.convertToScreen(rectInWindow)
        guard let imageRef = CGWindowListCreateImage(
            rectInScreen,
            .optionIncludingWindow,
            CGWindowID(window.windowNumber),
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            return nil
        }

        return NSImage(cgImage: imageRef, size: emulatorView.bounds.size)
    }

    private func showStopTransition(with image: NSImage?) {
        guard let image else { return }

        removeTransitionSnapshot()

        let imageView = NSImageView(frame: view.bounds)
        imageView.image = image
        imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]
        imageView.alphaValue = 0.55
        view.addSubview(imageView)
        transitionSnapshotView = imageView

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            imageView.animator().alphaValue = 0
        } completionHandler: { [weak self, weak imageView] in
            guard let self, self.transitionSnapshotView === imageView else { return }
            self.removeTransitionSnapshot()
        }
    }

    private func removeTransitionSnapshot() {
        transitionSnapshotView?.removeFromSuperview()
        transitionSnapshotView = nil
    }
}

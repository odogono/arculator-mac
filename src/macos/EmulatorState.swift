//
//  EmulatorState.swift
//  Arculator
//
//  ObservableObject that polls the emulation runtime state via a
//  main-thread Timer and exposes read-only @Published properties.
//

import Foundation

class EmulatorState: ObservableObject {

    static let shared = EmulatorState()

    // MARK: - Published Properties

    @Published private(set) var sessionState: ARCSessionState = .idle
    @Published private(set) var activeConfigName: String = ""
    @Published private(set) var speedPercent: Int = 0
    @Published private(set) var discNames: [String] = Array(repeating: "", count: discSlotCount)
    @Published private(set) var canSaveSnapshot: Bool = false

    // MARK: - Computed Properties

    var isRunning: Bool { sessionState == .running }
    var isPaused: Bool { sessionState == .paused }
    var isIdle: Bool { sessionState == .idle }
    var isActive: Bool { sessionState != .idle }

    // MARK: - Private

    private static let discSlotCount = 4
    private static let discNameBufferSize = 512
    private var pollTimer: Timer?

    // MARK: - Lifecycle

    init() {
        startPolling()
    }

    deinit {
        stopPolling()
    }

    func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Polling

    private func poll() {
        let newState = EmulatorBridge.sessionState()
        if newState != sessionState {
            sessionState = newState
        }

        let newConfigName = EmulatorBridge.activeConfigName()
        if newConfigName != activeConfigName {
            activeConfigName = newConfigName
        }

        let newSpeed = Int(inssec)
        if newSpeed != speedPercent {
            speedPercent = newSpeed
        }

        for i in 0..<Self.discSlotCount {
            let name = readDiscName(at: i)
            if name != discNames[i] {
                discNames[i] = name
            }
        }

        let newCanSave = (sessionState == .paused) && EmulatorBridge.canSaveSnapshot()
        if newCanSave != canSaveSnapshot {
            canSaveSnapshot = newCanSave
        }
    }

    private func readDiscName(at index: Int) -> String {
        withUnsafePointer(to: &discname) { ptr in
            let raw = UnsafeRawPointer(ptr).advanced(by: index * Self.discNameBufferSize)
            return String(cString: raw.assumingMemoryBound(to: CChar.self))
        }
    }
}

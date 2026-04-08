//
//  SnapshotBrowserModel.swift
//  Arculator
//
//  Backing model for the "Load Snapshot" browser page. Enumerates
//  .arcsnap files in <support>/snapshots/, peeks each one through
//  snapshot_peek_summary(), and exposes the results as an ordered
//  array of SnapshotSummaryData for SwiftUI.
//

import AppKit
import Foundation
import SwiftUI

@MainActor
final class SnapshotBrowserModel: ObservableObject {

    @Published private(set) var entries: [SnapshotSummaryData] = []
    @Published private(set) var isLoading: Bool = false
    @Published var loadError: String?

    func refresh() {
        isLoading = true
        loadError = nil

        let dir = EmulatorBridge.snapshotsDirectoryPath()
        guard !dir.isEmpty else {
            isLoading = false
            entries = []
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let results = Self.loadEntries(in: dir)
            DispatchQueue.main.async {
                guard let self else { return }
                self.entries = results
                self.isLoading = false
            }
        }
    }

    /// Peek failures are logged and skipped so one corrupt file
    /// doesn't hide the rest.
    private static func loadEntries(in dir: String) -> [SnapshotSummaryData] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir) else {
            return []
        }

        var out: [SnapshotSummaryData] = []
        out.reserveCapacity(files.count)

        for name in files {
            guard name.hasSuffix(".arcsnap") else { continue }
            let path = (dir as NSString).appendingPathComponent(name)
            var error: NSString?
            if let summary = EmulatorBridge.peekSnapshotSummary(atPath: path, error: &error) {
                out.append(summary)
            } else {
                NSLog("SnapshotBrowser: skipped %@: %@",
                      path, (error as String?) ?? "unknown error")
            }
        }

        // Newest first.
        out.sort { a, b in
            let da = a.createdAt ?? .distantPast
            let db = b.createdAt ?? .distantPast
            return da > db
        }
        return out
    }

    /// Shows an NSOpenPanel as the "Browse Other Location…" escape hatch.
    /// Returns the chosen path, or nil if the user cancelled.
    func chooseOtherLocation() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["arcsnap"]
        let dir = EmulatorBridge.snapshotsDirectoryPath()
        if !dir.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: dir, isDirectory: true)
        }
        if panel.runModal() != .OK { return nil }
        return panel.url?.path
    }
}

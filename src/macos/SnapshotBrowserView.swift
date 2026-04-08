//
//  SnapshotBrowserView.swift
//  Arculator
//
//  "Load Snapshot" content-area page. Lists .arcsnap files in the
//  support directory with thumbnail, title, machine, timestamp, and
//  floppy count. Picking an entry invokes `onOpen` with the chosen
//  path; "Browse Other Location…" opens an NSOpenPanel as an escape
//  hatch for snapshots stored outside the default directory.
//

import AppKit
import SwiftUI

struct SnapshotBrowserView: View {

    @ObservedObject var model: SnapshotBrowserModel
    let onOpen: (String) -> Void
    let onClose: () -> Void

    @State private var selectedPath: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            contentBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            bottomBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand { onClose() }
        .accessibilityIdentifier("snapshotBrowserPage")
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Load Snapshot")
                .font(.title2.weight(.semibold))
            Spacer()
            Button {
                model.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
            .accessibilityIdentifier("snapshotBrowserRefreshButton")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentBody: some View {
        if model.isLoading && model.entries.isEmpty {
            ProgressView("Reading snapshots…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.entries.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(model.entries, id: \.filePath) { entry in
                        SnapshotBrowserRow(
                            entry: entry,
                            isSelected: selectedPath == entry.filePath,
                            onSelect: { selectedPath = entry.filePath },
                            onOpen:   { onOpen(entry.filePath) }
                        )
                    }
                }
                .padding(16)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.stack")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No snapshots in \(EmulatorBridge.snapshotsDirectoryPath())")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack {
            Button(action: onClose) {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("snapshotBrowserBackButton")

            Spacer()

            Button("Browse Other Location…") {
                if let path = model.chooseOtherLocation() {
                    onOpen(path)
                }
            }
            .accessibilityIdentifier("snapshotBrowserBrowseOtherButton")

            Button("Open") {
                if let path = selectedPath { onOpen(path) }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(selectedPath == nil)
            .accessibilityIdentifier("snapshotBrowserOpenButton")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Row

private struct SnapshotBrowserRow: View {

    let entry: SnapshotSummaryData
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack(spacing: 14) {
            thumbnail

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.displayName)
                    .font(.headline)
                    .lineLimit(1)

                if let desc = entry.descriptionText, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    if !entry.machineConfigName.isEmpty {
                        Label(entry.machineConfigName, systemImage: "desktopcomputer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !entry.machine.isEmpty {
                        Text(entry.machine)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    if let date = entry.createdAt {
                        Label(
                            Self.timestampFormatter.string(from: date),
                            systemImage: "clock"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    if !entry.floppyPaths.isEmpty {
                        Label("\(entry.floppyPaths.count)",
                              systemImage: "opticaldisc")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected
                      ? Color.accentColor.opacity(0.18)
                      : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpen() }
        .onTapGesture { onSelect() }
        .accessibilityIdentifier("snapshotBrowserRow")
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.25))
            if let nsImage = entry.preview {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 96, height: 72)
    }
}

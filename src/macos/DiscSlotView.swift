//
//  DiscSlotView.swift
//  Arculator
//
//  Per-drive disc slot controls: disc name display, Change button
//  (opens NSOpenPanel), and Eject button. Used by RunningControlsView.
//

import SwiftUI
import UniformTypeIdentifiers

struct DiscSlotView: View {

    let driveIndex: Int
    let discName: String
    @State private var isDropTargeted = false

    private var isEmpty: Bool { discName.isEmpty }
    private static let allowedExtensions = Set(["adf", "img", "fdi", "apd", "hfe", "scp", "ssd", "dsd"])

    private var displayName: String {
        if isEmpty { return "Empty" }
        return (discName as NSString).lastPathComponent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Drive \(driveIndex)", systemImage: "opticaldisc")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Text(displayName)
                .font(.caption)
                .foregroundStyle(isEmpty ? .tertiary : .primary)
                .truncationMode(.middle)
                .lineLimit(1)
                .help(isEmpty ? "" : discName)

            HStack(spacing: 6) {
                Button("Change") {
                    changeDisc()
                }
                .controlSize(.mini)

                Button("Eject") {
                    EmulatorBridge.ejectDisc(Int32(driveIndex))
                }
                .controlSize(.mini)
                .disabled(isEmpty)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isDropTargeted ? Color.accentColor.opacity(0.14) : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isDropTargeted ? Color.accentColor : Color.clear, lineWidth: 1)
        }
        .dropDestination(for: URL.self) { items, _ in
            guard let url = items.first else { return false }
            return loadDroppedDisc(from: url)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .accessibilityIdentifier("discSlot_\(driveIndex)")
    }

    private func changeDisc() {
        let types = Self.allowedExtensions.compactMap { UTType(filenameExtension: $0) }

        let panel = NSOpenPanel()
        panel.title = "Select a disc image"
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        EmulatorBridge.changeDisc(Int32(driveIndex), path: url.path)
    }

    private func loadDroppedDisc(from url: URL) -> Bool {
        let normalizedURL = url.standardizedFileURL
        guard normalizedURL.isFileURL,
              Self.allowedExtensions.contains(normalizedURL.pathExtension.lowercased()) else {
            return false
        }

        EmulatorBridge.changeDisc(Int32(driveIndex), path: normalizedURL.path)
        return true
    }
}

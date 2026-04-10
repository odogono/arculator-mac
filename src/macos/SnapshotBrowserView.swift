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

// MARK: - Identifiable conformance for sheet(item:)

extension SnapshotSummaryData: @retroactive Identifiable {
    public var id: String { filePath }
}

struct SnapshotBrowserView: View {

    @ObservedObject var model: SnapshotBrowserModel
    let onOpen: (String) -> Void
    let onClose: () -> Void

    @State private var selectedPath: String?
    @State private var editingEntry: SnapshotSummaryData?
    @State private var editName: String = ""
    @State private var editDescription: String = ""
    @State private var editPreview: NSImage?
    @State private var previewChanged: Bool = false
    @State private var deletingEntry: SnapshotSummaryData?

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
        .sheet(item: $editingEntry) { entry in
            SnapshotEditSheet(
                entry: entry,
                name: $editName,
                description: $editDescription,
                preview: $editPreview,
                previewChanged: $previewChanged,
                onSave: {
                    saveEdits(for: entry)
                },
                onCancel: {
                    editingEntry = nil
                }
            )
        }
        .alert("Delete Snapshot?",
               isPresented: Binding(
                   get: { deletingEntry != nil },
                   set: { if !$0 { deletingEntry = nil } }
               )
        ) {
            Button("Delete", role: .destructive) {
                if let entry = deletingEntry {
                    deleteSnapshot(entry)
                }
            }
            Button("Cancel", role: .cancel) {
                deletingEntry = nil
            }
        } message: {
            if let entry = deletingEntry {
                Text("\u{201C}\(entry.displayName)\u{201D} will be permanently deleted.")
            }
        }
        .accessibilityElement(children: .contain)
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
                        .contextMenu {
                            Button("Edit Details\u{2026}") {
                                beginEditing(entry)
                            }
                            Divider()
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting(
                                    [URL(fileURLWithPath: entry.filePath)])
                            }
                            Divider()
                            Button("Delete\u{2026}") {
                                deletingEntry = entry
                            }
                        }
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

    // MARK: - Editing helpers

    private func beginEditing(_ entry: SnapshotSummaryData) {
        editName = entry.displayName
        editDescription = entry.descriptionText ?? ""
        editPreview = entry.preview
        previewChanged = false
        editingEntry = entry
    }

    private func saveEdits(for entry: SnapshotSummaryData) {
        var error: NSString?

        let ok = EmulatorBridge.updateSnapshot(
            atPath: entry.filePath,
            name: editName,
            description: editDescription,
            updatePreview: previewChanged,
            preview: editPreview,
            error: &error
        )
        if !ok {
            NSLog("SnapshotBrowser: edit failed: %@",
                  (error as String?) ?? "unknown error")
        }

        editingEntry = nil
        model.refresh()
    }

    private func deleteSnapshot(_ entry: SnapshotSummaryData) {
        do {
            try FileManager.default.removeItem(atPath: entry.filePath)
            if selectedPath == entry.filePath {
                selectedPath = nil
            }
            model.refresh()
        } catch {
            NSLog("SnapshotBrowser: delete failed: %@",
                  error.localizedDescription)
        }
        deletingEntry = nil
    }
}

// MARK: - Edit Sheet

private struct SnapshotEditSheet: View {

    let entry: SnapshotSummaryData
    @Binding var name: String
    @Binding var description: String
    @Binding var preview: NSImage?
    @Binding var previewChanged: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Snapshot Details")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Preview image (interactive: click to select, Cmd+C/V)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Preview")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Click to select, then \u{2318}C to copy or \u{2318}V to paste")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        SnapshotPreviewEditor(
                            image: $preview,
                            onChanged: { previewChanged = true }
                        )
                        .frame(height: 160)
                    }

                    // Name
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Snapshot name", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Description
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Description")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $description)
                            .font(.body)
                            .frame(minHeight: 60, maxHeight: 120)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(nsColor: .separatorColor),
                                            lineWidth: 0.5)
                            )
                    }

                    // Read-only info
                    if !entry.machineConfigName.isEmpty || !entry.machine.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Machine")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                if !entry.machineConfigName.isEmpty {
                                    Label(entry.machineConfigName,
                                          systemImage: "desktopcomputer")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                                if !entry.machine.isEmpty {
                                    Text(entry.machine)
                                        .font(.callout.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            // Buttons
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 420, height: 520)
    }
}

// MARK: - Preview Image Editor (NSViewRepresentable)
//
// An interactive image view that becomes first responder on click and
// responds to the standard Cmd+C / Cmd+V via the responder chain's
// copy: / paste: selectors. Also provides a right-click context menu.

private struct SnapshotPreviewEditor: NSViewRepresentable {

    @Binding var image: NSImage?
    var onChanged: () -> Void

    func makeNSView(context: Context) -> SnapshotPreviewNSView {
        let view = SnapshotPreviewNSView()
        view.image = image
        view.onImageChanged = { newImage in
            image = newImage
            onChanged()
        }
        return view
    }

    func updateNSView(_ nsView: SnapshotPreviewNSView, context: Context) {
        nsView.image = image
        nsView.onImageChanged = { newImage in
            image = newImage
            onChanged()
        }
        nsView.needsDisplay = true
    }
}

private final class SnapshotPreviewNSView: NSView {

    var image: NSImage?
    var onImageChanged: ((NSImage?) -> Void)?
    private var isFocused = false

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy",  action: #selector(copy(_:)),  keyEquivalent: "")
        menu.addItem(withTitle: "Paste", action: #selector(paste(_:)), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Clear", action: #selector(clearPreview(_:)), keyEquivalent: "")
        self.menu = menu
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Focus

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        isFocused = true
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        isFocused = false
        needsDisplay = true
        return true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let bgColor = NSColor.black.withAlphaComponent(0.15)
        let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)

        bgColor.setFill()
        path.fill()

        if let img = image {
            let imgSize = img.size
            guard imgSize.width > 0, imgSize.height > 0 else { return }
            let scale = min(bounds.width / imgSize.width,
                            bounds.height / imgSize.height)
            let drawSize = NSSize(width: imgSize.width * scale,
                                  height: imgSize.height * scale)
            let origin = NSPoint(x: (bounds.width  - drawSize.width)  / 2,
                                 y: (bounds.height - drawSize.height) / 2)
            img.draw(in: NSRect(origin: origin, size: drawSize),
                     from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            if let symbol = NSImage(systemSymbolName: "photo",
                                    accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: 28,
                                                         weight: .regular)
                let configured = symbol.withSymbolConfiguration(config) ?? symbol
                let symSize = configured.size
                let origin = NSPoint(x: (bounds.width  - symSize.width)  / 2,
                                     y: (bounds.height - symSize.height) / 2)
                configured.draw(in: NSRect(origin: origin, size: symSize),
                                from: .zero, operation: .sourceOver, fraction: 0.3)
            }
        }

        if isFocused {
            NSColor.controlAccentColor.setStroke()
            let inset = path.copy() as! NSBezierPath
            inset.lineWidth = 2.5
            inset.stroke()
        }
    }

    // MARK: Key equivalents

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        let flags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
        guard flags == .command else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case "c":
            if image != nil { copy(nil); return true }
        case "v":
            paste(nil)
            return true
        default:
            break
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: Copy / Paste

    @objc func copy(_ sender: Any?) {
        guard let img = image else { NSSound.beep(); return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([img])
    }

    @objc func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        guard let images = pb.readObjects(forClasses: [NSImage.self],
                                          options: nil) as? [NSImage],
              let pasted = images.first else {
            NSSound.beep()
            return
        }
        image = pasted
        onImageChanged?(pasted)
        needsDisplay = true
    }

    @objc func clearPreview(_ sender: Any?) {
        image = nil
        onImageChanged?(nil)
        needsDisplay = true
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(copy(_:)) {
            return image != nil
        }
        if menuItem.action == #selector(paste(_:)) {
            return NSPasteboard.general.canReadObject(
                forClasses: [NSImage.self], options: nil)
        }
        if menuItem.action == #selector(clearPreview(_:)) {
            return image != nil
        }
        return false
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

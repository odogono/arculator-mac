//
//  StorageSettingsView.swift
//  Arculator
//
//  2x IDE hard drives (path + browse + geometry fields) and
//  5th Column ROM path. HD sub-dialogs (New, Configure) launch
//  via ConfigEditorBridge as modal AppKit dialogs.
//

import SwiftUI

struct StorageSettingsView: View {
    @ObservedObject var config: MachineConfigModel
    @ObservedObject var emulatorState: EmulatorState

    private var isST506: Bool {
        config.ioType == .oldST506
    }

    private var sectorSize: Int {
        isST506 ? 256 : 512
    }

    var body: some View {
        Form {
            hdSection(drive: 0, label: "Hard Drive 4")
            hdSection(drive: 1, label: "Hard Drive 5")
            if config.has5thColumn {
                fifthColumnSection
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.visible)
    }

    // MARK: - Hard Drive Section

    private func hdSection(drive: Int, label: String) -> some View {
        let path = hdPath(for: drive)
        return Section(label) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(path.isEmpty ? "No image selected" : path)
                        .foregroundStyle(path.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }

                HStack(spacing: 8) {
                    Button("Select...") {
                        selectHD(drive: drive)
                    }
                    Button("New...") {
                        newHD(drive: drive)
                    }
                    Button("Eject") {
                        setHDPath(drive: drive, path: "")
                        setHDGeometry(drive: drive, cyl: 0, hpc: 0, spt: 0)
                    }
                    .disabled(path.isEmpty)
                }
                .controlSize(.small)

                Text("New... creates a blank image. Internal drives are exposed at boot, but blank images still need formatting in RISC OS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !path.isEmpty {
                    geometryFields(drive: drive)
                }
            }
            .mutabilityGated(ARCSettingHDPaths, emulatorState: emulatorState)
        }
    }

    private func geometryFields(drive: Int) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text("Cylinders").font(.caption).foregroundStyle(.secondary)
                Text("Heads").font(.caption).foregroundStyle(.secondary)
                Text("Sectors").font(.caption).foregroundStyle(.secondary)
                Text("Size").font(.caption).foregroundStyle(.secondary)
            }
            GridRow {
                intField(value: hdCylBinding(drive), range: 0...16383)
                intField(value: hdHpcBinding(drive), range: 0...16)
                intField(value: hdSptBinding(drive), range: 0...63)
                Text(hdSizeString(drive: drive))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 60)
            }
        }
    }

    private func intField(value: Binding<Int32>, range: ClosedRange<Int>) -> some View {
        TextField("", value: value, format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: 70)
            .multilineTextAlignment(.trailing)
    }

    // MARK: - 5th Column ROM

    private var fifthColumnSection: some View {
        Section("5th Column ROM") {
            HStack {
                Text(config.fifthColumnPath.isEmpty ? "No ROM selected" : config.fifthColumnPath)
                    .foregroundStyle(config.fifthColumnPath.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            HStack(spacing: 8) {
                Button("Select...") {
                    selectFifthColumn()
                }
                Button("Clear") {
                    config.fifthColumnPath = ""
                }
                .disabled(config.fifthColumnPath.isEmpty)
            }
            .controlSize(.small)
            .mutabilityGated(ARCSetting5thColumnROM, emulatorState: emulatorState)
        }
    }

    // MARK: - HD Path/Geometry Accessors

    private func hdPath(for drive: Int) -> String {
        drive == 0 ? config.hdPath0 : config.hdPath1
    }

    private func setHDPath(drive: Int, path: String) {
        if drive == 0 { config.hdPath0 = path } else { config.hdPath1 = path }
    }

    private func setHDGeometry(drive: Int, cyl: Int32, hpc: Int32, spt: Int32) {
        if drive == 0 {
            config.hdCyl0 = cyl; config.hdHpc0 = hpc; config.hdSpt0 = spt
        } else {
            config.hdCyl1 = cyl; config.hdHpc1 = hpc; config.hdSpt1 = spt
        }
    }

    private func hdCylBinding(_ drive: Int) -> Binding<Int32> {
        Binding(get: { drive == 0 ? config.hdCyl0 : config.hdCyl1 },
                set: { drive == 0 ? (config.hdCyl0 = $0) : (config.hdCyl1 = $0) })
    }

    private func hdHpcBinding(_ drive: Int) -> Binding<Int32> {
        Binding(get: { drive == 0 ? config.hdHpc0 : config.hdHpc1 },
                set: { drive == 0 ? (config.hdHpc0 = $0) : (config.hdHpc1 = $0) })
    }

    private func hdSptBinding(_ drive: Int) -> Binding<Int32> {
        Binding(get: { drive == 0 ? config.hdSpt0 : config.hdSpt1 },
                set: { drive == 0 ? (config.hdSpt0 = $0) : (config.hdSpt1 = $0) })
    }

    private func hdSizeString(drive: Int) -> String {
        let cyl = drive == 0 ? config.hdCyl0 : config.hdCyl1
        let hpc = drive == 0 ? config.hdHpc0 : config.hdHpc1
        let spt = drive == 0 ? config.hdSpt0 : config.hdSpt1
        guard cyl > 0, hpc > 0, spt > 0 else { return "" }
        let bytes = Int(cyl) * Int(hpc) * Int(spt) * sectorSize
        let mb = bytes / (1024 * 1024)
        return "\(mb) MB"
    }

    // MARK: - Dialog Actions

    private func selectHD(drive: Int) {
        let panel = NSOpenPanel()
        panel.title = "Select a disc image"
        panel.allowedContentTypes = [.init(filenameExtension: "hdf")!]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let path = url.path
        if let result = ConfigEditorBridge.showConfHD(withPath: path, isST506: isST506) {
            setHDPath(drive: drive, path: result.path)
            setHDGeometry(drive: drive, cyl: Int32(result.cylinders), hpc: Int32(result.heads), spt: Int32(result.sectors))
        }
    }

    private func newHD(drive: Int) {
        if let result = ConfigEditorBridge.showNewHD(withST506: isST506) {
            setHDPath(drive: drive, path: result.path)
            setHDGeometry(drive: drive, cyl: Int32(result.cylinders), hpc: Int32(result.heads), spt: Int32(result.sectors))
        }
    }

    private func selectFifthColumn() {
        let panel = NSOpenPanel()
        panel.title = "Select a 5th Column ROM image"
        panel.allowedContentTypes = [
            .init(filenameExtension: "bin")!,
            .init(filenameExtension: "rom")!
        ]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        config.fifthColumnPath = url.path
    }
}

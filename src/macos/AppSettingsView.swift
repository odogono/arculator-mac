//
//  AppSettingsView.swift
//  Arculator
//
//  App-wide settings page (single column, sectioned Form). Replaces
//  the content area when the gear button in the sidebar is clicked.
//  Dismissed via the Back button or Escape (.onExitCommand).
//

import AppKit
import SwiftUI

struct AppSettingsView: View {

    @ObservedObject var settings: AppSettings
    let onClose: () -> Void

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                Form {
                    Section("General") {
                        userDataLocationRow
                        if settings.pendingRestart {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("Restart Arculator to apply the new location.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        releaseShortcutRow
                    }

                    Section("About") {
                        aboutRow
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.visible)
            }

            Divider()
            bottomBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand { onClose() }
        .accessibilityIdentifier("appSettingsPage")
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.title2.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack {
            Button(action: onClose) {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("appSettingsBackButton")
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - General rows

    private var userDataLocationRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("User data location")
                Spacer()
                Button {
                    settings.revealSupportPathInFinder()
                } label: {
                    Image(systemName: "folder")
                }
                .controlSize(.small)
                .help("Reveal in Finder")
                .accessibilityIdentifier("revealSupportPathButton")

                Button("Change…") {
                    settings.chooseSupportPath(presenting: NSApp.keyWindow)
                }
                .controlSize(.small)
                .accessibilityIdentifier("chooseSupportPathButton")
            }

            Text(settings.effectiveSupportPath)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("userDataLocationField")
        }
    }

    private var releaseShortcutRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Mouse release shortcut")
                Text("Pressed inside the emulator window to release a captured mouse.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ShortcutRecorderView(combo: $settings.releaseShortcut)
                .frame(width: 180, height: 26)
        }
    }

    // MARK: - About row

    private var aboutRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("Arculator")
                    .font(.headline)
                Text("Version \(version)\(build.isEmpty ? "" : " (\(build))")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("Up to Date")
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .overlay(
                    Capsule()
                        .stroke(Color.green.opacity(0.5), lineWidth: 1)
                )
                .accessibilityIdentifier("aboutVersionPill")
        }
        .padding(.vertical, 4)
    }
}

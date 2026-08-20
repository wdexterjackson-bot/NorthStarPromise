import NSPDesignSystem
import SwiftUI

/// docs/07 §4's Settings sections, styled like the system Settings app —
/// a colored icon tile per row. Shows real values where this build
/// actually has them (the workspace's processing mode); everything else
/// is a placeholder row rather than a fabricated toggle that doesn't
/// control anything yet.
@MainActor
struct SettingsView: View {
    let environment: AppEnvironment

    var body: some View {
        NavigationStack {
            List {
                Section("Processing") {
                    settingsRow(symbol: "cpu", tint: .blue, title: "Default processing mode") {
                        Text(environment.defaultPolicy?.defaultProcessingMode.rawValue ?? "—")
                            .foregroundStyle(NSPColor.secondaryText)
                    }
                    settingsRow(symbol: "sparkles", tint: .indigo, title: "On-device availability") {
                        Text("Not checked yet").foregroundStyle(NSPColor.secondaryText)
                    }
                }

                unconfiguredSection(
                    title: "Capture", symbol: "mic.fill", tint: .red,
                    message: "Format, segment length, markers, and haptics settings aren't exposed yet.")

                unconfiguredSection(
                    title: "Privacy", symbol: "lock.fill", tint: .green,
                    message: "Consent, retention, redaction, and memory-exclusion defaults aren't exposed yet.")

                unconfiguredSection(
                    title: "Storage", symbol: "internaldrive.fill", tint: .gray,
                    message: "Per-device usage and reclamation policy aren't calculated yet.")

                unconfiguredSection(
                    title: "Sync", symbol: "icloud.fill", tint: .blue,
                    message: "iCloud account state, quota, and sync status aren't connected to this screen yet.")

                unconfiguredSection(
                    title: "Integrations", symbol: "puzzlepiece.extension.fill", tint: .purple,
                    message: "No integrations configured.")

                Section("About") {
                    settingsRow(symbol: "info.circle.fill", tint: .gray, title: "Device ID") {
                        Text(environment.deviceID.rawValue.uuidString.prefix(8))
                            .foregroundStyle(NSPColor.secondaryText)
                            .monospaced()
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    @ViewBuilder
    private func settingsRow<Value: View>(
        symbol: String, tint: Color, title: String, @ViewBuilder value: () -> Value
    ) -> some View {
        HStack(spacing: NSPSpacing.medium) {
            NSPIconBadge(symbolName: symbol, tint: tint)
            Text(title)
            Spacer()
            value()
        }
        .padding(.vertical, 2)
    }

    private func unconfiguredSection(title: String, symbol: String, tint: Color, message: String) -> some View {
        Section(title) {
            HStack(alignment: .top, spacing: NSPSpacing.medium) {
                NSPIconBadge(symbolName: symbol, tint: tint)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(NSPColor.secondaryText)
            }
            .padding(.vertical, 2)
        }
    }
}

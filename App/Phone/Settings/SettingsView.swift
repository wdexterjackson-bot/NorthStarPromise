import SwiftUI

/// docs/07 §4's Settings sections. Shows real values where this build
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
                    LabeledContent(
                        "Default processing mode",
                        value: environment.defaultPolicy?.defaultProcessingMode.rawValue ?? "—")
                    LabeledContent("On-device availability", value: "Not checked yet")
                }

                Section("Capture") {
                    Text("Format, segment length, markers, and haptics settings aren't exposed yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Privacy") {
                    Text("Consent, retention, redaction, and memory-exclusion defaults aren't exposed yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Storage") {
                    Text("Per-device usage and reclamation policy aren't calculated yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Sync") {
                    Text("iCloud account state, quota, and sync status aren't connected to this screen yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Integrations") {
                    Text("No integrations configured.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    LabeledContent("Device ID", value: environment.deviceID.rawValue.uuidString.prefix(8).description)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

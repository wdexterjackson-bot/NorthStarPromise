import NSPActions
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

    @State private var calendars: [CalendarInfo] = []
    @State private var isLoadingCalendars = false
    @State private var calendarAccessDenied = false

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

                calendarSection

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

    /// "Create a calendar event for recordings." Turning this on requests
    /// EventKit write-only access (never reads existing events) and, once
    /// granted, lets the user pick a destination calendar. Every event is
    /// still confirmed individually before creation — this toggle governs
    /// whether the confirmation prompt appears after a recording, not
    /// whether the write itself is silent (I6).
    private var calendarSection: some View {
        Section("Calendar") {
            Toggle(
                "Create calendar event for recordings",
                isOn: Binding(
                    get: { environment.calendarSyncEnabled },
                    set: { newValue in Task { await setCalendarSyncEnabled(newValue) } }))

            if environment.calendarSyncEnabled {
                if isLoadingCalendars {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if calendars.isEmpty {
                    Text("No writable calendars found.")
                        .font(.caption)
                        .foregroundStyle(NSPColor.secondaryText)
                } else {
                    Picker(
                        "Calendar",
                        selection: Binding(
                            get: { environment.selectedCalendarIdentifier ?? calendars[0].identifier },
                            set: { environment.selectedCalendarIdentifier = $0 })
                    ) {
                        ForEach(calendars) { calendar in
                            Text(calendar.title).tag(calendar.identifier)
                        }
                    }
                }
            }

            if calendarAccessDenied {
                Text("Calendar access was denied. Enable it for North-Star Promise in Settings → Privacy & Security.")
                    .font(.caption)
                    .foregroundStyle(NSPColor.statusDanger)
            }

            Text(
                "Adds an event to your chosen calendar after each recording ends. You always confirm the exact "
                    + "time before it's created."
            )
            .font(.caption)
            .foregroundStyle(NSPColor.secondaryText)
        }
        .task {
            if environment.calendarSyncEnabled { await loadCalendars() }
        }
    }

    private func setCalendarSyncEnabled(_ enabled: Bool) async {
        guard enabled else {
            environment.calendarSyncEnabled = false
            return
        }
        let status = await environment.calendarEventWriter.requestAccess()
        if status == .authorized {
            calendarAccessDenied = false
            environment.calendarSyncEnabled = true
            await loadCalendars()
        } else {
            calendarAccessDenied = true
            environment.calendarSyncEnabled = false
        }
    }

    private func loadCalendars() async {
        isLoadingCalendars = true
        defer { isLoadingCalendars = false }
        calendars = await environment.calendarEventWriter.availableCalendars()
        if environment.selectedCalendarIdentifier == nil {
            environment.selectedCalendarIdentifier = calendars.first?.identifier
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

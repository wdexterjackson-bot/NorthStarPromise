import NSPActions
import NSPCore
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
                appearanceSection

                Section("Processing") {
                    settingsRow(symbol: "cpu", tint: .blue, title: "Default processing mode") {
                        Text(environment.defaultPolicy?.defaultProcessingMode.rawValue ?? "—")
                            .foregroundStyle(Palette.textTertiary)
                    }
                    settingsRow(symbol: "sparkles", tint: .indigo, title: "On-device availability") {
                        Text("Not checked yet").foregroundStyle(Palette.textTertiary)
                    }
                }

                calendarSection

                ambientSection

                unconfiguredSection(
                    title: "Capture", symbol: "mic.fill", tint: .red,
                    message: "Format, segment length, markers, and haptics settings aren't exposed yet.")

                unconfiguredSection(
                    title: "Privacy", symbol: "lock.fill", tint: .green,
                    message: "Consent, retention, redaction, and memory-exclusion defaults aren't exposed yet.")

                unconfiguredSection(
                    title: "Storage", symbol: "internaldrive.fill", tint: .gray,
                    message: "Per-device usage and reclamation policy aren't calculated yet.")

                syncSection

                unconfiguredSection(
                    title: "Integrations", symbol: "puzzlepiece.extension.fill", tint: .purple,
                    message: "No integrations configured.")

                Section("About") {
                    settingsRow(symbol: "info.circle.fill", tint: .gray, title: "Device ID") {
                        Text(environment.deviceID.rawValue.uuidString.prefix(8))
                            .foregroundStyle(Palette.textTertiary)
                            .monospaced()
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    /// System / Light / Dark override (`AppEnvironment.appearanceMode`'s own
    /// doc comment) — the mockups show iPhone in dark and iPad in light,
    /// but that's a presentation choice, not a platform rule
    /// (`DASHBOARD_SPEC.md` §2.1: "ship both themes on both devices").
    private var appearanceSection: some View {
        Section("Appearance") {
            Picker(
                "Theme",
                selection: Binding(
                    get: { environment.appearanceMode }, set: { environment.appearanceMode = $0 })
            ) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
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
                        .font(Typo.ui(11.5, .medium))
                        .foregroundStyle(Palette.textTertiary)
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
                    .font(Typo.ui(11.5, .medium))
                    .foregroundStyle(Palette.danger.foreground)
            }

            Text(
                "Adds an event to your chosen calendar after each recording ends. You always confirm the exact "
                    + "time before it's created."
            )
            .font(Typo.ui(11.5, .medium))
            .foregroundStyle(Palette.textTertiary)
        }
        .task {
            if environment.calendarSyncEnabled { await loadCalendars() }
        }
    }

    /// Duration options in the picker — 30-minute steps up to 2.5 hours
    /// (150 min), the locked decision from "Overheard," 2026-08-22.
    /// 5-minute increments up to 2.5 hours (150 min) — the locked
    /// decision, 2026-08-22.
    private static let ambientDurationOptionsMinutes = Array(stride(from: 5, through: 150, by: 5))

    /// "Exercise Mode"'s own settings — internally still `Policy
    /// .ambientModeEnabled` etc. ("Overheard" recommendation, 2026-08-22;
    /// relabeled 2026-08-22). Toggling this on is the workspace's standing
    /// permission to use the feature at all; a live session's own
    /// start/stop lives on `AmbientModeView`, reached from the capture
    /// button's long-press menu or My Work, not here.
    private var ambientSection: some View {
        Section {
            Toggle(
                "Exercise Mode",
                isOn: Binding(
                    get: { environment.defaultPolicy?.ambientModeEnabled ?? false },
                    set: { newValue in Task { await setAmbientModeEnabled(newValue) } }))
            if environment.defaultPolicy?.ambientModeEnabled == true {
                Picker(
                    "Session length",
                    selection: Binding(
                        get: { environment.defaultPolicy?.ambientSessionDurationMinutes ?? 60 },
                        set: { newValue in Task { await setAmbientSessionDuration(newValue) } })
                ) {
                    ForEach(Self.ambientDurationOptionsMinutes, id: \.self) { minutes in
                        Text(Self.durationLabel(minutes)).tag(minutes)
                    }
                }
                .pickerStyle(.wheel)
            }
        } header: {
            Text("Exercise Mode")
        } footer: {
            Text(
                "Recording in Exercise Mode allows you to capture notes, project updates, action items, etc. for "
                    + "your later review without saving the recording or creating a meeting out of the session.")
        }
    }

    private static func durationLabel(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(minutes) min" }
        if remainder == 0 { return "\(hours) hr" }
        return "\(hours) hr \(remainder) min"
    }

    private func setAmbientModeEnabled(_ enabled: Bool) async {
        guard var policy = environment.defaultPolicy else { return }
        policy.ambientModeEnabled = enabled
        await savePolicy(policy)
    }

    private func setAmbientSessionDuration(_ minutes: Int) async {
        guard var policy = environment.defaultPolicy else { return }
        policy.ambientSessionDurationMinutes = minutes
        await savePolicy(policy)
    }

    private func savePolicy(_ policy: Policy) async {
        do {
            try await environment.policyRepository.update(policy, at: environment.clock.now())
            environment.refreshDefaultPolicy(policy)
        } catch {
            // Settings toggles have no dedicated error surface today — a
            // failed write just leaves the toggle showing the prior,
            // still-accurate value on next read rather than a silent
            // false success.
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

    /// Explicit opt-in (I6): off by default, matching docs/06's safest
    /// default. Turning this on only changes the *workspace's live
    /// default* policy — meetings already recorded keep whatever mode
    /// they were armed under (I5's freeze-at-Arming rule); only meetings
    /// recorded after this point sync.
    private var syncSection: some View {
        Section("Sync") {
            Toggle(
                "Sync to iCloud",
                isOn: Binding(
                    get: { environment.defaultPolicy?.defaultProcessingMode != .localOnly },
                    set: { newValue in Task { await setSyncEnabled(newValue) } }))

            if environment.defaultPolicy?.defaultProcessingMode != .localOnly {
                syncStatusRow
                Button("Sync Now") { Task { await syncNow() } }
                    .disabled(environment.syncCoordinator.status == .syncing)
            }

            Text(
                "Recordings made while this is on are pushed to your private iCloud, so they show up on your "
                    + "other devices signed into the same Apple ID. Meetings already recorded aren't affected."
            )
            .font(Typo.ui(11.5, .medium))
            .foregroundStyle(Palette.textTertiary)
        }
    }

    @ViewBuilder
    private var syncStatusRow: some View {
        switch environment.syncCoordinator.status {
        case .idle:
            settingsRow(symbol: "icloud", tint: .blue, title: "Status") {
                Text("Idle").foregroundStyle(Palette.textTertiary)
            }
        case .syncing:
            settingsRow(symbol: "icloud", tint: .blue, title: "Status") {
                ProgressView()
            }
        case .succeeded(let date):
            settingsRow(symbol: "checkmark.icloud", tint: .green, title: "Status") {
                Text("Last synced \(date.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(Palette.textTertiary)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 2) {
                settingsRow(symbol: "exclamationmark.icloud", tint: .orange, title: "Status") {
                    Text("Couldn't sync").foregroundStyle(Palette.danger.foreground)
                }
                Text(message)
                    .font(Typo.ui(10.5, .medium))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
    }

    private func setSyncEnabled(_ enabled: Bool) async {
        guard var policy = environment.defaultPolicy else { return }
        policy.defaultProcessingMode = enabled ? .onDevicePreferred : .localOnly
        try? await environment.policyRepository.update(policy, at: environment.clock.now())
        environment.refreshDefaultPolicy(policy)
    }

    private func syncNow() async {
        guard let workspaceID = environment.defaultPolicy?.workspaceID else { return }
        await environment.syncCoordinator.syncNow(workspaceID: workspaceID)
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
                    .font(Typo.ui(11.5, .medium))
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(.vertical, 2)
        }
    }
}

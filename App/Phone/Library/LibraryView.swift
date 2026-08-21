import NSPCore
import NSPDesignSystem
import SwiftUI

/// docs/07 §4's Library screen: search, filter, sort, saved searches, and
/// paged rows that never load transcripts. Now lists all three artifact
/// kinds the Library actually holds — Meetings, Brain Dumps, and Notes
/// (docs/09-BACKLOG.md, "rescoping the meeting-organization data model":
/// "the Library contains all containers of artifacts," not just meetings)
/// — rather than only ever showing `Meeting`s and implying everything in
/// the app is one. Filter chips cover lifecycle state (the most useful axis
/// given nothing generates actions or owners yet, and `BrainDump`/`Note`
/// reuse the same `MeetingState` enum, so one filter set already covers all
/// three); date/workspace/`captureMode`/has-actions/has-unresolved-owner/
/// `excludedFromMemory` chips and saved searches are a follow-up, not a
/// silent scope cut (documented here rather than left to be discovered).
@MainActor
struct LibraryView: View {
    let environment: AppEnvironment
    /// When set (iPad), tapping a meeting calls this instead of pushing —
    /// see `TodayView.onSelectMeeting`'s doc comment for the full reasoning.
    /// Brain Dumps/Notes always push within Library's own `NavigationStack`
    /// regardless of platform — neither has an iPad detail-column surface
    /// yet (`NSP-155`'s own scope is the *active-recording* case; browsing
    /// a completed one from Library is this same gap, deferred alongside it).
    var onSelectMeeting: ((MeetingID) -> Void)?

    /// A coarse grouping of `MeetingState` — the full 19-case vocabulary
    /// isn't a useful filter surface, but "what stage is this at" is.
    private enum StateFilter: String, CaseIterable, Identifiable {
        case needsReview = "Needs review"
        case inProgress = "Recording/Processing"
        case approved = "Approved"
        case archived = "Archived"

        var id: String { rawValue }

        func matches(_ state: MeetingState) -> Bool {
            switch self {
            case .needsReview: return state == .readyForReview || state == .partialFailure
            case .inProgress:
                return [.arming, .recording, .paused, .interrupted, .finalizing, .processing]
                    .contains(state)
            case .approved: return state == .approved || state == .edited || state == .shared || state == .savedRaw
            case .archived: return state == .archived
            }
        }
    }

    @State private var meetings: [Meeting] = []
    @State private var brainDumps: [BrainDump] = []
    @State private var notes: [Note] = []
    @State private var searchText = ""
    @State private var activeFilters: Set<StateFilter> = []
    @State private var loadError: String?

    private struct DayGroup: Identifiable {
        let day: Date
        let items: [LibraryItem]
        var id: Date { day }
    }

    private var allItems: [LibraryItem] {
        meetings.map(LibraryItem.meeting) + brainDumps.map(LibraryItem.brainDump) + notes.map(LibraryItem.note)
    }

    private var filteredItems: [LibraryItem] {
        var result = allItems.sorted { $0.startedAt > $1.startedAt }
        if !searchText.isEmpty {
            result = result.filter { $0.matchesSearch(searchText) }
        }
        if !activeFilters.isEmpty {
            result = result.filter { item in activeFilters.contains { $0.matches(item.lifecycleState) } }
        }
        return result
    }

    /// Newest day first, each day's own items newest first — same
    /// "most recent activity first" ordering `filteredItems` already used,
    /// just with a day boundary drawn through it.
    private var groupedItems: [DayGroup] {
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: filteredItems) { calendar.startOfDay(for: $0.startedAt) }
        return byDay.keys.sorted(by: >).map { day in DayGroup(day: day, items: byDay[day, default: []]) }
    }

    private func dayLabel(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    var body: some View {
        NavigationStack {
            Group {
                if let loadError {
                    ContentUnavailableView(
                        "Couldn't load Library", systemImage: "exclamationmark.triangle", description: Text(loadError))
                } else if allItems.isEmpty {
                    ContentUnavailableView(
                        "Nothing yet", systemImage: "list.bullet",
                        description: Text("Recordings, brain dumps, and notes you start from Today will show up here."))
                } else if filteredItems.isEmpty {
                    emptyFilteredState
                } else {
                    libraryList
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: MeetingID.self) { meetingID in
                MeetingDetailView(meetingID: meetingID, environment: environment)
            }
            .navigationDestination(for: BrainDumpID.self) { brainDumpID in
                BrainDumpDetailView(brainDumpID: brainDumpID, environment: environment)
            }
            .navigationDestination(for: NoteID.self) { noteID in
                NoteDetailView(noteID: noteID, environment: environment)
            }
            .searchable(text: $searchText, prompt: "Search Library")
            .task { await loadAll() }
            .refreshable { await loadAll() }
        }
    }

    private var libraryList: some View {
        List {
            filterChips
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            ForEach(groupedItems) { group in
                Section {
                    ForEach(group.items) { item in
                        libraryRow(for: item)
                            .listRowInsets(
                                EdgeInsets(
                                    top: NSPSpacing.extraSmall, leading: NSPSpacing.large,
                                    bottom: NSPSpacing.extraSmall, trailing: NSPSpacing.large)
                            )
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                } header: {
                    Text(dayLabel(group.day))
                        .font(Typo.ui(11, .extrabold, relativeTo: .caption2))
                        .tracking(0.14 * 11)
                        .foregroundStyle(Palette.textQuaternary)
                        .padding(.leading, NSPSpacing.large)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.canvas)
    }

    @ViewBuilder
    private func libraryRow(for item: LibraryItem) -> some View {
        switch item {
        case .meeting(let meeting):
            meetingLink(meeting.meetingID) {
                MeetingRow(meeting: meeting, onDelete: { Task { await deleteMeeting(meeting.meetingID) } })
                    .nspCard()
            }
        case .brainDump(let brainDump):
            NavigationLink(value: brainDump.brainDumpID) {
                BrainDumpRow(brainDump: brainDump, onDelete: { Task { await deleteBrainDump(brainDump.brainDumpID) } })
                    .nspCard()
            }
            .buttonStyle(.plain)
        case .note(let note):
            NavigationLink(value: note.noteID) {
                NoteRow(note: note, onDelete: { Task { await deleteNote(note.noteID) } })
                    .nspCard()
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var emptyFilteredState: some View {
        if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            ContentUnavailableView {
                Label("Nothing matches these filters", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Clear filters to see everything.")
            } actions: {
                Button("Clear filters") { activeFilters.removeAll() }
            }
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: NSPSpacing.small) {
                ForEach(StateFilter.allCases) { filter in
                    let isSelected = activeFilters.contains(filter)
                    Button {
                        if isSelected {
                            activeFilters.remove(filter)
                        } else {
                            activeFilters.insert(filter)
                        }
                    } label: {
                        Text(filter.rawValue)
                            .font(Typo.ui(11.5, .semibold))
                            .padding(.horizontal, NSPSpacing.medium)
                            .padding(.vertical, NSPSpacing.small)
                            .background(isSelected ? Palette.accent.background : Palette.fill)
                            .foregroundStyle(isSelected ? Palette.accent.foreground : Palette.textPrimary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, NSPSpacing.extraSmall)
        }
    }

    @ViewBuilder
    private func meetingLink<Label: View>(_ meetingID: MeetingID, @ViewBuilder label: () -> Label) -> some View {
        if let onSelectMeeting {
            Button {
                onSelectMeeting(meetingID)
            } label: {
                label()
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: meetingID) { label() }
                .buttonStyle(.plain)
        }
    }

    private func loadAll() async {
        guard let workspaceID = environment.defaultPolicy?.workspaceID else { return }
        do {
            async let fetchedMeetings = environment.meetingRepository.fetchAll(
                workspaceID: workspaceID, includeDeleted: false)
            async let fetchedBrainDumps = environment.brainDumpRepository.fetchAll(
                workspaceID: workspaceID, includeDeleted: false)
            async let fetchedNotes = environment.noteRepository.fetchAll(
                workspaceID: workspaceID, includeDeleted: false)
            meetings = try await fetchedMeetings
            brainDumps = try await fetchedBrainDumps
            notes = try await fetchedNotes
        } catch {
            loadError = "\(error)"
        }
    }

    private func deleteMeeting(_ meetingID: MeetingID) async {
        do {
            try await environment.deleteMeeting(meetingID)
            await loadAll()
        } catch {
            loadError = "\(error)"
        }
    }

    private func deleteBrainDump(_ brainDumpID: BrainDumpID) async {
        do {
            try await environment.deleteBrainDump(brainDumpID)
            await loadAll()
        } catch {
            loadError = "\(error)"
        }
    }

    private func deleteNote(_ noteID: NoteID) async {
        do {
            try await environment.deleteNote(noteID)
            await loadAll()
        } catch {
            loadError = "\(error)"
        }
    }
}

/// One Library row's worth of shared surface — grouping-by-day, search, and
/// state-filtering all operate on this rather than three separate lists.
private enum LibraryItem: Identifiable {
    case meeting(Meeting)
    case brainDump(BrainDump)
    case note(Note)

    var id: String {
        switch self {
        case .meeting(let meeting): return meeting.meetingID.rawValue.uuidString
        case .brainDump(let brainDump): return brainDump.brainDumpID.rawValue.uuidString
        case .note(let note): return note.noteID.rawValue.uuidString
        }
    }

    var startedAt: Date {
        switch self {
        case .meeting(let meeting): return meeting.startedAt
        case .brainDump(let brainDump): return brainDump.startedAt
        case .note(let note): return note.startedAt
        }
    }

    var lifecycleState: MeetingState {
        switch self {
        case .meeting(let meeting): return meeting.lifecycleState
        case .brainDump(let brainDump): return brainDump.lifecycleState
        case .note(let note): return note.lifecycleState
        }
    }

    /// A Brain Dump has no title of its own to search — "Brain Dump" is the
    /// literal label its row always shows, so that's what search matches
    /// against instead.
    func matchesSearch(_ text: String) -> Bool {
        switch self {
        case .meeting(let meeting): return meeting.title.localizedCaseInsensitiveContains(text)
        case .brainDump: return "Brain Dump".localizedCaseInsensitiveContains(text)
        case .note(let note): return note.title.localizedCaseInsensitiveContains(text)
        }
    }
}

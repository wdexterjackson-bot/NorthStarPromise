import NSPCore
import NSPDesignSystem
import SwiftUI

/// docs/07 §4's Library screen: search, filter, sort, saved searches, and
/// paged rows that never load transcripts. Filter chips cover lifecycle
/// state (the most useful axis given nothing generates actions or owners
/// yet); date/workspace/`captureMode`/has-actions/has-unresolved-owner/
/// `excludedFromMemory` chips and saved searches are a follow-up, not a
/// silent scope cut (documented here rather than left to be discovered).
@MainActor
struct LibraryView: View {
    let environment: AppEnvironment
    /// When set (iPad), tapping a meeting calls this instead of pushing —
    /// see `TodayView.onSelectMeeting`'s doc comment for the full reasoning.
    var onSelectMeeting: ((MeetingID) -> Void)?

    /// A coarse grouping of `MeetingState` — the full 19-case vocabulary
    /// isn't a useful filter surface, but "what stage is this meeting at"
    /// is.
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
    @State private var searchText = ""
    @State private var activeFilters: Set<StateFilter> = []
    @State private var loadError: String?

    private var filteredMeetings: [Meeting] {
        var result = meetings.sorted { $0.startedAt > $1.startedAt }
        if !searchText.isEmpty {
            result = result.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
        if !activeFilters.isEmpty {
            result = result.filter { meeting in activeFilters.contains { $0.matches(meeting.lifecycleState) } }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            Group {
                if let loadError {
                    ContentUnavailableView(
                        "Couldn't load meetings", systemImage: "exclamationmark.triangle", description: Text(loadError))
                } else if meetings.isEmpty {
                    ContentUnavailableView(
                        "No meetings yet", systemImage: "list.bullet",
                        description: Text("Recordings you start from Today will show up here."))
                } else if filteredMeetings.isEmpty {
                    emptyFilteredState
                } else {
                    List {
                        filterChips
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        ForEach(filteredMeetings) { meeting in
                            meetingLink(meeting.meetingID) {
                                MeetingRow(meeting: meeting).nspCard()
                            }
                            .listRowInsets(
                                EdgeInsets(
                                    top: NSPSpacing.extraSmall, leading: NSPSpacing.large,
                                    bottom: NSPSpacing.extraSmall,
                                    trailing: NSPSpacing.large)
                            )
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(NSPColor.background)
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: MeetingID.self) { meetingID in
                MeetingDetailView(meetingID: meetingID, environment: environment)
            }
            .searchable(text: $searchText, prompt: "Search meetings")
            .task { await loadMeetings() }
            .refreshable { await loadMeetings() }
        }
    }

    @ViewBuilder
    private var emptyFilteredState: some View {
        if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            ContentUnavailableView {
                Label("No meetings match these filters", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Clear filters to see every meeting.")
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
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, NSPSpacing.medium)
                            .padding(.vertical, NSPSpacing.small)
                            .background(isSelected ? NSPColor.accent.opacity(0.2) : NSPColor.secondaryBackground)
                            .foregroundStyle(isSelected ? NSPColor.accent : NSPColor.primaryText)
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
        }
    }

    private func loadMeetings() async {
        guard let workspaceID = environment.defaultPolicy?.workspaceID else { return }
        do {
            meetings = try await environment.meetingRepository.fetchAll(workspaceID: workspaceID, includeDeleted: false)
        } catch {
            loadError = "\(error)"
        }
    }
}

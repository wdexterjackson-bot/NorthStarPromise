import NSPCore
import SwiftUI

/// docs/07 §4's Library screen: search, filter, sort, saved searches, and
/// paged rows that never load transcripts. Filter chips and saved searches
/// aren't built yet — search-by-title and newest-first sort are the v1
/// slice; the rest is a follow-up, not a silent scope cut (documented
/// here rather than left to be discovered).
@MainActor
struct LibraryView: View {
    let environment: AppEnvironment

    @State private var meetings: [Meeting] = []
    @State private var searchText = ""
    @State private var loadError: String?

    private var filteredMeetings: [Meeting] {
        let sorted = meetings.sorted { $0.startedAt > $1.startedAt }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
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
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List(filteredMeetings) { meeting in
                        NavigationLink(value: meeting.meetingID) {
                            MeetingRow(meeting: meeting)
                        }
                    }
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

    private func loadMeetings() async {
        guard let workspaceID = environment.defaultPolicy?.workspaceID else { return }
        do {
            meetings = try await environment.meetingRepository.fetchAll(workspaceID: workspaceID, includeDeleted: false)
        } catch {
            loadError = "\(error)"
        }
    }
}

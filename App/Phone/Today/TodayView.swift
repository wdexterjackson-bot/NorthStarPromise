import NSPCore
import NSPDesignSystem
import SwiftUI

/// docs/07 §4: "Sections in fixed order: Now (active session card, or
/// nothing), Needs review, Upcoming, Attention." Sections with nothing to
/// show are simply absent — that's still the fixed order, just with gaps
/// (docs/07 §11: correct empty states, never invented content).
@MainActor
struct TodayView: View {
    let environment: AppEnvironment
    let session: RecordingSession

    @State private var meetings: [Meeting] = []
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            List {
                nowSection
                needsReviewSection
            }
            .navigationTitle("Today")
            .navigationDestination(for: MeetingID.self) { meetingID in
                MeetingDetailView(meetingID: meetingID, environment: environment)
            }
            .task { await loadMeetings() }
            .refreshable { await loadMeetings() }
        }
    }

    @ViewBuilder
    private var nowSection: some View {
        Section("Now") {
            switch session.state {
            case .idle:
                Button {
                    Task { await session.start() }
                } label: {
                    Label("Start Recording", systemImage: "record.circle")
                }
            case .arming:
                HStack(spacing: NSPSpacing.small) {
                    ProgressView()
                    Text("Preparing…")
                }
            case .recording, .paused:
                ActiveSessionCard(session: session)
            case .finalizing:
                HStack(spacing: NSPSpacing.small) {
                    ProgressView()
                    Text("Finishing up…")
                }
            case .failed(let message):
                VStack(alignment: .leading, spacing: NSPSpacing.small) {
                    NSPStatusBadge(
                        symbolName: "exclamationmark.triangle.fill", label: "Couldn't record",
                        tint: NSPColor.statusDanger)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(NSPColor.secondaryText)
                    Button("Try again") { session.dismissFailure() }
                }
            }
        }
    }

    @ViewBuilder
    private var needsReviewSection: some View {
        let needsReview = meetings.filter {
            $0.lifecycleState == .readyForReview || $0.lifecycleState == .partialFailure
        }
        if !needsReview.isEmpty {
            Section("Needs review") {
                ForEach(needsReview) { meeting in
                    NavigationLink(value: meeting.meetingID) {
                        MeetingRow(meeting: meeting)
                    }
                }
            }
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

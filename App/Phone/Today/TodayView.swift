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
            ScrollView {
                VStack(alignment: .leading, spacing: NSPSpacing.extraLarge) {
                    if let loadError {
                        Text(loadError).font(.caption).foregroundStyle(NSPColor.statusDanger)
                    }
                    nowSection
                    needsReviewSection
                }
                .padding(NSPSpacing.large)
            }
            .background(NSPColor.background)
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
        switch session.state {
        case .idle:
            startRecordingCard
        case .arming:
            centeredStatusCard(message: "Preparing…")
        case .recording, .paused:
            ActiveSessionCard(session: session)
        case .finalizing:
            centeredStatusCard(message: "Finishing up…")
        case .failed(let message):
            VStack(alignment: .leading, spacing: NSPSpacing.medium) {
                NSPStatusBadge(
                    symbolName: "exclamationmark.triangle.fill", label: "Couldn't record", tint: NSPColor.statusDanger)
                Text(message).font(.callout).foregroundStyle(NSPColor.secondaryText)
                Button("Try again") { session.dismissFailure() }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .nspCard()
        }
    }

    private var startRecordingCard: some View {
        Button {
            Task { await session.start() }
        } label: {
            VStack(spacing: NSPSpacing.medium) {
                ZStack {
                    Circle().fill(Color.red.gradient).frame(width: 88, height: 88)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(spacing: 2) {
                    Text("Start Recording").font(.title3.weight(.semibold))
                    Text("Capture audio on this iPhone")
                        .font(.caption)
                        .foregroundStyle(NSPColor.secondaryText)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, NSPSpacing.extraLarge)
        }
        .buttonStyle(.plain)
        .nspCard()
    }

    private func centeredStatusCard(message: String) -> some View {
        HStack(spacing: NSPSpacing.medium) {
            ProgressView()
            Text(message).font(.callout).foregroundStyle(NSPColor.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NSPSpacing.large)
        .nspCard()
    }

    @ViewBuilder
    private var needsReviewSection: some View {
        let needsReview = meetings.filter {
            $0.lifecycleState == .readyForReview || $0.lifecycleState == .partialFailure
        }
        if !needsReview.isEmpty {
            VStack(alignment: .leading, spacing: NSPSpacing.medium) {
                Text("Needs Review")
                    .font(.title3.weight(.bold))
                ForEach(needsReview) { meeting in
                    NavigationLink(value: meeting.meetingID) {
                        MeetingRow(meeting: meeting).nspCard()
                    }
                    .buttonStyle(.plain)
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

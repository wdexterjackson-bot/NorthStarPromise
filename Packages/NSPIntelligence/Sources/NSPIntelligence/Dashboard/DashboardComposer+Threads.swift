import Foundation
import NSPCore
import NSPPersistence

/// Thread-derivation helpers, split out of `DashboardComposer.swift` purely
/// to stay under this repo's 250-line type-body budget — not a meaningful
/// behavioral boundary, same reasoning `RecordingSessionMarkers.swift`'s own
/// split documents.
extension DashboardComposer {
    /// `deriveThreadStatuses`'s own inputs, bundled purely to keep its
    /// signature under the 5-parameter budget.
    struct ThreadStatusInputs {
        let allMeetings: [Meeting]
        let meetingIDsByThread: [NSPThreadID: Set<MeetingID>]
        let openActions: [Action]
        let allDecisions: [Decision]
    }

    /// The spec's non-ML `NSPThreadStatus` rules (§3.2), recomputed here
    /// from data already in memory rather than stored back to the
    /// database — this composer only reads. A user-closed thread is never
    /// overridden; every other thread gets today's freshest status.
    static func deriveThreadStatuses(
        threads: [NSPThread], inputs: ThreadStatusInputs, now: Date
    ) -> [NSPThreadID: NSPThreadStatus] {
        var result: [NSPThreadID: NSPThreadStatus] = [:]
        for thread in threads where thread.status != .closed {
            let meetingIDs = inputs.meetingIDsByThread[thread.threadID] ?? []
            // A thread-tagged freestanding action/decision counts toward its
            // thread's status even with no meeting of its own — a
            // commitment's `threadID` is independent of `meetingID`
            // (`Action`'s own doc comment).
            let threadActions = inputs.openActions.filter {
                $0.threadID == thread.threadID || $0.meetingID.map { meetingIDs.contains($0) } == true
            }
            let threadDecisions = inputs.allDecisions.filter {
                ($0.threadID == thread.threadID || meetingIDs.contains($0.meetingID))
                    && openDecisionStatuses.contains($0.status)
            }
            let hasOverdueOwed = threadActions.contains { $0.direction == .iOwe && age($0, now: now) > 0 }
            let hasDecisionDue = threadDecisions.contains {
                $0.deferCount >= 2 || ($0.decideBy.map { now.timeIntervalSince($0) > -5 * 86400 } ?? false)
            }
            let lastMeeting = inputs.allMeetings.filter { meetingIDs.contains($0.meetingID) }.map(\.startedAt).max()
            let isDormant =
                (lastMeeting.map { now.timeIntervalSince($0) > 30 * 86400 } ?? false)
                && (!threadActions.isEmpty || !threadDecisions.isEmpty)

            if hasOverdueOwed {
                result[thread.threadID] = .atRisk
            } else if hasDecisionDue {
                result[thread.threadID] = .decisionDue
            } else if isDormant {
                result[thread.threadID] = .dormant
            } else {
                result[thread.threadID] = .onTrack
            }
        }
        return result
    }

    static func makeThreadCards(
        threads: [NSPThread], meetingIDsByThread: [NSPThreadID: Set<MeetingID>],
        derivedStatuses: [NSPThreadID: NSPThreadStatus]
    ) -> [ThreadCard] {
        let ranked = threads.filter { $0.status != .closed }.sorted { $0.lastTouchedAt > $1.lastTouchedAt }
        return ranked.prefix(3).map { thread in
            let meetingCount = meetingIDsByThread[thread.threadID]?.count ?? 0
            return ThreadCard(
                threadID: thread.threadID, name: thread.title, colorSlot: thread.colorSlot,
                status: derivedStatuses[thread.threadID] ?? thread.status, meetingCount: meetingCount,
                sinceDate: thread.createdAt, tensionSentence: nil)
        }
    }

    /// Inverts thread→meetings into meeting→threads, ranked
    /// most-recently-touched-first — the tie-break every single-thread-
    /// badge spot in `DashboardComposer.swift` (`makeThreadRef`,
    /// `makeCapturedToday`) uses to pick one thread for a meeting that may
    /// now belong to several.
    static func invertAndRank(
        _ meetingIDsByThread: [NSPThreadID: Set<MeetingID>], threadsByID: [NSPThreadID: NSPThread]
    ) -> [MeetingID: [NSPThreadID]] {
        var result: [MeetingID: [NSPThreadID]] = [:]
        for (threadID, meetingIDs) in meetingIDsByThread {
            for meetingID in meetingIDs {
                result[meetingID, default: []].append(threadID)
            }
        }
        for meetingID in result.keys {
            result[meetingID]?.sort { lhs, rhs in
                let lhsTouch = threadsByID[lhs]?.lastTouchedAt ?? .distantPast
                let rhsTouch = threadsByID[rhs]?.lastTouchedAt ?? .distantPast
                return lhsTouch > rhsTouch
            }
        }
        return result
    }
}

import Foundation
import NSPCore
import NSPPersistence

/// A thread that's gone quiet — no meeting, decision, or action touch in
/// 14+ days.
public struct QuietThreadEntry: Identifiable, Equatable, Sendable {
    public var id: NSPThreadID { threadID }
    public let threadID: NSPThreadID
    public let title: String
    public let quietDays: Int

    public init(threadID: NSPThreadID, title: String, quietDays: Int) {
        self.threadID = threadID
        self.title = title
        self.quietDays = quietDays
    }
}

/// Someone this workspace owes something to that's been open 7+ days —
/// "people not followed up with."
public struct OverdueFollowUpEntry: Identifiable, Equatable, Sendable {
    public var id: PersonID { personID }
    public let personID: PersonID
    public let personName: String
    public let openCount: Int

    public init(personID: PersonID, personName: String, openCount: Int) {
        self.personID = personID
        self.personName = personName
        self.openCount = openCount
    }
}

/// The Monday-morning brief "The Spine" recommendation calls for
/// (2026-08-22) — a moment that arrives, not a section you have to
/// remember to check. Composed from data that already exists: no new
/// infrastructure, just `RelationshipGraph` plus a delivery moment
/// (`WeeklyBriefScheduler`'s local notification, `MyWorkView`'s brief
/// card). Default-on for every workspace.
public struct WeeklyBrief: Sendable, Equatable {
    public let weekOf: Date
    public let quietThreads: [QuietThreadEntry]
    public let overdueFollowUps: [OverdueFollowUpEntry]
    public let decisionsLastWeek: [Decision]
    public let meetingsThisWeek: Int

    public init(
        weekOf: Date, quietThreads: [QuietThreadEntry], overdueFollowUps: [OverdueFollowUpEntry],
        decisionsLastWeek: [Decision], meetingsThisWeek: Int
    ) {
        self.weekOf = weekOf
        self.quietThreads = quietThreads
        self.overdueFollowUps = overdueFollowUps
        self.decisionsLastWeek = decisionsLastWeek
        self.meetingsThisWeek = meetingsThisWeek
    }

    /// A one-line summary for a notification body — "3 threads gone quiet,
    /// 2 people waiting, 4 meetings this week."
    public var summary: String {
        var parts: [String] = []
        if !quietThreads.isEmpty {
            parts.append("\(quietThreads.count) thread\(quietThreads.count == 1 ? "" : "s") gone quiet")
        }
        if !overdueFollowUps.isEmpty {
            parts.append("\(overdueFollowUps.count) people waiting")
        }
        parts.append("\(meetingsThisWeek) meeting\(meetingsThisWeek == 1 ? "" : "s") this week")
        return parts.joined(separator: " · ")
    }
}

/// The repositories `WeeklyBriefComposer.compose` reads from — its own
/// bundle rather than reusing `DashboardRepositories`, since it needs
/// `PersonRepository` (to name who a follow-up is owed to) and nothing
/// else in this package constructs `DashboardRepositories` with that field.
public struct WeeklyBriefRepositories: Sendable {
    public let meeting: any MeetingRepository
    public let action: any ActionRepository
    public let decision: any DecisionRepository
    public let thread: any NSPThreadRepository
    public let person: any PersonRepository

    public init(
        meeting: any MeetingRepository, action: any ActionRepository, decision: any DecisionRepository,
        thread: any NSPThreadRepository, person: any PersonRepository
    ) {
        self.meeting = meeting
        self.action = action
        self.decision = decision
        self.thread = thread
        self.person = person
    }
}

/// Pure assembly from live repositories — same "honest, no ML" shape as
/// `DashboardComposer`.
public enum WeeklyBriefComposer {
    private static let quietThreshold: TimeInterval = 14 * 86400
    private static let overdueThreshold: TimeInterval = 7 * 86400

    public static func compose(
        workspaceID: WorkspaceID, repositories: WeeklyBriefRepositories, clock: any Clock
    ) async throws -> WeeklyBrief {
        let now = clock.now()
        let calendar = Calendar.current
        let threads = try await repositories.thread.fetchAll(workspaceID: workspaceID)
        let openThreads = threads.filter { $0.status != .closed }
        let quietThreads = openThreads.compactMap { thread -> QuietThreadEntry? in
            let quietSeconds = now.timeIntervalSince(thread.lastTouchedAt)
            guard quietSeconds >= quietThreshold else { return nil }
            return QuietThreadEntry(
                threadID: thread.threadID, title: thread.title, quietDays: Int(quietSeconds / 86400))
        }
        .sorted { $0.quietDays > $1.quietDays }

        let allActions = try await repositories.action.fetchAll(workspaceID: workspaceID)
        let openIOweActions = allActions.filter {
            ProjectOpenStatusesShared.set.contains($0.status) && $0.direction == .iOwe
        }
        var overdueByPerson: [PersonID: Int] = [:]
        for action in openIOweActions {
            guard let counterpartyID = action.counterpartyID else { continue }
            let dueDate: Date?
            switch action.date {
            case .explicit(let date), .inferred(let date): dueDate = date
            case .unresolved: dueDate = nil
            }
            guard let dueDate, now.timeIntervalSince(dueDate) >= overdueThreshold else { continue }
            overdueByPerson[counterpartyID, default: 0] += 1
        }
        var overdueFollowUps: [OverdueFollowUpEntry] = []
        for (personID, count) in overdueByPerson {
            guard let person = try await repositories.person.find(personID) else { continue }
            overdueFollowUps.append(OverdueFollowUpEntry(personID: personID, personName: person.name, openCount: count))
        }
        overdueFollowUps.sort { $0.openCount > $1.openCount }

        let allDecisions = try await repositories.decision.fetchAll(workspaceID: workspaceID)
        let allMeetings = try await repositories.meeting.fetchAll(workspaceID: workspaceID, includeDeleted: false)
        let meetingDateByID = Dictionary(uniqueKeysWithValues: allMeetings.map { ($0.meetingID, $0.startedAt) })
        let weekAgo = now.addingTimeInterval(-7 * 86400)
        let decisionsLastWeek = allDecisions.filter { decision in
            guard let date = meetingDateByID[decision.meetingID] else { return false }
            return date >= weekAgo && date <= now
        }

        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now) else {
            return WeeklyBrief(
                weekOf: now, quietThreads: quietThreads, overdueFollowUps: overdueFollowUps,
                decisionsLastWeek: decisionsLastWeek, meetingsThisWeek: 0)
        }
        let meetingsThisWeek = allMeetings.filter {
            $0.startedAt >= weekInterval.start && $0.startedAt < weekInterval.end
        }.count

        return WeeklyBrief(
            weekOf: weekInterval.start, quietThreads: quietThreads, overdueFollowUps: overdueFollowUps,
            decisionsLastWeek: decisionsLastWeek, meetingsThisWeek: meetingsThisWeek)
    }
}

/// Mirrors `DashboardComposer`'s private `openActionStatuses` — duplicated
/// rather than shared across files since that set is `private` there, not
/// `internal` (kept file-scoped intentionally so nothing outside
/// `DashboardComposer.swift` depends on its exact status list drifting
/// together silently).
enum ProjectOpenStatusesShared {
    static let set: Set<ActionStatus> = [.proposed, .confirmed, .sent, .inProgress]
}

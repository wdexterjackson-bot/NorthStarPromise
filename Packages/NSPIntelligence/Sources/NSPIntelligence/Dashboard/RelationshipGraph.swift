import Foundation
import NSPCore
import NSPPersistence

/// The repositories `RelationshipGraph` reads from — grouped the same way
/// `DashboardRepositories` is, for the same 5-parameter-budget reason.
public struct RelationshipRepositories: Sendable {
    public let meeting: any MeetingRepository
    public let action: any ActionRepository
    public let decision: any DecisionRepository
    public let thread: any NSPThreadRepository
    public let project: any ProjectRepository
    public let meetingAttendee: any MeetingAttendeeRepository
    public let threadParticipant: any ThreadParticipantRepository
    public let projectPerson: any ProjectPersonRepository

    public init(
        meeting: any MeetingRepository, action: any ActionRepository, decision: any DecisionRepository,
        thread: any NSPThreadRepository, project: any ProjectRepository,
        meetingAttendee: any MeetingAttendeeRepository, threadParticipant: any ThreadParticipantRepository,
        projectPerson: any ProjectPersonRepository
    ) {
        self.meeting = meeting
        self.action = action
        self.decision = decision
        self.thread = thread
        self.project = project
        self.meetingAttendee = meetingAttendee
        self.threadParticipant = threadParticipant
        self.projectPerson = projectPerson
    }
}

/// Everything related to one Person/Thread/Project — meetings, open work,
/// and (where the anchor isn't itself a Person) the people involved.
public struct RelationshipBundle: Sendable {
    public let meetings: [Meeting]
    public let actions: [Action]
    public let decisions: [Decision]
    public let threads: [NSPThread]
    public let projects: [Project]
    public let personIDs: [PersonID]

    public init(
        meetings: [Meeting] = [], actions: [Action] = [], decisions: [Decision] = [], threads: [NSPThread] = [],
        projects: [Project] = [], personIDs: [PersonID] = []
    ) {
        self.meetings = meetings
        self.actions = actions
        self.decisions = decisions
        self.threads = threads
        self.projects = projects
        self.personIDs = personIDs
    }
}

/// One implementation of "what's related to X" instead of one per screen
/// ("The Spine" recommendation, 2026-08-22) — `DashboardComposer`,
/// `PersonDetailView`, and every future Thread/Project page call these
/// three functions instead of each writing their own joins across
/// `Meeting`/`Action`/`Decision`/`Thread`/`Person`/`Project`. Lives beside
/// `DashboardComposer` (same package, same "assembles from live
/// repositories, no ML, no network" honesty).
public enum RelationshipGraph {
    public static func everything(
        tiedToPerson personID: PersonID, repositories: RelationshipRepositories
    ) async throws -> RelationshipBundle {
        let meetingIDs = try await repositories.meetingAttendee.fetchMeetingIDs(for: personID)
        var meetings: [Meeting] = []
        var actions: [Action] = []
        var decisions: [Decision] = []
        for meetingID in meetingIDs {
            if let meeting = try await repositories.meeting.find(meetingID) { meetings.append(meeting) }
            actions.append(contentsOf: try await repositories.action.fetchAll(meetingID: meetingID))
            decisions.append(contentsOf: try await repositories.decision.fetchAll(meetingID: meetingID))
        }
        let byCounterparty = try await repositories.action.fetchAll(counterpartyID: personID)
        actions = dedupeActions(actions + byCounterparty)

        let threadIDs = try await repositories.threadParticipant.fetchThreadIDs(for: personID)
        var threads: [NSPThread] = []
        for threadID in threadIDs {
            if let thread = try await repositories.thread.find(threadID) { threads.append(thread) }
        }
        let projectIDs = try await repositories.projectPerson.fetchProjectIDs(for: personID)
        var projects: [Project] = []
        for projectID in projectIDs {
            if let project = try await repositories.project.find(projectID) { projects.append(project) }
        }

        return RelationshipBundle(
            meetings: meetings, actions: actions, decisions: decisions, threads: threads, projects: projects)
    }

    public static func everything(
        tiedToThread threadID: NSPThreadID, repositories: RelationshipRepositories
    ) async throws -> RelationshipBundle {
        let meetingIDs = try await repositories.thread.fetchMeetingIDs(for: threadID)
        var meetings: [Meeting] = []
        var actions: [Action] = []
        var decisions: [Decision] = []
        for meetingID in meetingIDs {
            if let meeting = try await repositories.meeting.find(meetingID) { meetings.append(meeting) }
            actions.append(contentsOf: try await repositories.action.fetchAll(meetingID: meetingID))
            decisions.append(contentsOf: try await repositories.decision.fetchAll(meetingID: meetingID))
        }
        let personIDs = Array(try await repositories.threadParticipant.fetchParticipantIDs(for: threadID))
        return RelationshipBundle(
            meetings: meetings, actions: dedupeActions(actions), decisions: decisions, personIDs: personIDs)
    }

    public static func everything(
        tiedToProject projectID: ProjectID, repositories: RelationshipRepositories
    ) async throws -> RelationshipBundle {
        let meetingIDs = try await repositories.project.fetchMeetingIDs(for: projectID)
        var meetings: [Meeting] = []
        var actions: [Action] = []
        var decisions: [Decision] = []
        for meetingID in meetingIDs {
            if let meeting = try await repositories.meeting.find(meetingID) { meetings.append(meeting) }
            actions.append(contentsOf: try await repositories.action.fetchAll(meetingID: meetingID))
            decisions.append(contentsOf: try await repositories.decision.fetchAll(meetingID: meetingID))
        }
        let personIDs = Array(try await repositories.projectPerson.fetchPersonIDs(for: projectID))
        return RelationshipBundle(
            meetings: meetings, actions: dedupeActions(actions), decisions: decisions, personIDs: personIDs)
    }

    private static func dedupeActions(_ actions: [Action]) -> [Action] {
        var seen = Set<ActionID>()
        return actions.filter { seen.insert($0.actionID).inserted }
    }
}

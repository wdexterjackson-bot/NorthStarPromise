import NSPActions
import NSPCore
import Observation

/// Drives "The First Hour" wizard — the skippable, resumable setup flow
/// that seeds `Person`/`NSPThread`/`Project` rows the way a human assistant
/// would ask about them, rather than a form. Every step commits to its
/// repository the moment it's answered (no in-memory draft waiting on a
/// final "Save") so a force-quit mid-wizard never loses an answer —
/// `Policy.onboardingLastStepIndex` is what lets a relaunch resume exactly
/// where the session left off. Thin by design (`CLAUDE.md` §3): every call
/// here is a direct pass-through to a repository already tested in its own
/// package; nothing here is business logic in its own right.
@MainActor
@Observable
public final class GettingStartedCoordinator {
    /// Order matters — this *is* `Policy.onboardingLastStepIndex`'s
    /// encoding (`rawValue`), so reordering cases silently changes what an
    /// already-in-progress workspace resumes on. Append, never reorder.
    public enum Step: Int, CaseIterable {
        case welcome, identity, threads, people, calendar, recordingPrefs, ambient, sync, review

        public var title: String {
            switch self {
            case .welcome: "Welcome"
            case .identity: "Who You Are"
            case .threads: "What's On Your Plate"
            case .people: "Who's Important"
            case .calendar: "Your Calendar"
            case .recordingPrefs: "How I Record"
            case .ambient: "Exercise Mode"
            case .sync: "Keeping Devices in Sync"
            case .review: "Review & Finish"
            }
        }
    }

    public let environment: AppEnvironment
    public private(set) var currentStep: Step

    /// What this session has created so far — shown back verbatim on the
    /// Review step, and available to `.people` for "attach to a Thread you
    /// just told me about" without a second database round trip.
    public private(set) var createdThreads: [NSPThread] = []
    public private(set) var createdPeople: [Person] = []
    public private(set) var createdProjects: [Project] = []
    public private(set) var saveError: String?

    public init(environment: AppEnvironment) {
        self.environment = environment
        let policy = environment.defaultPolicy
        if policy?.onboardingState.resumesExistingSession == true,
            let resumeStep = Step(rawValue: policy?.onboardingLastStepIndex ?? 0)
        {
            self.currentStep = resumeStep
        } else {
            self.currentStep = .welcome
        }
    }

    // MARK: - Navigation

    public func advance() async {
        await markInProgress(at: currentStep)
        guard let next = Step(rawValue: currentStep.rawValue + 1) else {
            await finish()
            return
        }
        currentStep = next
        await persistStepIndex(next)
    }

    public func back() {
        guard let previous = Step(rawValue: currentStep.rawValue - 1) else { return }
        currentStep = previous
    }

    /// "Skip for now" — from any step. Distinct from `.completed`: nothing
    /// created so far is discarded (every write already committed), but
    /// `RootView` never auto-presents the wizard again either way
    /// (`OnboardingState.shouldAutoPresent`).
    public func skipEntirely() async {
        guard var policy = environment.defaultPolicy else { return }
        policy.onboardingState = .skipped
        await save(policy)
    }

    public func finish() async {
        guard var policy = environment.defaultPolicy else { return }
        policy.onboardingState = .completed
        await save(policy)
    }

    private func markInProgress(at step: Step) async {
        guard var policy = environment.defaultPolicy, policy.onboardingState != .inProgress else { return }
        policy.onboardingState = .inProgress
        policy.onboardingLastStepIndex = step.rawValue
        await save(policy)
    }

    private func persistStepIndex(_ step: Step) async {
        guard var policy = environment.defaultPolicy else { return }
        policy.onboardingLastStepIndex = step.rawValue
        await save(policy)
    }

    private func save(_ policy: Policy) async {
        do {
            try await environment.policyRepository.update(policy, at: environment.clock.now())
            environment.refreshDefaultPolicy(policy)
        } catch {
            saveError = "\(error)"
        }
    }

    // MARK: - Step 1: identity

    /// Renames the self-`Person` (`AppEnvironment.bootstrap()`'s
    /// placeholder "You") and the workspace — the wizard's first real
    /// write. Empty fields leave the existing placeholder alone rather
    /// than overwriting it with blank text.
    public func saveIdentity(name: String, role: String, organization: String, workspaceName: String) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRole = role.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOrg = organization.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWorkspace = workspaceName.trimmingCharacters(in: .whitespacesAndNewlines)

        if let selfPersonID = environment.selfPersonID, var person = try? await environment.personRepository.find(selfPersonID) {
            if !trimmedName.isEmpty { person.name = trimmedName }
            if !trimmedRole.isEmpty { person.role = trimmedRole }
            if !trimmedOrg.isEmpty { person.organization = trimmedOrg }
            do {
                try await environment.personRepository.update(person, at: environment.clock.now())
            } catch {
                saveError = "\(error)"
            }
        }

        if !trimmedWorkspace.isEmpty, let workspaceID = environment.defaultPolicy?.workspaceID {
            do {
                var workspace = try await environment.workspaceRepository.find(workspaceID)
                workspace?.name = trimmedWorkspace
                if let workspace {
                    try await environment.workspaceRepository.update(workspace, at: environment.clock.now())
                }
            } catch {
                saveError = "\(error)"
            }
        }
    }

    // MARK: - Step 2: threads ("what's on your plate")

    @discardableResult
    public func addThread(title: String, kind: ThreadKind) async -> NSPThread? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let workspaceID = environment.defaultPolicy?.workspaceID else { return nil }
        let now = environment.clock.now()
        let thread = NSPThread(
            threadID: NSPThreadID(rawValue: .init()), workspaceID: workspaceID, title: trimmed, kind: kind,
            lastTouchedAt: now, createdAt: now, updatedAt: now)
        do {
            try await environment.threadRepository.insert(thread, at: now)
            createdThreads.append(thread)
            return thread
        } catch {
            saveError = "\(error)"
            return nil
        }
    }

    public func removeThread(_ threadID: NSPThreadID) async {
        do {
            try await environment.threadRepository.delete(threadID)
            createdThreads.removeAll { $0.threadID == threadID }
        } catch {
            saveError = "\(error)"
        }
    }

    // MARK: - Step 3: people ("who's important")

    @discardableResult
    public func addPerson(name: String, tag: String, threadIDs: Set<NSPThreadID>) async -> Person? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let workspaceID = environment.defaultPolicy?.workspaceID else { return nil }
        let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        let person = Person(
            personID: PersonID(rawValue: .init()), workspaceID: workspaceID, name: trimmedName,
            tags: trimmedTag.isEmpty ? [] : [trimmedTag])
        do {
            try await environment.personRepository.insert(person, at: environment.clock.now())
            createdPeople.append(person)
            for threadID in threadIDs {
                let existing = try await environment.threadParticipantRepository.fetchParticipantIDs(for: threadID)
                try await environment.threadParticipantRepository.setParticipants(
                    for: threadID, personIDs: existing.union([person.personID]))
            }
            return person
        } catch {
            saveError = "\(error)"
            return nil
        }
    }

    // MARK: - Step 4: calendar ("your calendar")

    /// Read-only — this app never writes to the user's real calendar from
    /// this step (`EventKitCalendarEventWriter`, the one path that does,
    /// isn't called anywhere in this flow). What "import" means here is
    /// the app's own tracking layer: a `ScheduledRecording` row, exactly
    /// the same entity `CalendarEventPickerView`'s existing single-event
    /// import already creates, just multi-select and driven from the
    /// wizard. Optionally groups the selected events under a new
    /// `Project` the user names.
    public func importSelectedEvents(_ events: [CalendarEventInfo], projectName: String) async {
        var project: Project?
        let trimmedProjectName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedProjectName.isEmpty, let workspaceID = environment.defaultPolicy?.workspaceID {
            let now = environment.clock.now()
            let newProject = Project(
                projectID: ProjectID(rawValue: .init()), workspaceID: workspaceID, name: trimmedProjectName,
                createdAt: now, updatedAt: now)
            do {
                try await environment.projectRepository.insert(newProject, at: now)
                createdProjects.append(newProject)
                project = newProject
            } catch {
                saveError = "\(error)"
            }
        }

        guard let workspaceID = environment.defaultPolicy?.workspaceID else { return }
        for event in events {
            let now = environment.clock.now()
            let scheduled = ScheduledRecording(
                scheduledRecordingID: ScheduledRecordingID(rawValue: .init()), workspaceID: workspaceID,
                title: event.title.isEmpty ? "Untitled event" : event.title, scheduledStart: event.startDate,
                scheduledStop: event.endDate, calendarEventID: event.identifier, projectID: project?.projectID,
                createdAt: now, updatedAt: now)
            do {
                try await environment.scheduledRecordingRepository.insert(scheduled, at: now)
            } catch {
                saveError = "\(error)"
            }
        }
    }
}

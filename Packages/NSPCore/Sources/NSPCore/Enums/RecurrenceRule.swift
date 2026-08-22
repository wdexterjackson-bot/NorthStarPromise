import Foundation

/// `EKWeekday`-equivalent — `.monday...sunday` rather than `Calendar`'s
/// 1...7-from-Sunday `weekday` component, since every recurrence UI element
/// (`RecurrenceConfigurationView`, NSP-158) reads and writes these as a
/// human day-of-week set, not a raw component integer. `RecurrenceExpander`
/// is the one place that bridges to `Calendar.Component.weekday`.
public enum Weekday: Int, Sendable, Hashable, Codable, CaseIterable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    /// `Calendar`'s `weekday` component uses this exact same 1...7,
    /// Sunday-first numbering, so this is a plain passthrough — kept as a
    /// named property rather than relying on `rawValue` at call sites so
    /// the bridge is explicit and grep-able.
    public var calendarComponentValue: Int { rawValue }
}

/// Outlook's "The" radio option under Monthly/Yearly ("the second Tuesday").
public enum WeekdayOrdinal: Sendable, Hashable, Codable, CaseIterable {
    case first, second, third, fourth, last
}

/// Outlook's Monthly/Yearly pattern is always one of these two radio
/// choices — "Day `N`" or "The `[ordinal]` `[weekday]`".
public enum MonthlyPattern: Sendable, Hashable, Codable {
    case dayOfMonth(Int)
    case relativeWeekday(WeekdayOrdinal, Weekday)
}

/// Every Outlook-equivalent recurrence pattern (docs/09 NSP-157). Mirrors
/// Outlook's own Daily/Weekly/Monthly/Yearly segmented choice exactly,
/// since `RecurrenceConfigurationView` (NSP-158) has to reproduce that
/// dialog. `.daily`'s `everyWeekday` flag is Outlook's "Every weekday"
/// radio option nested under Daily — a weekly Mon-Fri pattern in disguise,
/// kept on `.daily` rather than expressed as `.weekly(1, [.mon...fri])`
/// because that's where Outlook itself puts the control.
public enum RecurrenceFrequency: Sendable, Hashable, Codable {
    case daily(interval: Int, everyWeekday: Bool = false)
    case weekly(interval: Int, days: Set<Weekday>)
    case monthly(interval: Int, pattern: MonthlyPattern)
    case yearly(month: Int, pattern: MonthlyPattern)
}

/// Outlook's "Range of recurrence" end options — `.never` / "End after `N`
/// occurrences" / "End by `date`".
public enum RecurrenceEnd: Sendable, Hashable, Codable {
    case never
    case afterOccurrences(Int)
    case onDate(Date)
}

/// A recurring series' pattern, detached from any single `Meeting`/
/// `ScheduledRecording` row so many series-instances (a promoted occurrence
/// becomes its own real row, per `RecurrenceException`'s doc comment) can
/// reference the same rule by `recurrenceRuleID`. Never materializes future
/// occurrences as rows itself — `RecurrenceExpander` does that, in memory,
/// for display only.
public struct RecurrenceRule: Sendable, Hashable, Codable, Identifiable {
    public let recurrenceRuleID: RecurrenceRuleID
    public var id: RecurrenceRuleID { recurrenceRuleID }
    public let workspaceID: WorkspaceID

    public var frequency: RecurrenceFrequency
    public var end: RecurrenceEnd

    public let createdAt: Date
    public var updatedAt: Date

    public init(
        recurrenceRuleID: RecurrenceRuleID,
        workspaceID: WorkspaceID,
        frequency: RecurrenceFrequency,
        end: RecurrenceEnd = .never,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.recurrenceRuleID = recurrenceRuleID
        self.workspaceID = workspaceID
        self.frequency = frequency
        self.end = end
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// One date's departure from its series' default pattern — the standard
/// rule-plus-exceptions model every real calendar app uses (Google/Outlook/
/// Apple Calendar), rather than materializing every future occurrence as a
/// real row (a "never ends" daily standup would otherwise grow the
/// `scheduled_recording`/`meeting` table forever). `.cancelled` just
/// excludes `originalOccurrenceDate` from `RecurrenceExpander`'s output;
/// `.modified` pairs with an override row (the occurrence was actually
/// started/edited as its own real `Meeting`/`ScheduledRecording`) so the
/// virtual occurrence is replaced by that real one instead of double-shown
/// (NSP-160's dedupe).
public struct RecurrenceException: Sendable, Hashable, Codable, Identifiable {
    public enum Kind: String, Sendable, Hashable, Codable {
        case modified
        case cancelled
    }

    public let recurrenceExceptionID: RecurrenceExceptionID
    public var id: RecurrenceExceptionID { recurrenceExceptionID }
    public let recurrenceRuleID: RecurrenceRuleID

    /// The virtual occurrence date this exception replaces — matched
    /// against `RecurrenceExpander`'s output, not a real row's own date.
    public var originalOccurrenceDate: Date
    public var kind: Kind

    public var overrideMeetingID: MeetingID?
    public var overrideScheduledRecordingID: ScheduledRecordingID?

    public let createdAt: Date
    public var updatedAt: Date

    public init(
        recurrenceExceptionID: RecurrenceExceptionID,
        recurrenceRuleID: RecurrenceRuleID,
        originalOccurrenceDate: Date,
        kind: Kind,
        overrideMeetingID: MeetingID? = nil,
        overrideScheduledRecordingID: ScheduledRecordingID? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.recurrenceExceptionID = recurrenceExceptionID
        self.recurrenceRuleID = recurrenceRuleID
        self.originalOccurrenceDate = originalOccurrenceDate
        self.kind = kind
        self.overrideMeetingID = overrideMeetingID
        self.overrideScheduledRecordingID = overrideScheduledRecordingID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

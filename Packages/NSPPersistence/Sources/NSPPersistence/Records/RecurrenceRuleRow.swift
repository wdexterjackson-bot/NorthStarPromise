import Foundation
@preconcurrency import GRDB
import NSPCore

/// Mirrors the `recurrence_rule` table (NSP-157). `RecurrenceFrequency`'s
/// four cases and `RecurrenceEnd`'s three don't fit a single column each —
/// flattened into a `*_kind` discriminator plus every case's possible
/// payload columns, left `NULL` where a given kind doesn't use them. Same
/// "kind + payload" shape `MeetingRow` uses for `MeetingState.failed`.
// swiftlint:disable:next type_body_length
struct RecurrenceRuleRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "recurrence_rule"

    var recurrenceRuleID: String
    var workspaceID: String

    var frequencyKind: String
    var interval: Int?
    var everyWeekday: Bool?
    var daysOfWeek: String?
    var month: Int?
    var patternKind: String?
    var patternDayOfMonth: Int?
    var patternOrdinal: String?
    var patternWeekday: Int?

    var endKind: String
    var endOccurrences: Int?
    var endDate: Date?

    var createdAt: Date
    var updatedAt: Date
    var rowRevision: Int

    enum CodingKeys: String, CodingKey {
        case recurrenceRuleID = "recurrence_rule_id"
        case workspaceID = "workspace_id"
        case frequencyKind = "frequency_kind"
        case interval
        case everyWeekday = "every_weekday"
        case daysOfWeek = "days_of_week"
        case month
        case patternKind = "pattern_kind"
        case patternDayOfMonth = "pattern_day_of_month"
        case patternOrdinal = "pattern_ordinal"
        case patternWeekday = "pattern_weekday"
        case endKind = "end_kind"
        case endOccurrences = "end_occurrences"
        case endDate = "end_date"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case rowRevision = "row_revision"
    }

    init(rule: RecurrenceRule, createdAt: Date, updatedAt: Date, rowRevision: Int) {
        self.recurrenceRuleID = rule.recurrenceRuleID.rawValue.uuidString
        self.workspaceID = rule.workspaceID.rawValue.uuidString

        switch rule.frequency {
        case .daily(let interval, let everyWeekday):
            self.frequencyKind = "daily"
            self.interval = interval
            self.everyWeekday = everyWeekday
        case .weekly(let interval, let days):
            self.frequencyKind = "weekly"
            self.interval = interval
            self.daysOfWeek = days.map { String($0.rawValue) }.sorted().joined(separator: ",")
        case .monthly(let interval, let pattern):
            self.frequencyKind = "monthly"
            self.interval = interval
            (self.patternKind, self.patternDayOfMonth, self.patternOrdinal, self.patternWeekday) =
                Self.encode(pattern)
        case .yearly(let month, let pattern):
            self.frequencyKind = "yearly"
            self.month = month
            (self.patternKind, self.patternDayOfMonth, self.patternOrdinal, self.patternWeekday) =
                Self.encode(pattern)
        }

        switch rule.end {
        case .never:
            self.endKind = "never"
        case .afterOccurrences(let count):
            self.endKind = "afterOccurrences"
            self.endOccurrences = count
        case .onDate(let date):
            self.endKind = "onDate"
            self.endDate = date
        }

        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.rowRevision = rowRevision
    }

    private static func encode(_ pattern: MonthlyPattern) -> (
        kind: String, dayOfMonth: Int?, ordinal: String?, weekday: Int?
    ) {
        switch pattern {
        case .dayOfMonth(let day):
            return ("dayOfMonth", day, nil, nil)
        case .relativeWeekday(let ordinal, let weekday):
            return ("relativeWeekday", nil, ordinal.rawValueString, weekday.rawValue)
        }
    }

    func asDomain() throws -> RecurrenceRule {
        guard let idUUID = UUID(uuidString: recurrenceRuleID) else {
            throw PersistenceError.corruptRow(
                table: Self.databaseTableName, column: "recurrence_rule_id", value: recurrenceRuleID)
        }
        guard let workspaceUUID = UUID(uuidString: workspaceID) else {
            throw PersistenceError.corruptRow(
                table: Self.databaseTableName, column: "workspace_id", value: workspaceID)
        }

        let frequency: RecurrenceFrequency
        switch frequencyKind {
        case "daily":
            frequency = .daily(interval: interval ?? 1, everyWeekday: everyWeekday ?? false)
        case "weekly":
            let days = Set(
                (daysOfWeek ?? "").split(separator: ",").compactMap { Int($0) }.compactMap { Weekday(rawValue: $0) })
            frequency = .weekly(interval: interval ?? 1, days: days)
        case "monthly":
            frequency = .monthly(interval: interval ?? 1, pattern: try decodePattern())
        case "yearly":
            frequency = .yearly(month: month ?? 1, pattern: try decodePattern())
        default:
            throw PersistenceError.corruptRow(
                table: Self.databaseTableName, column: "frequency_kind", value: frequencyKind)
        }

        let end: RecurrenceEnd
        switch endKind {
        case "never":
            end = .never
        case "afterOccurrences":
            guard let count = endOccurrences else {
                throw PersistenceError.corruptRow(
                    table: Self.databaseTableName, column: "end_occurrences", value: "nil")
            }
            end = .afterOccurrences(count)
        case "onDate":
            guard let date = endDate else {
                throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "end_date", value: "nil")
            }
            end = .onDate(date)
        default:
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "end_kind", value: endKind)
        }

        return RecurrenceRule(
            recurrenceRuleID: RecurrenceRuleID(rawValue: idUUID), workspaceID: WorkspaceID(rawValue: workspaceUUID),
            frequency: frequency, end: end, createdAt: createdAt, updatedAt: updatedAt)
    }

    private func decodePattern() throws -> MonthlyPattern {
        switch patternKind {
        case "dayOfMonth":
            guard let day = patternDayOfMonth else {
                throw PersistenceError.corruptRow(
                    table: Self.databaseTableName, column: "pattern_day_of_month", value: "nil")
            }
            return .dayOfMonth(day)
        case "relativeWeekday":
            guard let ordinalString = patternOrdinal, let ordinal = WeekdayOrdinal(rawValueString: ordinalString),
                let weekdayValue = patternWeekday, let weekday = Weekday(rawValue: weekdayValue)
            else {
                throw PersistenceError.corruptRow(
                    table: Self.databaseTableName, column: "pattern_ordinal", value: patternOrdinal ?? "nil")
            }
            return .relativeWeekday(ordinal, weekday)
        default:
            throw PersistenceError.corruptRow(
                table: Self.databaseTableName, column: "pattern_kind", value: patternKind ?? "nil")
        }
    }
}

extension WeekdayOrdinal {
    fileprivate var rawValueString: String {
        switch self {
        case .first: return "first"
        case .second: return "second"
        case .third: return "third"
        case .fourth: return "fourth"
        case .last: return "last"
        }
    }

    fileprivate init?(rawValueString: String) {
        switch rawValueString {
        case "first": self = .first
        case "second": self = .second
        case "third": self = .third
        case "fourth": self = .fourth
        case "last": self = .last
        default: return nil
        }
    }
}

/// Mirrors the `recurrence_exception` table (NSP-157).
struct RecurrenceExceptionRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "recurrence_exception"

    var recurrenceExceptionID: String
    var recurrenceRuleID: String
    var originalOccurrenceDate: Date
    var kind: String
    var overrideMeetingID: String?
    var overrideScheduledRecordingID: String?
    var createdAt: Date
    var updatedAt: Date
    var rowRevision: Int

    enum CodingKeys: String, CodingKey {
        case recurrenceExceptionID = "recurrence_exception_id"
        case recurrenceRuleID = "recurrence_rule_id"
        case originalOccurrenceDate = "original_occurrence_date"
        case kind
        case overrideMeetingID = "override_meeting_id"
        case overrideScheduledRecordingID = "override_scheduled_recording_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case rowRevision = "row_revision"
    }

    init(exception: RecurrenceException, createdAt: Date, updatedAt: Date, rowRevision: Int) {
        self.recurrenceExceptionID = exception.recurrenceExceptionID.rawValue.uuidString
        self.recurrenceRuleID = exception.recurrenceRuleID.rawValue.uuidString
        self.originalOccurrenceDate = exception.originalOccurrenceDate
        self.kind = exception.kind.rawValue
        self.overrideMeetingID = exception.overrideMeetingID?.rawValue.uuidString
        self.overrideScheduledRecordingID = exception.overrideScheduledRecordingID?.rawValue.uuidString
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.rowRevision = rowRevision
    }

    func asDomain() throws -> RecurrenceException {
        guard let idUUID = UUID(uuidString: recurrenceExceptionID) else {
            throw PersistenceError.corruptRow(
                table: Self.databaseTableName, column: "recurrence_exception_id", value: recurrenceExceptionID)
        }
        guard let ruleUUID = UUID(uuidString: recurrenceRuleID) else {
            throw PersistenceError.corruptRow(
                table: Self.databaseTableName, column: "recurrence_rule_id", value: recurrenceRuleID)
        }
        guard let kindValue = RecurrenceException.Kind(rawValue: kind) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "kind", value: kind)
        }
        let resolvedOverrideMeetingID = try overrideMeetingID.map { string -> MeetingID in
            guard let uuid = UUID(uuidString: string) else {
                throw PersistenceError.corruptRow(
                    table: Self.databaseTableName, column: "override_meeting_id", value: string)
            }
            return MeetingID(rawValue: uuid)
        }
        let resolvedOverrideScheduledRecordingID = try overrideScheduledRecordingID.map { string -> ScheduledRecordingID in
            guard let uuid = UUID(uuidString: string) else {
                throw PersistenceError.corruptRow(
                    table: Self.databaseTableName, column: "override_scheduled_recording_id", value: string)
            }
            return ScheduledRecordingID(rawValue: uuid)
        }

        return RecurrenceException(
            recurrenceExceptionID: RecurrenceExceptionID(rawValue: idUUID),
            recurrenceRuleID: RecurrenceRuleID(rawValue: ruleUUID), originalOccurrenceDate: originalOccurrenceDate,
            kind: kindValue, overrideMeetingID: resolvedOverrideMeetingID,
            overrideScheduledRecordingID: resolvedOverrideScheduledRecordingID, createdAt: createdAt,
            updatedAt: updatedAt)
    }
}

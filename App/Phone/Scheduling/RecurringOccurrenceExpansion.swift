import Foundation
import NSPCore

/// A recurring series' occurrence within a display window that has no real
/// `Meeting`/`ScheduledRecording` row yet — `RecurrenceExpander`'s pure
/// output, rendered read-only until the user starts or skips it (NSP-160).
/// Carries just enough of the series' first real row (its "template") to
/// render an agenda/calendar row identically to a promoted one.
struct VirtualOccurrence: Identifiable {
    let recurrenceRuleID: RecurrenceRuleID
    let occurrenceDate: Date
    let title: String
    let colorSlot: Int
    let subtitle: String
    /// `true` when the template came from a `ScheduledRecording` (so
    /// "Start Event" should create a pending recording, not a bare note/
    /// reminder shell).
    let isRecordedMeeting: Bool
    let alertStyle: ScheduledRecordingAlertStyle
    let notifyLeadTime: TimeInterval
    let meetingKind: MeetingKind

    var id: String { "\(recurrenceRuleID.rawValue.uuidString)-\(occurrenceDate.timeIntervalSince1970)" }
}

/// Expands every recurring series referenced by a set of real rows into
/// virtual occurrences within a display window — the mechanism that makes
/// a recurring event actually keep showing up on future agenda/calendar
/// days, since nothing is ever materialized as a real row until started
/// (NSP-157's design). Lives at the App layer (not `NSPIntelligence`'s
/// `DashboardComposer`) because it needs `RecurrenceRuleRepository`/
/// `RecurrenceExceptionRepository`, matching how `ScheduledRecording`
/// merging already happens outside `DashboardComposer`, in
/// `PadDashboardSidebar`/`PadRootView`.
enum RecurringOccurrenceExpansion {
    private struct SeriesTemplate {
        let seriesStart: Date
        let title: String
        let colorSlot: Int
        let subtitle: String
        let isRecordedMeeting: Bool
        let alertStyle: ScheduledRecordingAlertStyle
        let notifyLeadTime: TimeInterval
        let meetingKind: MeetingKind
        var realOccurrenceKeys: Set<DateComponents>
    }

    static func expand(
        meetings: [Meeting], scheduledRecordings: [ScheduledRecording], window: ClosedRange<Date>,
        environment: AppEnvironment
    ) async -> [VirtualOccurrence] {
        let calendar = Calendar.current
        var templates: [RecurrenceRuleID: SeriesTemplate] = [:]

        for meeting in meetings {
            guard let ruleID = meeting.recurrenceRuleID else { continue }
            let subtitle: String
            switch meeting.kind {
            case .notesOnly: subtitle = "Meeting with Notes"
            case .recorded: subtitle = "Recorded Meeting"
            }
            merge(
                ruleID: ruleID, date: meeting.startedAt,
                title: meeting.isTitleSensitive || meeting.title.isEmpty ? "Untitled meeting" : meeting.title,
                colorSlot: meeting.colorSlot, subtitle: subtitle, isRecordedMeeting: false, alertStyle: .sound,
                notifyLeadTime: 0, meetingKind: meeting.kind, calendar: calendar, into: &templates)
        }
        for recording in scheduledRecordings {
            guard let ruleID = recording.recurrenceRuleID else { continue }
            merge(
                ruleID: ruleID, date: recording.scheduledStart, title: recording.title, colorSlot: recording.colorSlot,
                subtitle: "Recorded Meeting", isRecordedMeeting: true, alertStyle: recording.alertStyle,
                notifyLeadTime: recording.notifyLeadTime, meetingKind: .recorded, calendar: calendar,
                into: &templates)
        }

        var occurrences: [VirtualOccurrence] = []
        for (ruleID, template) in templates {
            guard let rule = try? await environment.recurrenceRuleRepository.find(ruleID) else { continue }
            let exceptions = (try? await environment.recurrenceExceptionRepository.fetchAll(recurrenceRuleID: ruleID)) ?? []
            let excludedKeys = Set(
                exceptions.map { minuteKey($0.originalOccurrenceDate, calendar: calendar) })
            let dates = RecurrenceExpander.occurrences(
                of: rule, seriesStart: template.seriesStart, in: window, calendar: calendar)
            for date in dates {
                let key = minuteKey(date, calendar: calendar)
                if template.realOccurrenceKeys.contains(key) || excludedKeys.contains(key) { continue }
                occurrences.append(
                    VirtualOccurrence(
                        recurrenceRuleID: ruleID, occurrenceDate: date, title: template.title,
                        colorSlot: template.colorSlot, subtitle: template.subtitle,
                        isRecordedMeeting: template.isRecordedMeeting, alertStyle: template.alertStyle,
                        notifyLeadTime: template.notifyLeadTime, meetingKind: template.meetingKind))
            }
        }
        return occurrences
    }

    // swiftlint:disable:next function_parameter_count
    private static func merge(
        ruleID: RecurrenceRuleID, date: Date, title: String, colorSlot: Int, subtitle: String,
        isRecordedMeeting: Bool, alertStyle: ScheduledRecordingAlertStyle, notifyLeadTime: TimeInterval,
        meetingKind: MeetingKind, calendar: Calendar, into templates: inout [RecurrenceRuleID: SeriesTemplate]
    ) {
        let key = minuteKey(date, calendar: calendar)
        if var existing = templates[ruleID] {
            existing.realOccurrenceKeys.insert(key)
            if date < existing.seriesStart {
                templates[ruleID] = SeriesTemplate(
                    seriesStart: date, title: title, colorSlot: colorSlot, subtitle: subtitle,
                    isRecordedMeeting: isRecordedMeeting, alertStyle: alertStyle, notifyLeadTime: notifyLeadTime,
                    meetingKind: meetingKind, realOccurrenceKeys: existing.realOccurrenceKeys)
            } else {
                templates[ruleID] = existing
            }
        } else {
            templates[ruleID] = SeriesTemplate(
                seriesStart: date, title: title, colorSlot: colorSlot, subtitle: subtitle,
                isRecordedMeeting: isRecordedMeeting, alertStyle: alertStyle, notifyLeadTime: notifyLeadTime,
                meetingKind: meetingKind, realOccurrenceKeys: [key])
        }
    }

    private static func minuteKey(_ date: Date, calendar: Calendar) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }
}

import Foundation
@preconcurrency import GRDB
import NSPCore

/// Mirrors the `scheduled_recording` table. A single-table record — unlike
/// `ActionRow`, `ScheduledRecording` has no array-valued fields needing a
/// normalized child table.
struct ScheduledRecordingRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "scheduled_recording"

    var scheduledRecordingID: String
    var workspaceID: String
    var title: String
    var scheduledStart: Date
    var scheduledStop: Date
    var status: String
    var alertStyle: String
    var notifyLeadTime: Double
    var calendarEventID: String?
    var meetingID: String?
    var projectID: String?
    var createdAt: Date
    var updatedAt: Date
    var rowRevision: Int

    enum CodingKeys: String, CodingKey {
        case scheduledRecordingID = "scheduled_recording_id"
        case workspaceID = "workspace_id"
        case title
        case scheduledStart = "scheduled_start"
        case scheduledStop = "scheduled_stop"
        case status
        case alertStyle = "alert_style"
        case notifyLeadTime = "notify_lead_time"
        case calendarEventID = "calendar_event_id"
        case meetingID = "meeting_id"
        case projectID = "project_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case rowRevision = "row_revision"
    }

    init(item: ScheduledRecording, createdAt: Date, updatedAt: Date, rowRevision: Int) {
        self.scheduledRecordingID = item.scheduledRecordingID.rawValue.uuidString
        self.workspaceID = item.workspaceID.rawValue.uuidString
        self.title = item.title
        self.scheduledStart = item.scheduledStart
        self.scheduledStop = item.scheduledStop
        self.status = item.status.rawValue
        self.alertStyle = item.alertStyle.rawValue
        self.notifyLeadTime = item.notifyLeadTime
        self.calendarEventID = item.calendarEventID
        self.meetingID = item.meetingID?.rawValue.uuidString
        self.projectID = item.projectID?.rawValue.uuidString
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.rowRevision = rowRevision
    }

    func asDomain() throws -> ScheduledRecording {
        guard let idUUID = UUID(uuidString: scheduledRecordingID) else {
            throw PersistenceError.corruptRow(
                table: Self.databaseTableName, column: "scheduled_recording_id", value: scheduledRecordingID)
        }
        guard let workspaceUUID = UUID(uuidString: workspaceID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "workspace_id", value: workspaceID)
        }
        guard let recordingStatus = ScheduledRecordingStatus(rawValue: status) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "status", value: status)
        }
        guard let recordingAlertStyle = ScheduledRecordingAlertStyle(rawValue: alertStyle) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "alert_style", value: alertStyle)
        }
        let resolvedMeetingID = try meetingID.map { string -> MeetingID in
            guard let uuid = UUID(uuidString: string) else {
                throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "meeting_id", value: string)
            }
            return MeetingID(rawValue: uuid)
        }
        let resolvedProjectID = try projectID.map { string -> ProjectID in
            guard let uuid = UUID(uuidString: string) else {
                throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "project_id", value: string)
            }
            return ProjectID(rawValue: uuid)
        }

        return ScheduledRecording(
            scheduledRecordingID: ScheduledRecordingID(rawValue: idUUID),
            workspaceID: WorkspaceID(rawValue: workspaceUUID),
            title: title, scheduledStart: scheduledStart, scheduledStop: scheduledStop, status: recordingStatus,
            alertStyle: recordingAlertStyle, notifyLeadTime: notifyLeadTime, calendarEventID: calendarEventID,
            meetingID: resolvedMeetingID, projectID: resolvedProjectID, createdAt: createdAt, updatedAt: updatedAt)
    }
}

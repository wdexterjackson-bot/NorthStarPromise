import Foundation
@preconcurrency import GRDB
import NSPCore

/// Tracks which system-suggested thread groupings the user has dismissed,
/// keyed by a stable fingerprint of the suggestion's meeting set (see
/// `NSPIntelligence`'s `ThreadSuggestionEngine.fingerprint(for:)`). This
/// package doesn't depend on `NSPIntelligence`, so the fingerprint is just
/// an opaque `String` here — computing and comparing it is the caller's
/// job.
public protocol ThreadSuggestionDismissalRepository: Sendable {
    func dismiss(fingerprint: String, workspaceID: WorkspaceID, at date: Date) async throws
    func fetchDismissedFingerprints(workspaceID: WorkspaceID) async throws -> Set<String>
}

public struct GRDBThreadSuggestionDismissalRepository: ThreadSuggestionDismissalRepository {
    private let dbWriter: any DatabaseWriter

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    public func dismiss(fingerprint: String, workspaceID: WorkspaceID, at date: Date) async throws {
        let row = DismissedThreadSuggestionRow(
            fingerprint: fingerprint, workspaceID: workspaceID.rawValue.uuidString, dismissedAt: date)
        try await dbWriter.write { db in
            try row.insert(db, onConflict: .replace)
        }
    }

    public func fetchDismissedFingerprints(workspaceID: WorkspaceID) async throws -> Set<String> {
        try await dbWriter.read { db in
            let rows =
                try DismissedThreadSuggestionRow
                .filter(Column("workspace_id") == workspaceID.rawValue.uuidString)
                .fetchAll(db)
            return Set(rows.map(\.fingerprint))
        }
    }
}

struct DismissedThreadSuggestionRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "dismissed_thread_suggestion"
    var fingerprint: String
    var workspaceID: String
    var dismissedAt: Date

    enum CodingKeys: String, CodingKey {
        case fingerprint
        case workspaceID = "workspace_id"
        case dismissedAt = "dismissed_at"
    }
}

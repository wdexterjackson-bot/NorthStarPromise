import CloudKit
import NSPCore

/// docs/02 §6, verbatim: "Custom record zone `ws-<workspaceID>` in the
/// private database."
public enum WorkspaceZone {
    public static func recordZoneID(for workspaceID: WorkspaceID) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: "ws-\(workspaceID.rawValue.uuidString)", ownerName: CKCurrentUserDefaultName)
    }
}

/// docs/02 §6, verbatim record-type names.
public enum CloudKitRecordType {
    public static let meeting = "CD_Meeting"
    public static let segment = "CD_Segment"
    public static let transcriptTurn = "CD_TranscriptTurn"
}

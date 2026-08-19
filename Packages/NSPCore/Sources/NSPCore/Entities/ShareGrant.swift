import Foundation

/// One access grant to an external or internal recipient, with revocation
/// and download controls enforced at fetch time (docs/02 §2, docs/01 §3
/// "NSPActions"/"Backend"; NSP-119…122).
public struct ShareGrant: Sendable, Hashable, Codable, Identifiable {
    public let shareGrantID: ShareGrantID
    public var id: ShareGrantID { shareGrantID }
    public let meetingID: MeetingID

    public var recipient: String
    public var role: ShareRole
    public var scope: ShareScope
    public var expiresAt: Date?
    /// Hashed, never stored in the clear.
    public var passcodeHash: String?
    public var downloadPolicy: DownloadPolicy
    public var revoked: Bool

    public init(
        shareGrantID: ShareGrantID,
        meetingID: MeetingID,
        recipient: String,
        role: ShareRole,
        scope: ShareScope,
        expiresAt: Date? = nil,
        passcodeHash: String? = nil,
        downloadPolicy: DownloadPolicy = .allowed,
        revoked: Bool = false
    ) {
        self.shareGrantID = shareGrantID
        self.meetingID = meetingID
        self.recipient = recipient
        self.role = role
        self.scope = scope
        self.expiresAt = expiresAt
        self.passcodeHash = passcodeHash
        self.downloadPolicy = downloadPolicy
        self.revoked = revoked
    }
}

public enum ShareRole: String, Sendable, Hashable, Codable, CaseIterable {
    case viewer
    case commenter
    case editor
}

/// What a `ShareGrant` exposes (docs/02 §7 export schema mirrors this scope).
public enum ShareScope: String, Sendable, Hashable, Codable, CaseIterable {
    case fullRecap
    case sectionOnly
    case actionsOnly
    case soundbite
}

public enum DownloadPolicy: String, Sendable, Hashable, Codable, CaseIterable {
    case allowed
    case blocked
}

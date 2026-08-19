import Foundation
import NSPCore

/// A declared request to send content off-device (docs/06 §2). Every field
/// is filled in by the caller *before* asking `NetworkGate`; the gate never
/// inspects payload bytes, only this declaration plus what the meeting's
/// frozen `Policy` and `ConsentRecord` allow.
public struct EgressRequest: Sendable, Hashable {
    public let meetingID: MeetingID
    public let purpose: EgressPurpose
    public let classes: Set<ContentClass>
    public let byteCount: Int
    public let payloadSHA256: String
    public let destination: EgressDestination

    public init(
        meetingID: MeetingID,
        purpose: EgressPurpose,
        classes: Set<ContentClass>,
        byteCount: Int,
        payloadSHA256: String,
        destination: EgressDestination
    ) {
        self.meetingID = meetingID
        self.purpose = purpose
        self.classes = classes
        self.byteCount = byteCount
        self.payloadSHA256 = payloadSHA256
        self.destination = destination
    }
}

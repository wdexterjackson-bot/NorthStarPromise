import Foundation

/// One append-only entry in a meeting's explainable timeline (docs/02 §2).
/// `sampleOffset` is the only ordering key that matters; `wallClock` is
/// display and cross-device anchoring only.
public struct TimelineEvent: Sendable, Hashable, Codable, Identifiable {
    public let eventID: TimelineEventID
    public var id: TimelineEventID { eventID }
    public let owner: ContentOwnerRef
    public let deviceID: DeviceID

    public let type: TimelineEventType
    public let sampleOffset: Int64
    public let wallClock: Date
    public let payload: JSONValue?

    public init(
        eventID: TimelineEventID,
        owner: ContentOwnerRef,
        deviceID: DeviceID,
        type: TimelineEventType,
        sampleOffset: Int64,
        wallClock: Date,
        payload: JSONValue? = nil
    ) {
        self.eventID = eventID
        self.owner = owner
        self.deviceID = deviceID
        self.type = type
        self.sampleOffset = sampleOffset
        self.wallClock = wallClock
        self.payload = payload
    }
}

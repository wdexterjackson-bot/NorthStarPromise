/// Points at one missing segment for a `.partial` meeting, and the device
/// that last held it (docs/02 §2, `Meeting.availability`).
public struct SegmentRef: Sendable, Hashable, Codable {
    public let segmentID: SegmentID
    public let deviceID: DeviceID
    public let sequence: Int

    public init(segmentID: SegmentID, deviceID: DeviceID, sequence: Int) {
        self.segmentID = segmentID
        self.deviceID = deviceID
        self.sequence = sequence
    }
}

/// Whether a meeting's full package is present locally (docs/02 §2,
/// `Meeting.availability`). Never derived silently — each case is an
/// explicit, disclosed state (docs/11 §12).
public enum Availability: Sendable, Hashable, Codable {
    case complete
    case partial(missing: [SegmentRef])
    case recoverable
    case failed
}

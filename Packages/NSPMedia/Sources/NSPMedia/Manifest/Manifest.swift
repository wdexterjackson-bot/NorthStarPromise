import Foundation
import NSPCore

/// A closed segment's entry inside `manifest.json` (docs/02 §4) — a
/// slimmer, disk-durability-focused projection of `NSPPersistence`'s
/// `Segment`, not the entity itself. The manifest only needs what recovery
/// needs: enough to name, order, and verify each file.
public struct ManifestSegmentRecord: Sendable, Hashable, Codable {
    public var sequence: Int
    public var segmentID: SegmentID
    public var file: String
    public var startSample: Int64
    public var sampleCount: Int64
    public var sha256: Data
    public var closedAt: Date

    public init(
        sequence: Int, segmentID: SegmentID, file: String, startSample: Int64, sampleCount: Int64, sha256: Data,
        closedAt: Date
    ) {
        self.sequence = sequence
        self.segmentID = segmentID
        self.file = file
        self.startSample = startSample
        self.sampleCount = sampleCount
        self.sha256 = sha256
        self.closedAt = closedAt
    }
}

/// A timeline entry inside `manifest.json` (docs/02 §4) — same shape as
/// `NSPPersistence`'s `TimelineEvent` minus the identifiers a single-device
/// manifest doesn't need (the manifest itself already names the meeting and
/// device).
public struct ManifestTimelineRecord: Sendable, Hashable, Codable {
    public var type: TimelineEventType
    public var sampleOffset: Int64
    public var wallClock: Date
    public var payload: JSONValue?

    public init(type: TimelineEventType, sampleOffset: Int64, wallClock: Date, payload: JSONValue? = nil) {
        self.type = type
        self.sampleOffset = sampleOffset
        self.wallClock = wallClock
        self.payload = payload
    }
}

/// One entry appended to `manifest.wal` between seals (docs/03 §3.2 step 5,
/// §3.4's "WAL append, not manifest rewrite"). A closed segment and an
/// in-session timeline event both flow through the same append path so
/// nothing needs a full `manifest.json` rewrite mid-session.
public enum ManifestWALEntry: Sendable, Hashable, Codable {
    case segment(ManifestSegmentRecord)
    case timelineEvent(ManifestTimelineRecord)
}

/// The exact on-disk shape of `manifest.json` (docs/02 §4, verbatim).
public struct Manifest: Sendable, Hashable, Codable {
    public struct AudioFormat: Sendable, Hashable, Codable {
        public var codec: AudioCodec
        public var sampleRate: Int
        public var channels: Int
        public var bitRate: Int

        public init(codec: AudioCodec, sampleRate: Int, channels: Int, bitRate: Int) {
            self.codec = codec
            self.sampleRate = sampleRate
            self.channels = channels
            self.bitRate = bitRate
        }
    }

    public struct HealthRollup: Sendable, Hashable, Codable {
        public var interruptions: Int
        public var routeChanges: Int
        public var lowLevelWarnings: Int
        public var thermalPeak: ThermalState

        public init(
            interruptions: Int = 0, routeChanges: Int = 0, lowLevelWarnings: Int = 0,
            thermalPeak: ThermalState = .nominal
        ) {
            self.interruptions = interruptions
            self.routeChanges = routeChanges
            self.lowLevelWarnings = lowLevelWarnings
            self.thermalPeak = thermalPeak
        }
    }

    public struct Integrity: Sendable, Hashable, Codable {
        public var sealed: Bool
        public var repairedTail: Bool

        public init(sealed: Bool = false, repairedTail: Bool = false) {
            self.sealed = sealed
            self.repairedTail = repairedTail
        }
    }

    public var version: Int
    public var meetingID: MeetingID
    public var deviceID: DeviceID
    public var captureMode: CaptureMode
    public var audioFormat: AudioFormat
    public var createdAt: Date
    public var sealedAt: Date?
    public var segments: [ManifestSegmentRecord]
    public var timeline: [ManifestTimelineRecord]
    public var health: HealthRollup
    public var streamSHA256: Data?
    public var integrity: Integrity

    public init(
        meetingID: MeetingID,
        deviceID: DeviceID,
        captureMode: CaptureMode,
        audioFormat: AudioFormat,
        createdAt: Date,
        sealedAt: Date? = nil,
        segments: [ManifestSegmentRecord] = [],
        timeline: [ManifestTimelineRecord] = [],
        health: HealthRollup = HealthRollup(),
        streamSHA256: Data? = nil,
        integrity: Integrity = Integrity(),
        version: Int = 1
    ) {
        self.version = version
        self.meetingID = meetingID
        self.deviceID = deviceID
        self.captureMode = captureMode
        self.audioFormat = audioFormat
        self.createdAt = createdAt
        self.sealedAt = sealedAt
        self.segments = segments
        self.timeline = timeline
        self.health = health
        self.streamSHA256 = streamSHA256
        self.integrity = integrity
    }
}

extension Manifest {
    /// Structural self-check docs/03 §5's recovery relies on before trusting
    /// a loaded manifest: segments are gapless and sequential from zero,
    /// sample math is internally consistent, and a manifest claiming to be
    /// sealed actually has a `sealedAt`. This is deliberately *not* the full
    /// recovery algorithm (`IntegrityChecker`, tail repair — NSP-020, 021,
    /// 025, 055) — just the check NSP-014's writer must never violate.
    public func validates() -> Bool {
        guard segments.map(\.sequence) == Array(0..<segments.count) else { return false }

        var expectedStartSample: Int64 = 0
        for segment in segments {
            guard segment.startSample == expectedStartSample, segment.sampleCount >= 0 else { return false }
            expectedStartSample += segment.sampleCount
        }

        if integrity.sealed {
            guard sealedAt != nil else { return false }
        }

        return true
    }
}

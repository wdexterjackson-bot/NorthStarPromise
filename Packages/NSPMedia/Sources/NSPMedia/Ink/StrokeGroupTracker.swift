import CoreGraphics
import Foundation
import NSPCore

/// One stroke's identity for grouping — this is the tracker's only view of
/// "a stroke": when it landed on the canonical sample timeline and where it
/// landed on the page. It has no knowledge of PencilKit; the ink editor at
/// the call site converts a real `PKStroke` into this before feeding the
/// tracker.
public struct InkStrokeEvent: Sendable, Hashable {
    public let strokeID: UUID
    public let boundingBox: CGRect
    public let sampleOffset: Int64

    public init(strokeID: UUID, boundingBox: CGRect, sampleOffset: Int64) {
        self.strokeID = strokeID
        self.boundingBox = boundingBox
        self.sampleOffset = sampleOffset
    }
}

/// A closed group of strokes, ready to become one `.sketch` `NoteBlock`.
public struct InkStrokeGroup: Sendable, Hashable {
    public let strokeIDs: [UUID]
    public let sampleRange: SampleRange
    public let boundingBox: CGRect

    public init(strokeIDs: [UUID], sampleRange: SampleRange, boundingBox: CGRect) {
        self.strokeIDs = strokeIDs
        self.sampleRange = sampleRange
        self.boundingBox = boundingBox
    }
}

/// Groups ink strokes into `NoteBlock`-sized clusters as they're drawn,
/// purely from stroke timing and position — no PencilKit or UIKit
/// dependency, so the `NOT-002` grouping-tolerance rule (docs/07 §5: "ink
/// strokes close together in time and position are grouped into one shared
/// stamp rather than one per stroke") is unit-testable without a simulator.
public struct StrokeGroupTracker: Sendable {
    /// Two strokes join the same group only if both hold: their sample
    /// offsets are within this many samples of each other, AND their
    /// bounding boxes are within `distanceMargin` of touching.
    public let sampleGapTolerance: Int64
    public let distanceMargin: CGFloat

    private var openStrokeIDs: [UUID] = []
    private var openBoundingBox: CGRect?
    private var openFirstSample: Int64?
    private var openLastSample: Int64?

    public init(sampleRate: Int, timeTolerance: TimeInterval = 1.5, distanceMargin: CGFloat = 48) {
        self.sampleGapTolerance = Int64((Double(sampleRate) * timeTolerance).rounded())
        self.distanceMargin = distanceMargin
    }

    /// Feeds one newly-drawn stroke. If it doesn't fit the group that was
    /// open *before* this stroke arrived, that group closes and is
    /// returned; the new stroke always starts or extends whichever group
    /// is open afterward.
    public mutating func handle(_ event: InkStrokeEvent) -> InkStrokeGroup? {
        var closedGroup: InkStrokeGroup?
        if let lastSample = openLastSample, let boundingBox = openBoundingBox {
            let withinTime = abs(event.sampleOffset - lastSample) <= sampleGapTolerance
            let withinDistance =
                boundingBox.insetBy(dx: -distanceMargin, dy: -distanceMargin).intersects(event.boundingBox)
            if !(withinTime && withinDistance) {
                closedGroup = closeOpenGroup()
            }
        }
        openStrokeIDs.append(event.strokeID)
        openFirstSample = min(openFirstSample ?? event.sampleOffset, event.sampleOffset)
        openLastSample = max(openLastSample ?? event.sampleOffset, event.sampleOffset)
        openBoundingBox = openBoundingBox?.union(event.boundingBox) ?? event.boundingBox
        return closedGroup
    }

    /// Force-closes whatever group is open — called by the UI layer's own
    /// idle timer, on tool switch away from ink, or when recording
    /// pauses/stops. Returns `nil` if nothing was open.
    @discardableResult
    public mutating func closeOpenGroup() -> InkStrokeGroup? {
        guard !openStrokeIDs.isEmpty, let first = openFirstSample, let last = openLastSample,
            let box = openBoundingBox
        else {
            return nil
        }
        let group = InkStrokeGroup(
            strokeIDs: openStrokeIDs, sampleRange: SampleRange(startSample: first, endSample: last),
            boundingBox: box)
        openStrokeIDs = []
        openFirstSample = nil
        openLastSample = nil
        openBoundingBox = nil
        return group
    }
}

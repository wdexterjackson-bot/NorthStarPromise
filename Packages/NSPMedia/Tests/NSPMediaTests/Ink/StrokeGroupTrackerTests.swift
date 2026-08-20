import CoreGraphics
import Foundation
import Testing

@testable import NSPMedia

/// The `NOT-002` acceptance test: stroke-group timestamping must merge
/// strokes that are close in time and position, and split ones that
/// aren't, so tap-a-stroke-to-seek lands on a meaningfully-sized group
/// rather than one block per pen-down.
@Suite("StrokeGroupTracker")
struct StrokeGroupTrackerTests {
    private static let sampleRate = 48000

    private static func event(_ id: UUID = UUID(), positionX: CGFloat, seconds: Double) -> InkStrokeEvent {
        InkStrokeEvent(
            strokeID: id, boundingBox: CGRect(x: positionX, y: 0, width: 10, height: 10),
            sampleOffset: Int64(seconds * Double(sampleRate)))
    }

    @Test func strokesCloseInTimeAndSpaceMergeIntoOneGroup() {
        var tracker = StrokeGroupTracker(sampleRate: Self.sampleRate)
        let first = Self.event(positionX: 0, seconds: 1.0)
        let second = Self.event(positionX: 15, seconds: 1.4)

        #expect(tracker.handle(first) == nil)
        #expect(tracker.handle(second) == nil)

        let group = tracker.closeOpenGroup()
        #expect(group?.strokeIDs == [first.strokeID, second.strokeID])
        #expect(group?.sampleRange.startSample == first.sampleOffset)
        #expect(group?.sampleRange.endSample == second.sampleOffset)
    }

    @Test func strokesFarApartInTimeSplitIntoSeparateGroups() {
        var tracker = StrokeGroupTracker(sampleRate: Self.sampleRate, timeTolerance: 1.5)
        let first = Self.event(positionX: 0, seconds: 1.0)
        let second = Self.event(positionX: 5, seconds: 5.0)

        #expect(tracker.handle(first) == nil)
        let closed = tracker.handle(second)

        #expect(closed?.strokeIDs == [first.strokeID])
        let remaining = tracker.closeOpenGroup()
        #expect(remaining?.strokeIDs == [second.strokeID])
    }

    @Test func strokesFarApartInSpaceSplitEvenWhenCloseInTime() {
        var tracker = StrokeGroupTracker(sampleRate: Self.sampleRate, distanceMargin: 48)
        let first = Self.event(positionX: 0, seconds: 1.0)
        let second = Self.event(positionX: 500, seconds: 1.05)

        #expect(tracker.handle(first) == nil)
        let closed = tracker.handle(second)

        #expect(closed?.strokeIDs == [first.strokeID])
    }

    @Test func closingWithNothingOpenReturnsNil() {
        var tracker = StrokeGroupTracker(sampleRate: Self.sampleRate)
        #expect(tracker.closeOpenGroup() == nil)
    }

    @Test func sampleRangeSpansOutOfOrderOffsetsCorrectly() {
        var tracker = StrokeGroupTracker(sampleRate: Self.sampleRate)
        let first = Self.event(positionX: 0, seconds: 2.0)
        let second = Self.event(positionX: 5, seconds: 1.8)

        _ = tracker.handle(first)
        _ = tracker.handle(second)
        let group = tracker.closeOpenGroup()

        #expect(group?.sampleRange.startSample == second.sampleOffset)
        #expect(group?.sampleRange.endSample == first.sampleOffset)
    }
}

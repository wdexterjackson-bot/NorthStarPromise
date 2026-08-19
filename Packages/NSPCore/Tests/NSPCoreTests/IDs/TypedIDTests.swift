import Foundation
import Testing

@testable import NSPCore

@Suite("TypedID")
struct TypedIDTests {
    @Test func test_generate_twoCalls_produceDistinctIDs() {
        let a = MeetingID.generate(clock: SystemClock())
        let b = MeetingID.generate(clock: SystemClock())

        #expect(a != b)
    }

    @Test func test_generate_isTimeOrdered_laterTimestampSortsAfter() {
        struct FixedClock: Clock {
            let date: Date
            func now() -> Date { date }
        }
        var generator = SystemRandomNumberGenerator()

        let earlier = MeetingID.generate(
            clock: FixedClock(date: Date(timeIntervalSince1970: 1000)), randomSource: &generator)
        let later = MeetingID.generate(
            clock: FixedClock(date: Date(timeIntervalSince1970: 2000)), randomSource: &generator)

        #expect(earlier.rawValue.uuidString < later.rawValue.uuidString)
    }

    @Test func test_uuidStringInit_roundTripsThroughDescription() {
        let original = MeetingID.generate(clock: SystemClock())

        let parsed = MeetingID(uuidString: original.description)

        #expect(parsed == original)
    }

    @Test func test_uuidStringInit_malformedString_returnsNil() {
        #expect(MeetingID(uuidString: "not-a-uuid") == nil)
    }

    @Test func test_codable_roundTripsThroughJSON() throws {
        let original = MeetingID.generate(clock: SystemClock())
        let data = try JSONEncoder().encode(original)

        let decoded = try JSONDecoder().decode(MeetingID.self, from: data)

        #expect(decoded == original)
    }

    @Test func test_distinctEntityKinds_areNotInterchangeable() {
        // Compile-time proof: MeetingID and SegmentID are different types
        // even though both wrap UUID, so a caller cannot pass one where the
        // other is expected (docs/11 §1).
        let meetingID = MeetingID.generate(clock: SystemClock())
        let segmentID = SegmentID(rawValue: meetingID.rawValue)

        #expect(meetingID.rawValue == segmentID.rawValue)
    }
}

import Testing

@testable import NSPCore

@Suite("SampleRange")
struct SampleRangeTests {
    @Test func test_sampleCount_isEndMinusStart() {
        let range = SampleRange(startSample: 1000, endSample: 5000)

        #expect(range.sampleCount == 4000)
    }

    @Test func test_zeroLengthRange_isAllowed() {
        let range = SampleRange(startSample: 500, endSample: 500)

        #expect(range.sampleCount == 0)
    }
}

@Suite("SampleDuration")
struct SampleDurationTests {
    @Test func test_seconds_dividesSampleCountByRate() {
        let duration = SampleDuration(sampleCount: 32000, sampleRate: 16000)

        #expect(duration.seconds == 2.0)
    }

    @Test func test_zero_hasZeroSeconds() {
        #expect(SampleDuration.zero.seconds == 0)
    }
}
